USE [SQLPulse]
GO


SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE PROCEDURE [Pulse].[Module_Disk_CollectLatency]
	
	/* *********************************************************************************

	There are no input or output variables at this time

	********************************************************************************* */
	

AS

BEGIN

/* *********************************************************************************

Source: SQLPulse: Get Disk Latency
Build: 2.1
Build Date: 2026-01-10

This query is based on a Microsoft Learn article: 

	https://learn.microsoft.com/en-us/troubleshoot/sql/database-engine/performance/troubleshoot-sql-io-performance

For future modification, allowing specification of collection frequency and time before data is valid may is advisable
This would be to allow smoothing from any startup stress (for example, on [tempdb])

This sproc performs the following activities:

   1) Get the last server restart time via the stored procedure [dbo].[UpdateLastServerStart]
   2) Declare the internal variables
   3) Create Temp Table for data processing
   4) Gather and insert the data into the temp table for processing
   5) Insert the data into [Pulse].[Disk_Latency]
   6) Debug Line if you pull this out of the sproc and into a normal query
   7) Object cleanup


********************************************************************************* */

-- 1) Get the last server restart time via the stored procedure [dbo].[UpdateLastServerStart]

	EXECUTE [Pulse].[UpdateLastServerStart]

-- 2) Declare the internal variables

	Declare @EventTimeUTC as datetime2 (3) = (SELECT (SYSUTCDATETIME()))
	Declare @EventTimeLocal as datetime2 (3) = (SELECT (SYSDATETIME()))
	Declare @LastRestart as datetime = (SELECT MAX(RestartDate) FROM Pulse.tblServerRestartDates)
	Declare @PreviousDataDate as datetime = (SELECT MAX(EventTimeUTC) FROM Pulse.Disk_Latency)
	-- Declare @MinimumMonitorAge as int -- For future use as a user-configurable parameter


-- 3) Create Temp Table for data processing

	CREATE TABLE #tempDiskLatency(
		[EventTimeUTC] [datetime2] (3) NULL,
		[EventTimeLocal] [datetime2] (3) NULL,
		[ReadLatency] [int] NULL,
		[WriteLatency] [int] NULL,
		[AvgLatency] [int] NULL,
		[AvgKBsPerTransfer] [int] NULL,
		[Drive] nvarchar(10),
		[DatabaseName] nvarchar(255) NULL,
		[PhysicalName] nvarchar(2000) NULL
		)
		

-- 4) Gather and insert the data into the temp table for processing

	INSERT INTO #tempDiskLatency

	SELECT
		@EventTimeUTC,
		@EventTimeLocal,
		 ReadLatency = CASE WHEN vfs.num_of_reads = 0 
                           THEN 0 ELSE (vfs.io_stall_read_ms / vfs.num_of_reads) END,
        WriteLatency = CASE WHEN vfs.num_of_writes = 0 
                            THEN 0 ELSE (vfs.io_stall_write_ms / vfs.num_of_writes) END,
        AvgLatency = CASE WHEN (vfs.num_of_reads = 0 AND vfs.num_of_writes = 0) 
                          THEN 0 ELSE (vfs.io_stall / (vfs.num_of_reads + vfs.num_of_writes)) END,
        AvgKBsPerTransfer = CASE WHEN (vfs.num_of_reads = 0 AND vfs.num_of_writes = 0) 
                                 THEN 0 ELSE (((vfs.num_of_bytes_read + vfs.num_of_bytes_written) 
                                               / (vfs.num_of_reads + vfs.num_of_writes)) / 1024) END,
        LEFT(mf.physical_name, 2) AS [Drive],
        DB_NAME(vfs.database_id) AS [DatabaseName],
        mf.physical_name
    FROM sys.dm_io_virtual_file_stats(NULL, NULL) AS vfs
    JOIN sys.master_files AS mf
      ON vfs.database_id = mf.database_id
     AND vfs.file_id = mf.file_id
    ORDER BY AvgLatency DESC;
	

-- 5) Insert the data into [Pulse].[Disk_Latency]
	-- This is where @MinimumMonitorAge would/will be used in the future
	
	INSERT INTO Pulse.Disk_Latency
		(EventTimeUTC, EventTimeLocal, ReadLatency, WriteLatency, AvgLatency, AvgKBsPerTransfer, Drive, DatabaseName, PhysicalName)
	SELECT EventTimeUTC, EventTimeLocal, ReadLatency, WriteLatency, AvgLatency, AvgKBsPerTransfer, Drive, DatabaseName, PhysicalName
	FROM #tempDiskLatency;

--6) Debug Line if you pull this out of the sproc and into a normal query

	--Select * from #tempDiskLatency

	--Select * From Disk_Latency
	
-- 7) Object cleanup

	DROP TABLE #tempDiskLatency


END
GO


