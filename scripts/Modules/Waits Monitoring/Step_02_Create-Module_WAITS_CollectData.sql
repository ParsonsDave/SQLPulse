USE [SQLPulse]
GO


SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE PROCEDURE [Pulse].[Module_Waits_CollectData]

AS
BEGIN
--	-- SET NOCOUNT ON added to prevent extra result sets from
--	-- interfering with SELECT statements.
	SET NOCOUNT ON;

/* *********************************************************************************

Source: SQLPulse: Get WAIT Statistics
Build: 2.2
Build Date: 2026-03-01

This sproc gathers and records SQL Wait data

It performs the following activities:

   1) Get the last server restart time via the stored procedure [Pulse].[UpdateLastServerStart]
   2) Declare the internal variables and set their values
   3) INSERT Wait Data into table: Waits_StatsArchive
	-> This table is a running record of wait stats to be used by a consultant or someone knowledgeable
	-> The rollup will be done via the entires in the table Waits_StatsByMonth
	-> NOTE!!
	-> This query needs to be tuned;
	-> most or all of waits that would be considered 'OTHER' should be filtered out entirely
	-> The ORDER BY clause is not necessary, but is included so the query can be easily pulled out of this sproc for manual use
   4) Restart boundary detection
	-> Create an entry in the Waits_StatsByMonth table to retain data from before an instance restart
   5) Detect month boundary
	-> This has TWO actions: when the month changeover happens,
	-> insert the previous waits (the last waits of the month
	-> and then the current data as the start of the month baseline
   6) Cleanup
	-> This space intentionally blank

This query doesn't currently cover Availability Groups; code needs to be added to 
determine if this is an AG node and the waits gathered.

AG Wait notes for later:

Wait Type	Description	Possible Cause
HADR_SYNC_COMMIT	Primary replica is waiting for the secondary to harden the log before committing (synchronous mode).	Network latency, slow disk on secondary, high transaction volume.
HADR_DATABASE_FLOW_CONTROL	Flow control is throttling log send rate to avoid overwhelming the secondary.	Secondary is slow to process log blocks.
HADR_LOGCAPTURE_WAIT	Log capture thread is idle, waiting for new log records.	Low activity or log capture delays.
HADR_LOGSEND_QUEUE	Log send thread is waiting to send log blocks to the secondary.	Network congestion, secondary not keeping up.
HADR_WORK_QUEUE	Worker thread is waiting for work in the AG worker pool.	Normal when idle; high values may indicate backlog.
HADR_TRANSPORT_DBR	Waits related to database replica transport.	Network or endpoint issues.

********************************************************************************* */


-- 1) Get the last server restart time via the stored procedure [Pulse].[UpdateLastServerStart]

	EXECUTE [Pulse].[UpdateLastServerStart]

-- 2) Declare the internal variables and set their values
		
		DECLARE @LastStartup datetime2(3) = (SELECT MAX(RestartDate) FROM Pulse.tblServerRestartDates);
		DECLARE @EventTimeUTC datetime2(3) = (SELECT SYSUTCDATETIME());
		DECLARE @EventTimeLocal datetime2(3) = (SELECT SYSDATETIME());
		DECLARE @RollupMonth date = DATEFROMPARTS(YEAR(@EventTimeUTC), MONTH(@EventTimeUTC), 1);
	
	-- Calculate the number of seconds since that time; Default to 1 if it's somehow 0
		
		DECLARE @UptimeSeconds int = DATEDIFF(second, @LastStartup, @EventTimeUTC);

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

	-- Get the most recent archive entry for clearing obsolete data (Step 7)

		DECLARE @LatestWaits datetime2(3) = (SELECT MAX(EventTimeUTC) FROM Pulse.Waits_StatsArchive)
		DECLARE @LatestWaitsLocal datetime2(3) = (SELECT MAX(EventTimeLocal) FROM Pulse.Waits_StatsArchive)
		SELECT @LatestWaits as LatestWaits, @EventTimeUTC as EventTimeUTC

-- 3) INSERT Wait Data into table: Waits_StatsArchive
	-- This table is a running record of wait stats to be used by a consultant or someone knowledgeable
	-- The rollup will be done via the entires in the table Waits_StatsByMonth
	-- NOTE!!
	-- This query needs to be tuned;
	-- most or all of waits that would be considered 'OTHER' should be filtered out entirely
	-- The ORDER BY clause is not necessary, but is included so the query can be easily pulled out of this sproc for manual use

	INSERT INTO Pulse.Waits_StatsArchive
	
	SELECT 
		@EventTimeUTC as EventTimeUTC
		, @EventTimeLocal as EventTimeLocal
		, @TotalServerTimeSeconds
		, ws.wait_type as WaitType
		, CASE 
        -- Availability Group Waits
        WHEN ws.wait_type IN ('HADR_SYNC_COMMIT', 'HADR_LOGCAPTURE_SYNC', 'HADR_REPLICA_SYNC_STATUS') THEN 'AGSync'
        WHEN ws.wait_type IN ('PARALLEL_REDO_WORKER_WAIT_FOR_WORK', 'REDO_THREAD_PENDING_WORK', 'PARALLEL_REDO_DRAIN_WORKER') THEN 'AGSecondary'
        
        -- Existing Categories
        WHEN ws.wait_type IN ('SOS_SCHEDULER_YIELD','THREADPOOL') THEN 'CPU'
        WHEN ws.wait_type = 'CXPACKET' THEN 'Parallelism'
        WHEN ws.wait_type IN ('RESOURCE_SEMAPHORE','CMEMTHREAD','RESOURCE_SEMAPHORE_QUERY_COMPILE') THEN 'Memory'
        WHEN ws.wait_type LIKE 'PAGEIOLATCH%' OR ws.wait_type IN ('WRITELOG','IO_COMPLETION') THEN 'Disk'
        WHEN ws.wait_type LIKE 'LCK_M_%' THEN 'Blocking'
        WHEN ws.wait_type IN ('LATCH_EX', 'LATCH_SH') THEN 'Latches'
        WHEN ws.wait_type = 'ASYNC_NETWORK_IO' THEN 'DataOutput'
        ELSE 'Other'
    END AS Category
		, ROUND(ws.wait_time_ms / 1000.0, 2) AS WaitSeconds
		, ROUND((ws.wait_time_ms - ws.signal_wait_time_ms) / 1000.0, 2) AS ResourceSeconds
		, ROUND(ws.signal_wait_time_ms / 1000.0, 2) AS SignalSeconds
		, ROUND(((ws.wait_time_ms / 1000.0) / @TotalServerTimeSeconds * 100), 2) AS TotalWaitPct
		, ws.waiting_tasks_count
	FROM sys.dm_os_wait_stats AS ws
	WHERE ws.waiting_tasks_count > 0

	-- Filter out BENIGN waits (later to be in a dedicated table)

	AND ws.wait_type NOT IN (
		'SLEEP_TASK','SLEEP_SYSTEMTASK','LAZYWRITER_SLEEP','SQLTRACE_BUFFER_FLUSH',
		'XE_DISPATCHER_WAIT','XE_TIMER_EVENT','BROKER_TO_FLUSH','BROKER_TASK_STOP',
		'BROKER_EVENTHANDLER','FT_IFTS_SCHEDULER_IDLE_WAIT','CHECKPOINT_QUEUE',
		'LOGMGR_QUEUE','REQUEST_FOR_DEADLOCK_SEARCH','WAITFOR','WAITFOR_TASKSHUTDOWN',
		'HADR_FILESTREAM_IOMGR_IOCOMPLETION','HADR_TIMER_TASK','HADR_WORK_QUEUE',
		'DIRTY_PAGE_POLL','SOS_WORK_DISPATCHER','CXCONSUMER','BROKER_RECEIVE_WAITFOR',
		'BROKER_TRANSMITTER','DISPATCHER_QUEUE_SEMAPHORE','FT_IFTSHC_MUTEX',
		'XE_DISPATCHER_JOIN','LATCH_SH','LATCH_UP','LATCH_NL','REPL_SCHEMA_ACCESS',
		'REPL_HISTORYCACHE_ACCESS','REPL_CACHE_ACCESS','REPL_TRANSPORT','CLR_AUTO_EVENT',
		'CLR_MANUAL_EVENT','CLR_SEMAPHORE','LOGMGR_RESERVE_APPEND','LOGMGR_FLUSH',
		'TRACEWRITE','WAIT_XTP_HOST_WAIT','WAIT_XTP_OFFLINE_CKPT_NEW_LOG',
		'WAIT_XTP_CKPT_CLOSE'
		)

	ORDER BY Category, TotalWaitPct DESC;

-- 4) Restart boundary detection
	-- Create an entry in the WaitsByMonth table to retain data from before an instance restart

    IF @LatestWaits IS NOT NULL
       AND @LastStartup > @LatestWaits
    BEGIN
        INSERT INTO Pulse.Waits_StatsByMonth (
              SnapshotDateUTC
			  , SnapshotDateLocal
			  , SnapshotType
			  , ServerName
			  , RollupMonth
			  , TotalServerTimeSeconds
			  , WaitType
			  , Category
			  , WaitSeconds
			  , ResourceSeconds
			  , SignalSeconds
			  , TotalWaitPct
			  , WaitingTasksCount
        )
        SELECT
              @LatestWaits
			  , @LatestWaitsLocal
              , 'PreRestart'
              , @@SERVERNAME
              , @RollupMonth
			  , TotalServerTimeSeconds
              , WaitType
			  , Category
              , WaitSeconds
			  , ResourceSeconds
			  , SignalSeconds
			  , TotalWaitPct
			  , WaitingTasksCount
        FROM Pulse.Waits_StatsArchive
        WHERE EventTimeUTC = @LatestWaits;
    END;


-- 5) Detect month boundary
	-- This has TWO actions: when the month changeover happens,
	-- insert the previous waits (the last waits of the month
	-- and then the current data as the start of the month baseline

    IF @LatestWaits IS NOT NULL
       AND (YEAR(@LatestWaits) <> YEAR(@EventTimeUTC)
         OR MONTH(@LatestWaits) <> MONTH(@EventTimeUTC))
    BEGIN
        INSERT INTO Pulse.Waits_StatsByMonth (
              SnapshotDateUTC
			  , SnapshotDateLocal
			  , SnapshotType
			  , ServerName
			  , RollupMonth
			  , TotalServerTimeSeconds
			  , WaitType
			  , Category
			  , WaitSeconds
			  , ResourceSeconds
			  , SignalSeconds
			  , TotalWaitPct
			  , WaitingTasksCount
        )
        SELECT
              @LatestWaits
			  , @LatestWaitsLocal
              , 'EndOfMonth'
              , @@SERVERNAME
              , @RollupMonth
			  , TotalServerTimeSeconds
              , WaitType
			  , Category
              , WaitSeconds
			  , ResourceSeconds
			  , SignalSeconds
			  , TotalWaitPct
			  , WaitingTasksCount
        FROM Pulse.Waits_StatsArchive
        WHERE EventTimeUTC = @LatestWaits;


	-----------------------------------------------------------------------------
	-- Insert StartOfMonth snapshot immidiately
	-----------------------------------------------------------------------------


        INSERT INTO Pulse.Waits_StatsByMonth (
              SnapshotDateUTC
			  , SnapshotDateLocal
			  , SnapshotType
			  , ServerName
			  , RollupMonth
			  , TotalServerTimeSeconds
			  , WaitType
			  , Category
			  , WaitSeconds
			  , ResourceSeconds
			  , SignalSeconds
			  , TotalWaitPct
			  , WaitingTasksCount
        )
        SELECT
              @EventTimeUTC
			  , @EventTimeLocal
              , 'StartOfMonth'
              , @@SERVERNAME
              , DATEADD(MONTH, 1, @RollupMonth)
			  , TotalServerTimeSeconds
              , WaitType
			  , Category
              , WaitSeconds
			  , ResourceSeconds
			  , SignalSeconds
			  , TotalWaitPct
			  , WaitingTasksCount
        FROM Pulse.Waits_StatsArchive
        WHERE EventTimeUTC = @EventTimeUTC
    END;


-- 6) Cleanup

	-- This space intentionally blank

END
GO


