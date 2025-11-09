The default job for this operation is called [DaveMonitor - GetMemoryCounters]
    • The job runs every 5 minutes by default. This can be modified to any value , but is a balance between granular data and performance impact. 5 minutes is more or less what professional monitoring tools use, so why not?
    • The job only has one step: run the stored procedure [DBA].[dbo].[GetMemoryCounters]

-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

Note: On 2024-11-14, while pulling out the code for a manual RAM check, I found my original query was pulling TWO (2) counters:

    Buffer Cache Hit Ratio
    Buffer Cache Hit Ratio Base
    
The former can be >100 and must be divided by the latter (base) value. After a short search, I found this query that does the trick:

    SELECT counter_name as CounterName, (a.cntr_value * 1.0 / b.cntr_value) * 100.0 as BufferCacheHitRatio FROM sys.dm_os_performance_counters  a JOIN  (SELECT cntr_value,OBJECT_NAME FROM sys.dm_os_performance_counters WHERE counter_name = 'Buffer cache hit ratio base' AND OBJECT_NAME LIKE '%Buffer Manager%') b ON  a.OBJECT_NAME = b.OBJECT_NAME WHERE a.counter_name =
 'Buffer cache hit ratio' AND a.OBJECT_NAME LIKE '%Buffer Manager%'
    
    From <https://jmarun.wordpress.com/2018/12/17/query-to-find-buffer-cache-hit-ratio-in-sql-server/> 
    
When cleaned up, it fits into the sproc quite well, and I can't for the life of me find why I was gathering both in the first place. Most likely I couldn't have a query like the one just mentioned, but it's remotely possible it was a design decision for reporting purposes. Nevertheless, I have updated the sproc and catalogued both the old version and updated version

-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

The data gathering is done by the stored procedure [dbo].[GetMemoryCounters]:

    1) Get the last server restart (EVERY sproc does this when it runs)
    2) Put the aggregate values for these items into a temp table
        a. Buffer Cache Hit Ratio
        b. Page Life Expectancy
    3) Put all non-duplicate values into the table [dbo].[tblMemoryCounters]

The counters and related data (such as their names and types) are pulled entirely from sys.dm_os_performance_counters

This is all extremely straightforward - it is simply a large table that contains the counters. The actual columns are:

    • ID (int, primary key)
    • EventTime (datetime) ; this is exact time the measurement is recorded for
    • ObjectName (nchar128) ; the category the counter belongs to (ex, SQLServer:Buffer Manager)
    • CounterName(nchar128) ; the name of the specific metric being recorded (child of the category)
    • InstanceName; the name of the counter instance - **NOT** the name of the SQL instance
    • CounterValue: the metric of the counter
    • CounterType: Type of counter as defined by the Windows performance architecture
        ○ The counter type is present for future expansion in calculations

These are all for mathematical manipulation. All columns except ID can take NULLs.

Much like the CounterType value, the leveraging of the temp table and the elimination of duplicates is done solely for future expansion of this module. As-is, it should be literally impossible to have duplicate entries based on time due to what I'm pulling - but that may not always be the case in the future.

To-Do for Version 1

    1) Change the table name to get rid of the 'tbl' prefix; this is to help the SQL sort algorithms work less; this will also require the sproc to be updated
    2) Decide which calculations will be part of the monthly health check; possible candidates are:
        a. Average values
        b. The % time  each counter is severe: PLE 300-600 / BCHR 95%-98%
        c. The % time each counter is critical: PLE <300 / BCHR < 95%
        d. A rollup of 'concern time' - the total % each is severe + critical
        e. The low-water marks for each

EX: PLE: 5% (215) | BCHR: 11% (88.3%)
As a baseline, 5% or more of anything should be considered 'bad'; bad values should be in RED on reports

To-Do for Version 2

    1) Get values per-core
    2) Have an expandable report with the header being a value rollup as describe above, the expand for a detailed view
