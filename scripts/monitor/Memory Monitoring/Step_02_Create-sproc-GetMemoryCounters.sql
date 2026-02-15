USE [SQLPulse]
GO

/****** Object:  StoredProcedure [dbo].[GetMemoryCounters]    Script Date: 3/2/2025 11:35:09 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO




CREATE PROCEDURE [dbo].[GetMemoryCounters]
	
	/* *********************************************************************************

	There are no input or output variables at this time

	********************************************************************************* */
	

AS

BEGIN

/* *********************************************************************************

Source: SQLPulse: Get Memory Counters
Build: 1.1
Build Date: 2026-01-10

This sproc gathers and records data for CPU utilization

Current Counters:

	Buffer Cache Hit Ratio
	Page Life Expectancy (Average of all NUMA nodes only)

Counters are being pulled raw rather than as final values to allow for more
flexibility in the future. It does mean that some processing will have
to be done - for example, to get a usable BCHR number. Should be worth it.

In the future, the goal is to pull the PLE of each NUMA node individually
in order to get an idea of different loads. The query to do so would start with:

SELECT*
FROM sys.dm_os_performance_counters
WHERE [counter_name] = 'Page life expectancy'

It performs the following activities:

   1) Get the last server restart time via the stored procedure [dbo].[UpdateLastServerStart]
   2) Declare the internal variables
   3) Create Temp Table to gather data for processing
   4) Set the current time
   5) Gather and insert Buffer Cache Hit Ratio into the temp table
   6) Gather and insert Page Life Expectancy into the temp table
   7) Insert non-duplicate values into the main table
		-- Duplicates are evaluated on the MINUTE by a CAST to smalldatetime, which sets all seconds & fractions thereof to 0
   8) Object cleanup

	



********************************************************************************* */

-- 1) Get the last server restart time via the stored procedure [dbo].[UpdateLastServerStart]

	EXECUTE [dbo].[UpdateLastServerStart]

-- 2) Declare the internal variables

	Declare @EventTime as datetime


-- 3) Create Temp Table to gather data for processing

	CREATE TABLE #TempMemoryCounters(
		[EventTime] [datetime] NULL,
		[ObjectName] [nchar](128) NULL,
		[CounterName] [nchar](128) NULL,
		[InstanceName] [nchar](128) NULL,
		[CounterValue] [bigint] NULL,
		[CounterType] [int] NULL
		)
	

-- 4) Set the current time

	Set @EventTime = CURRENT_TIMESTAMP


-- 5) Gather and insert Buffer Cache Hit Ratio into the temp table

	INSERT INTO #TempMemoryCounters
	SELECT
		@EventTime as EventTime
		,a.[object_name]
		,a.[counter_name]
		,a.[instance_name]
		,((a.cntr_value * 1.0 / b.cntr_value) * 100.0) AS [cntr_value]
		,a.[cntr_type]
	FROM sys.dm_os_performance_counters a 
	JOIN  (SELECT cntr_value,OBJECT_NAME FROM sys.dm_os_performance_counters WHERE counter_name = 'Buffer cache hit ratio base' AND OBJECT_NAME LIKE '%Buffer Manager%') b 
	ON  a.OBJECT_NAME = b.OBJECT_NAME 
	WHERE a.counter_name = 'Buffer cache hit ratio' AND a.OBJECT_NAME LIKE '%Buffer Manager%'


-- 6) Gather and insert Page Life Expectancy into the temp table

	INSERT INTO #TempMemoryCounters
	SELECT 
		@EventTime as EventTime
		,[object_name]
		,[counter_name]
		,[instance_name]
		,[cntr_value]
		,[cntr_type]
	FROM sys.dm_os_performance_counters
	WHERE [object_name] LIKE '%Manager%'
		AND [counter_name] = 'Page life expectancy'


-- 7) Insert non-duplicate values into the main table
		-- Duplicates are evaluated on the MINUTE by a CAST to smalldatetime, which sets all seconds & fractions thereof to 0

	INSERT INTO [dbo].[tblMemoryCounters] (EventTime, ObjectName, CounterName, InstanceName, CounterValue, CounterType)
	SELECT EventTime, ObjectName, CounterName, InstanceName, CounterValue, CounterType
	FROM #TempMemoryCounters t
	WHERE NOT EXISTS (SELECT 1 FROM [dbo].[tblMemoryCounters] d
	WHERE (CAST(EventTime AS smalldatetime) = CAST(t.EventTime AS smalldatetime)));


-- 8) Object cleanup

	drop table #TempMemoryCounters


END
GO
