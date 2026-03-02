USE [SQLPulse]
GO


SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO





CREATE PROCEDURE [Pulse].[Module_Memory_CollectData]
	
	/* *********************************************************************************

	There are no input or output variables at this time

	********************************************************************************* */
	

AS

BEGIN

/* *********************************************************************************

Source: SQLPulse: Collect Memory Counters
Build: 2.0
Build Date: 2026-02-14

This sproc gathers and records data for Memory utilization

Current Counters:

	Buffer Cache Hit Ratio
	Page Life Expectancy (Average of all NUMA nodes only)

	^These both come from the 'Buffer Manager' object, but I have them in 2 separate queries for ease of reading
	The next block all come from the 'Memory Manager' object, so we gather them all at once.

	Memory Grants Outstanding	- Number of active queries that have been granted workspace memory. Indicates current memory consumption by query execution.
	Memory Grants Pending		- Number of queries waiting for workspace memory. Any sustained value > 0 indicates memory pressure.
	Target Server Memory (KB)	- The amount of memory SQL Server wants based on workload. When Total < Target, SQL is still ramping up or is memory‑constrained*
	Total Server Memory (KB)	- The amount of memory SQL Server has currently allocated from the OS. Should approach Target under steady load*
	Free Memory (KB)			- Memory SQL Server has allocated but not yet assigned to any component. Drops toward zero under pressure.
	Stolen Server Memory (KB)	- Memory taken from the buffer pool for non‑data uses (e.g., query execution, hashing, sorting, internal structures); 
								   High values relative to buffer pool size can indicate pressure.

	* If the SQL service account has [Locak Pages in Memory] permissions, Target/Total RAM should converge to be equal as workloads are processed,
	   unless you have assigned more RAM than SQL ever actually uses. This is rare, but can happen.

Counters are being pulled raw rather than as final values to allow for more
flexibility in the future. It does mean that some processing will have
to be done - for example, to get a usable BCHR number. Should be worth it.

It performs the following activities:

   1) Get the last server restart time via the stored procedure [dbo].[UpdateLastServerStart]
   2) Declare the internal variables
   3) Create Temp Table to gather data for processing
   4) Gather and insert Buffer Cache Hit Ratio into the temp table
   5) Gather and insert Page Life Expectancy into the temp table
   6) Get the remaining counters
   7) Insert non-duplicate values into the main table
		-- Duplicates are evaluated on the MINUTE by a CAST to smalldatetime, which sets all seconds & fractions thereof to 0
   8) Object cleanup

********************************************************************************* */

-- 1) Get the last server restart time via the stored procedure [dbo].[UpdateLastServerStart]

	EXECUTE [Pulse].[UpdateLastServerStart]

-- 2) Declare the internal variables

	Declare @EventTimeUTC as datetime2 (3) = (SELECT SYSUTCDATETIME())
	Declare @EventTimeLocal as datetime2 (3) = (SELECT SYSDATETIME())


-- 3) Create Temp Table to gather data for processing

	CREATE TABLE #TempMemoryCounters(
		[EventTimeUTC] [datetime2] (3) NULL,
		[EventTimeLocal] [datetime2] (3) NULL,
		[ObjectName] [nchar](128) NULL,
		[CounterName] [nchar](128) NULL,
		[InstanceName] [nchar](128) NULL,
		[CounterValue] [bigint] NULL,
		[CounterType] [int] NULL
		)
	

-- 4) Gather and insert Buffer Cache Hit Ratio into the temp table

	INSERT INTO #TempMemoryCounters
	SELECT
		@EventTimeUTC
		,@EventTimeLocal
		,a.[object_name]
		,a.[counter_name]
		,a.[instance_name]
		,((a.cntr_value * 1.0 / b.cntr_value) * 100.0) AS [cntr_value]
		,a.[cntr_type]
	FROM sys.dm_os_performance_counters a 
	JOIN  (SELECT cntr_value,OBJECT_NAME FROM sys.dm_os_performance_counters WHERE counter_name = 'Buffer cache hit ratio base' AND OBJECT_NAME LIKE '%Buffer Manager%') b 
	ON  a.OBJECT_NAME = b.OBJECT_NAME 
	WHERE a.counter_name = 'Buffer cache hit ratio' AND a.OBJECT_NAME LIKE '%Buffer Manager%'


-- 5) Gather and insert Page Life Expectancy into the temp table

	INSERT INTO #TempMemoryCounters
	SELECT 
		@EventTimeUTC
		,@EventTimeLocal
		,[object_name]
		,[counter_name]
		,[instance_name]
		,[cntr_value]
		,[cntr_type]
	FROM sys.dm_os_performance_counters
	WHERE [object_name] LIKE '%Buffer Manager%'
		AND [counter_name] = 'Page life expectancy'


-- 6) Get the remaining counters

	INSERT INTO #TempMemoryCounters
	SELECT
		  @EventTimeUTC
		, @EventTimeLocal
		, [object_name]
		, [counter_name]
		, [instance_name]
		, [cntr_value]
		, [cntr_type]
	FROM sys.dm_os_performance_counters
	WHERE [object_name] LIKE '%Memory Manager%'
	  AND [counter_name] IN (
			  'Memory Grants Pending'
			, 'Memory Grants Outstanding'
			, 'Target Server Memory (KB)'
			, 'Total Server Memory (KB)'
			, 'Free Memory (KB)'
			, 'Stolen Server Memory (KB)'
		);


-- 7) Insert non-duplicate values into the main table
		-- Duplicates are evaluated on the MINUTE by a CAST to smalldatetime, which sets all seconds & fractions thereof to 0

	INSERT INTO [Pulse].[Memory_Counters] (EventTimeUTC, EventTimeLocal, ObjectName, CounterName, InstanceName, CounterValue, CounterType)
	SELECT EventTimeUTC, EventTimeLocal, ObjectName, CounterName, InstanceName, CounterValue, CounterType
	FROM #TempMemoryCounters t
	WHERE NOT EXISTS (SELECT 1 FROM [Pulse].[Memory_Counters] d
	WHERE (CAST(EventTimeUTC AS smalldatetime) = CAST(t.EventTimeUTC AS smalldatetime)));


-- 8) Object cleanup

	drop table #TempMemoryCounters


END
GO


