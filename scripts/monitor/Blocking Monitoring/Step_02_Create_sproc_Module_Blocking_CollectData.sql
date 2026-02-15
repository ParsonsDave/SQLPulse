USE [SQLPulse]
GO
/****** Object:  StoredProcedure [dbo].[Module_Blocking_CollectData]    Script Date: 1/18/2026 7:22:39 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


ALTER PROCEDURE [dbo].[Module_Blocking_CollectData]
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

    /* *********************************************************************************

Source: SQLPulse: Get Blocking Statistics
Build: 1.0
Build Date: 2026-01-18

This sproc gathers and records SQL Blocking data

It does this in two ways:

	1) It gets a snapshot of blocked sessions
	2) It calculates the cumulative blocking time, since engine startup, per database

#1 is very straightforward - the data collected is stored deirectly in the target table
#2 does require some additional work; if the engine hasn't restarted since the last collection date,
   delete the latest entry, but in either case, insert the new data

Both will be combined with the Blocking waits gathered by that module for reporting

It performs the following activities:

   1) Get the last server restart time via the stored procedure [dbo].[UpdateLastServerStart]
   2) Declare the internal variables and set their values
   3) INSERT blocked session data snapshot into table BlockingSessions
   4) Check if the server has restarted since the most recent entry in table BlockingTimeDatabases
		-- If not, delete the most recent data set in the table
   5) INSERT database blocking time into table BlockingTimeDatabases
   6) Object cleanup

** NOTE ** - Ensure that the AlertVersion variable is always kept up-to-date!
	--Note 2: There is currently no AlertVersion variable; perhaps later

********************************************************************************* */


-- 1) Get the last server restart time via the stored procedure [dbo].[UpdateLastServerStart]

	EXECUTE [dbo].[UpdateLastServerStart]

-- 2) Declare the internal variables and set their values
		
		DECLARE @LastStartup datetime = (SELECT MAX(RestartDate) FROM tblServerRestartDates)
		DECLARE @EventTimeUTC datetime = (SELECT SYSUTCDATETIME())
		DECLARE @EventTimeLocal datetime = (SELECT SYSDATETIME())
	
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

	-- Get the most recent data entry for clearing BlockingTimeDatabases (Step 4), if necessary

		DECLARE @LatestBlockingData datetime = (SELECT MAX(EventTimeUTC) FROM BlockingTimeDatabases)


-- 3) INSERT blocked session data snapshot into table BlockingSessions

	INSERT INTO BlockingSessions

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


-- 4) Check if the server has restarted since the most recent entry in table BlockingTimeDatabases
		-- If not, delete the most recent data set in the table

	IF (@LatestBlockingData IS NOT NULL AND @LatestBlockingData > @LastStartup)
		BEGIN
			DELETE BlockingTimeDatabases WHERE EventTimeUTC = @LatestBlockingData
		END

-- 5) INSERT database blocking time into table BlockingTimeDatabases

	;WITH Stats AS
	(
		SELECT 
			database_id,
			RowLockWaitMs  = SUM(row_lock_wait_in_ms),
			PageLockWaitMs = SUM(page_lock_wait_in_ms)
		FROM sys.dm_db_index_operational_stats(NULL, NULL, NULL, NULL)
		GROUP BY database_id
	)
	INSERT INTO BlockingTimeDatabases
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


-- Object cleanup
	-- This space intentionally blank

	


END
