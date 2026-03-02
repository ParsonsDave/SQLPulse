USE [SQLPulse]
GO


SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO



CREATE PROCEDURE [Pulse].[Module_CPU_CollectData]
	
	/* *********************************************************************************

	There are no input or output variables at this time

	********************************************************************************* */
	

AS

BEGIN

/* *********************************************************************************

Source: SQLPulse: Get CPU Utilization
Build: 1.2
Build Date: 2026-01-25

This sproc gathers and records data for CPU utilization
NOTE: This is an average CPU counter and does not gather granular data on individual cores
NOTE: This is to reduce communication spam. A comparison is done between the previous entry and the new entry to evaluate for the Agent job

It performs the following activities:

   1) Get the last server restart time via the stored procedure [dbo].[UpdateLastServerStart]
   2) Declare the internal variables
   3) Create Temp Table for use in clearing duplicates
   4) Grab the last 4 hours of CPU usage from sys.dm_os_ring_buffers and put it in the temp table
   5) Insert non-duplicate values into the main table
		-- Duplicates are evaluated on the MINUTE by a CAST to smalldatetime, which sets all seconds & fractions thereof to 0
   6) Debug Line if you pull this out of the sproc and into a normal query
   7) Object cleanup

** NOTE ** - Ensure that the AlertVersion variable is always kept up-to-date!
** NOTE2 ** - The AlertVersion variable does not currently exist

********************************************************************************* */

-- 1) Get the last server restart time via the stored procedure [dbo].[UpdateLastServerStart]

	EXECUTE [Pulse].[UpdateLastServerStart]

-- 2) Declare the internal variables

	DECLARE @Now BIGINT
	SELECT  @Now = ms_ticks FROM sys.dm_os_sys_info 


-- 3) Create Temp Table for use in clearing duplicates

	CREATE TABLE #tempCPUUsage(
		[EventTimeUTC] [datetime2] (3) NOT NULL,
		[EventTimeLocal] [datetime2] (3) NOT NULL,
		[SqlService] [int] NOT NULL,
		[IdleProcess] [int] NOT NULL,
		[NonSqlProcess] [int] NOT NULL
		)
	

-- 4) Grab the last 4 hours of CPU usage from sys.dm_os_ring_buffers and put it in the temp table

	INSERT INTO #tempCPUUsage

	SELECT  DATEADD(ms, -1 * ( @Now - [timestamp] ), SYSUTCDATETIME()) AS EventTimeUTC,
			DATEADD(ms, -1 * ( @Now - [timestamp] ), GETDATE()) AS EventTimeLocal,
	        SQLService, 
	        Idle,
	        100 - Idle - SQLService AS NonSqlProcesses
	FROM    ( SELECT    record.value('(./Record/@id)[1]', 'INT') AS record_id,
	                    record.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'INT') AS Idle,
	                    record.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 'INT') AS SQLService, 
                    timestamp
          FROM      ( SELECT    timestamp, CONVERT(XML, record) AS record
                      FROM      sys.dm_os_ring_buffers
                      WHERE     ring_buffer_type = N'RING_BUFFER_SCHEDULER_MONITOR'
                                AND record LIKE '%%'
	                    ) AS x
		) AS y
	ORDER BY 1


-- 5) Insert non-duplicate values into the main table
	-- Duplicates are evaluated on the MINUTE by a CAST to smalldatetime, which sets all seconds & fractions thereof to 0

	INSERT INTO [Pulse].[CPU_Data] (EventTimeUTC, EventTimeLocal, SqlService, IdleProcess, NonSqlProcess)
	SELECT EventTimeUTC, EventTimeLocal, SqlService, IdleProcess, NonSqlProcess
	FROM #tempCPUUsage t
	WHERE NOT EXISTS (SELECT 1 FROM [Pulse].[CPU_Data] d
	WHERE (CAST(EventTimeLocal AS smalldatetime) = CAST(t.EventTimeLocal AS smalldatetime)));


-- 6) Debug Line if you pull this out of the sproc and into a normal query
	
	--Select * from #tempCPUUsage


-- 7) Object cleanup

	drop table #tempCPUUsage


END
GO


