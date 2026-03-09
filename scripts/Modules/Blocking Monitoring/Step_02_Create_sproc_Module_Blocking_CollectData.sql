USE [SQLPulse]
GO


SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO



CREATE PROCEDURE [Pulse].[Module_Blocking_CollectData]
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

    /* *********************************************************************************

Source: SQLPulse: Get Blocking Statistics
Build: 2.0
Build Date: 2026-03-05

This sproc gathers and records SQL Blocking data

It does this in two ways:

	1) It gets a snapshot of blocked sessions
	2) It tracks blocking time per database via sys.dm_db_index_operational_stats 

#1 is very straightforward - the data collected is stored deirectly in the target table
#2 is copied directly from the Waits module. It archives all data, then creates
   snapshots to track dat by month. The latter is for the monthly rollup procedure,
   while the former is for historical purposes

Both will be combined with the blocking Waits gathered by that module for reporting

It performs the following activities:

   1) Get the last server restart time via the stored procedure [Pulse].[Module_Core_ServerRestartDates]
   2) Declare the internal variables and set their values
   3) INSERT blocked session data snapshot into table Blocking_Sessions
   4) INSERT database blocking time into table Blocking_TimeDatabases
	-> This table is a running record of wait stats to be used by a consultant or someone knowledgeable
	-> The rollup will be done via the entires in the table Blocking_TimeByMonth
   5) Restart boundary detection
	-> Create an entry in the Blocking_TimeByMonth table to retain data from before an instance restart
   6) Detect month boundary
	-> This has TWO actions: when the month changeover happens,
	-> insert the previous waits (the last waits of the month
	-> and then the current data as the start of the month baseline
   7) Cleanup

** NOTE ** - Ensure that the AlertVersion variable is always kept up-to-date!
	--Note 2: There is currently no AlertVersion variable; perhaps later

********************************************************************************* */


-- 1) Get the last server restart time via the stored procedure [Pulse].[Module_Core_ServerRestartDates]

	EXECUTE Pulse.Module_Core_ServerRestartDates

-- 2) Declare the internal variables and set their values
		
		DECLARE @LastStartup datetime = (SELECT MAX(RestartDate) FROM Core_ServerRestartDates);
		DECLARE @EventTimeUTC datetime = (SELECT SYSUTCDATETIME());
		DECLARE @EventTimeLocal datetime = (SELECT SYSDATETIME());
		DECLARE @RollupMonth date = DATEFROMPARTS(YEAR(@EventTimeUTC), MONTH(@EventTimeUTC), 1);
	
	-- Calculate the number of seconds since that time; Default to 1 if it's somehow 0
		
		DECLARE @UptimeSeconds int = DATEDIFF(second, @LastStartup, @EventTimeUTC)

		IF @UptimeSeconds = 0
			SET @UptimeSeconds = 1
		
	-- Get the number of processors to be able to calculate the total CPU time since restart
	-- NOTE!! This value respects the actual limitation of SQL configuration / licensing
	-- For example, Sql Standard is limited to 4 sockets or 24 cores, whichever is smaller,
	-- so a system with 8 sockets, 2 cores per socket (total 16 cores) would report back with this 
	-- query with the proper license value of 8
		
		DECLARE @LogicalProcessors int = (SELECT COUNT(*) FROM sys.dm_os_schedulers WHERE status = 'VISIBLE ONLINE')
		
		-- Alternate: this works but may have future limitations
		-- DECLARE @LogicalProcessors int = (SELECT COUNT (*) FROM sys.dm_os_schedulers WHERE scheduler_id < 1048576 AND is_online = 1)
	
	-- Calculate the total number of processing seconds since the last restart, accounting for all CPUs
	
		DECLARE @TotalServerTimeSeconds float = (@UptimeSeconds * @LogicalProcessors)

	-- Get the most recent data entry for clearing Blocking_TimeDatabases (Step 4), if necessary

		--DECLARE @LatestBlockingData datetime = (SELECT MAX(EventTimeUTC) FROM Pulse.Blocking_TimeDatabases)
		DECLARE @LatestBlocking datetime2(3) = (SELECT MAX(EventTimeUTC) FROM Pulse.Blocking_TimeDatabases)
		DECLARE @LatestBlockingLocal datetime2(3) = (SELECT MAX(EventTimeLocal) FROM Pulse.Blocking_TimeDatabases)
		SELECT @LatestBlocking as LatestWaits, @EventTimeUTC as EventTimeUTC


-- 3) INSERT blocked session data snapshot into table Blocking_Sessions

	INSERT INTO Pulse.Blocking_Sessions

	SELECT
		@EventTimeUTC
		,@EventTimeLocal
		,er.session_id
		,er.blocking_session_id
		,er.wait_type
		,er.wait_time
		,er.database_id
		,sd.name
		,er.sql_handle
		,er.command
		,br.command
	FROM sys.dm_exec_requests er
	INNER JOIN sys.databases sd
		ON er.database_id = sd.database_id
	LEFT JOIN sys.dm_exec_requests br
		ON er.blocking_session_id = br.session_id
	WHERE er.blocking_session_id <> 0


-- 4) INSERT database blocking time into table Blocking_TimeDatabases
	-- This table is a running record of wait stats to be used by a consultant or someone knowledgeable
	-- The rollup will be done via the entires in the table Blocking_TimeByMonth

	;WITH Stats AS
	(
		SELECT 
			database_id,
			RowLockWaitMs  = SUM(row_lock_wait_in_ms),
			PageLockWaitMs = SUM(page_lock_wait_in_ms)
		FROM sys.dm_db_index_operational_stats(NULL, NULL, NULL, NULL)
		GROUP BY database_id
	)
	INSERT INTO Pulse.Blocking_TimeDatabases
	(
		EventTimeUTC,
		EventTimeLocal,
		DatabaseID,
		DatabaseName,
		RowLockWaitMs,
		PageLockWaitMs,
		UptimeSeconds,
		ProcessorCount,
		TotalProcessorTimeSeconds
	)
	SELECT
		@EventTimeUTC
		,@EventTimeLocal
		,s.database_id
		,DB_NAME(s.database_id)
		,s.RowLockWaitMs
		,s.PageLockWaitMs
		,@UptimeSeconds
		,@LogicalProcessors
		,@TotalServerTimeSeconds
	FROM Stats s
	CROSS JOIN sys.dm_os_sys_info si;


-- 5) Restart boundary detection
	-- Create an entry in the Blocking_TimeByMonth table to retain data from before an instance restart

	IF @LatestBlocking IS NOT NULL
       AND @LastStartup > @LatestBlocking
    BEGIN
        INSERT INTO Pulse.Blocking_TimeByMonth (
              	[SnapshotDateUTC]
				, [SnapshotDateLocal]
				, [SnapshotType]
				, [ServerName]
				, [RollupMonth]
				, [DatabaseID]
				, [DatabaseName]
				, [RowLockWaitMs]
				, [PageLockWaitMs]
				-- , [TotalBlockingWaitMs]  AS ([RowLockWaitMs]+[PageLockWaitMs]) PERSISTED
				, [UptimeSeconds]
				, [ProcessorCount]
				, [TotalProcessorTimeSeconds]
        )
        SELECT
              @LatestBlocking
			  , @LatestBlockingLocal
              , 'PreRestart'
              , @@SERVERNAME
              , @RollupMonth
			  , DatabaseID
              , DatabaseName
			  , RowLockWaitMs
              , PageLockWaitMs
			  -- , TotalBlockingWaitMs
			  , UptimeSeconds
			  , ProcessorCount
			  , TotalProcessorTimeSeconds
        FROM Pulse.Blocking_TimeDatabases
        WHERE EventTimeUTC = @LatestBlocking;
    END;


-- 6) Detect month boundary
	-- This has TWO actions: when the month changeover happens,
	-- insert the previous waits (the last waits of the month
	-- and then the current data as the start of the month baseline

    IF @LatestBlocking IS NOT NULL
       AND (YEAR(@LatestBlocking) <> YEAR(@EventTimeUTC)
         OR MONTH(@LatestBlocking) <> MONTH(@EventTimeUTC))
    BEGIN
        INSERT INTO Pulse.Blocking_TimeByMonth (
              	[SnapshotDateUTC]
				, [SnapshotDateLocal]
				, [SnapshotType]
				, [ServerName]
				, [RollupMonth]
				, [DatabaseID]
				, [DatabaseName]
				, [RowLockWaitMs]
				, [PageLockWaitMs]
				-- , [TotalBlockingWaitMs]  AS ([RowLockWaitMs]+[PageLockWaitMs]) PERSISTED
				, [UptimeSeconds]
				, [ProcessorCount]
				, [TotalProcessorTimeSeconds]
        )
        SELECT
              @LatestBlocking
			  , @LatestBlockingLocal
              , 'EndOfMonth'
              , @@SERVERNAME
              , @RollupMonth
			  , DatabaseID
              , DatabaseName
			  , RowLockWaitMs
              , PageLockWaitMs
			  -- , TotalBlockingWaitMs
			  , UptimeSeconds
			  , ProcessorCount
			  , TotalProcessorTimeSeconds
        FROM Pulse.Blocking_TimeDatabases
        WHERE EventTimeUTC = @LatestBlocking;
    
	-----------------------------------------------------------------------------
	-- Insert StartOfMonth snapshot immediately
	-----------------------------------------------------------------------------

		INSERT INTO Pulse.Blocking_TimeByMonth (
              	[SnapshotDateUTC]
				, [SnapshotDateLocal]
				, [SnapshotType]
				, [ServerName]
				, [RollupMonth]
				, [DatabaseID]
				, [DatabaseName]
				, [RowLockWaitMs]
				, [PageLockWaitMs]
				-- , [TotalBlockingWaitMs]  AS ([RowLockWaitMs]+[PageLockWaitMs]) PERSISTED
				, [UptimeSeconds]
				, [ProcessorCount]
				, [TotalProcessorTimeSeconds]
        )
        SELECT
              @LatestBlocking
			  , @LatestBlockingLocal
              , 'StartOfMonth'
              , @@SERVERNAME
              , @RollupMonth
			  , DatabaseID
              , DatabaseName
			  , RowLockWaitMs
              , PageLockWaitMs
			  -- , TotalBlockingWaitMs
			  , UptimeSeconds
			  , ProcessorCount
			  , TotalProcessorTimeSeconds
        FROM Pulse.Blocking_TimeDatabases
        WHERE EventTimeUTC = @LatestBlocking;

    END;


-- 7) Cleanup

	-- This space intentionally blank

	
END
GO


