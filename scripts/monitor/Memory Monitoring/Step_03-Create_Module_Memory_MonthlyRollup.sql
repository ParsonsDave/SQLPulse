USE [SQLPulse];
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE PROCEDURE [Pulse].[Module_Memory_MonthlyRollup]

AS
BEGIN

    SET NOCOUNT ON;

/* *******************************************************************************************************************

Source: SQLPulse: Module_Memory_MonthlyRollup
Build: 1.0
Build Date: 2026-02-15

This is one of the reporting routines for the Memory module of SqlPulse
This procedures calculates the various Memory values for the monthly report/health check
This procedure will execute every 5 minutes along with the rest of the Pulse stored procedures;
    this is a deliberate design decision to maintain a dual job configuration

Notes:
    - Assumes [Pulse].[Memory_Counters] contains 5-minute samples.
    - Rollup is per-server, per-month.
    - This version targets a less-technical audience with high-signal metrics.

NOTE: At this time, the various Reporting procedures do NOT follow the convention of the other
stored procedures where the first activity is to execute [dbo].[UpdateLastServerStart]. The
current reasoning is that, since the Reporting procedures are in the tier 3 of the 
Execution order, you can't get here without having gone through all the Monitoring procedures
This may be revisited in the future; I want to evaluate the run time of the master job in release candidate 1

NOTE: Note that this all processes via UTC and NOT by local time. This is a deliberate decision for v1, but a future
version will support user-specified time choices, including Local, Server Time Zone, or even a custom offset

IMPORTANT: This procedure makes heavy use of Common Table Expressions (CTEs) versus building temp tables. This 
is partially a design choice and partially because the data collection is different from other metrics (multiple
different counters all in the same table) and this is a very good time to provide easy-to-understand examples
of their use.

It performs the following activities:

    1) Determine if the monthly rollup has already been completed; this should only ever execute once per month
        -> Exit the procedure if this month already has an execution
    2) Declare the internal variables
    3) Build the base data sets
    4) Calculate Data Completeness: How much of the possible data is present in the table?
    5) Steady-State memory metrics: ratio of Total/Target server memory 
    6) Memory grants review: pending grants max value & % time grants were outstanding
    7) PLE Metrics (median, 5th percentile, CV, thresholds): measures data churn between RAM and disk
    8) BCHR metrics(Avg, min, % below 95): measures RAM vs workload - 5 below 95 is critical
        But the busier the server, the closer to 100 users begin to notice performance lag
        this can even result in a noticable difference between something like 99.9% and 99.8%
        This default will need to be user-configurable in the future
    9) Insert data into the rollup table
        Note the ISNULL checks; these might needto be added to other columns
        They are present here because my dev SQL instance had perfect performance in those categories
        and so was inserting NULLs because no values fit the calculations

******************************************************************************************************************* */


-- 1) Determine if the monthly rollup has already been completed; this should only ever execute once per month
        -- Exit the procedure if this month already has an execution
        -- If youre unfamiliar, the RETURN command below is what does it; the exit code is 0 (successful)
        -- ServerName is just in case you change the name or move an existing Pulse to a new box

    DECLARE @ServerName sysname = @@SERVERNAME;

    -- This is where the check for whether calculations are to be made for local or UTC time
    -- DECLARE @ReportTimeUsed datetime2(3) =
        --(
        --    SELECT CASE ParameterNumber
        --             WHEN 1 THEN SYSUTCDATETIME()
        --             WHEN 2 THEN SYSDATETIME()
        --             ELSE SYSUTCDATETIME()   -- default fallback
        --           END
        --    FROM Pulse.Parameters
        --    WHERE ParameterName = 'ReportGenerationTimeMethod'
        --);

    DECLARE @RollupMonth date = (DATEADD(MONTH, -1, (DATEFROMPARTS(
        YEAR(SYSUTCDATETIME()),
        MONTH(SYSUTCDATETIME()),
        1)
        )));
       
    IF EXISTS (
        SELECT 1
        FROM [Pulse].[Memory_MonthlyRollup]
        WHERE RollupMonth = @RollupMonth
        AND ServerName = @ServerName
        )
    BEGIN
        RETURN;
    END


-- 2) Declare the internal variables
    
    DECLARE
        -- Admin / Metadata: All calculations local
            @StartDate datetime2(3) = @RollupMonth,  -- 1st of month 00:00 UTC
            @EndDate datetime2(3) = DATEADD(MONTH, 1, @RollupMonth), -- 1st of next month UTC
            @GeneratedLocal datetime2(3) = SYSDATETIME(),
            @GeneratedUTC datetime2(3) = SYSUTCDATETIME(),
            @ReportGenerationTimeMethod int = 1, -- In the future this will be [= SELECT ParameterNumber FROM Pulse.Parameters WHERE ParameterName = 'ReportGenerationTimeMethod']
                        
        -- Data Completeness
            @MinutesinMonth int,
            @CollectedPoints int,
            @ExpectedPoints int,
            @AccuracyPercent decimal(5,2);

            SELECT @ExpectedPoints = (DATEDIFF(MINUTE, @StartDate, @EndDate)) /5   -- This assumes the data gathering job runs every 5 minutes

        -- PLE Metrics
            DECLARE @MedianPLE int
            DECLARE @Ple5thPercentile int
            DECLARE @PctPLEBelow600 decimal(10,4)
            DECLARE @PctPLEBelow300 decimal(10,4)            


-- 3) Build the base datasets and get them into the reference table #BaseWithDerived

    ;WITH Base AS
    (
        SELECT
              EventTimeUTC
            , EventTimeLocal
            , MAX(CASE WHEN CounterName = 'Page life expectancy' THEN CounterValue END) AS PLE
            , MAX(CASE WHEN CounterName = 'Buffer cache hit ratio' THEN CounterValue END) AS BCHR
            , MAX(CASE WHEN CounterName = 'Target Server Memory (KB)' THEN CounterValue END) AS TargetServerMemoryKB
            , MAX(CASE WHEN CounterName = 'Total Server Memory (KB)'  THEN CounterValue END) AS TotalServerMemoryKB
            , MAX(CASE WHEN CounterName = 'Memory Grants Pending'     THEN CounterValue END) AS MemoryGrantsPending
            , MAX(CASE WHEN CounterName = 'Memory Grants Outstanding' THEN CounterValue END) AS MemoryGrantsOutstanding
            , MAX(CASE WHEN CounterName = 'Free Memory (KB)'          THEN CounterValue END) AS FreeMemoryKB
            , MAX(CASE WHEN CounterName = 'Stolen Server Memory (KB)' THEN CounterValue END) AS StolenMemoryKB
        FROM [Pulse].[Memory_Counters]
        WHERE EventTimeUTC >= @StartDate
          AND EventTimeUTC <  @EndDate
        GROUP BY EventTimeUTC, EventTimeLocal
    )
    , BaseWithDerived AS
    (
        SELECT
              *
            , CASE 
                  WHEN TargetServerMemoryKB IS NOT NULL AND TargetServerMemoryKB > 0
                       AND TotalServerMemoryKB IS NOT NULL
                  THEN CAST(TotalServerMemoryKB AS decimal(19,4)) / CAST(TargetServerMemoryKB AS decimal(19,4))
                  ELSE NULL
              END AS SteadyStateRatio
        FROM Base
    )
    
    SELECT * INTO #BaseWithDerived FROM BaseWithDerived


-- 4) Calculate Data Completeness Dataset: How much of the possible data is present in the table?
    -- 
        
    SELECT
          @ExpectedPoints AS ExpectedPoints
        , @ServerName     AS ServerName
        , @RollupMonth    AS RollupMonth
        , COUNT(*)        AS CollectedPoints
        , 100 * (COUNT(*) / Cast(@ExpectedPoints as decimal (7,2))) AS AccuracyPercent
    INTO #Points
    FROM #BaseWithDerived;
    
-- 5) Steady-State memory metrics: ratio of Total/Target server memory

    ;WITH Steady AS
    (
        SELECT SteadyStateRatio
        FROM #BaseWithDerived
        WHERE SteadyStateRatio IS NOT NULL
    )
    SELECT
          AVG(SteadyStateRatio)                                   AS AvgSteadyStateRatio
        , MIN(SteadyStateRatio)                                   AS MinSteadyStateRatio
        , (100.0 * (SUM(CASE WHEN SteadyStateRatio < 0.90 THEN 1 ELSE 0 END)) / CAST(@CollectedPoints as decimal(7,2))) AS PctBelow90pctSteady
    INTO #Steady
    FROM Steady;


-- 6) Memory grants review: pending grants max value & % time grants were outstanding

    ;WITH Grants AS
        (
            SELECT MemoryGrantsPending
            FROM #BaseWithDerived
            WHERE MemoryGrantsPending IS NOT NULL
        )
        SELECT
              (100.0 * (SUM(CASE WHEN MemoryGrantsPending > 0 THEN 1 ELSE 0 END)) / CAST(@CollectedPoints as decimal(7,2))) AS PctWithGrantsPending
            , MAX(MemoryGrantsPending)                                AS MaxGrantsPending
        INTO #Grants
        FROM Grants;


-- 7) PLE Metrics (median, 5th percentile, CV, thresholds): measures data churn between RAM and disk

    SELECT @MedianPLE = PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY PLE)
                            OVER ()
                            FROM #BaseWithDerived;

    SELECT @Ple5thPercentile = (SELECT DISTINCT(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY PLE) OVER ()) FROM #BaseWithDerived)

    SELECT @PctPLEBelow600 = 100 * ((SELECT COUNT(PLE) FROM #BaseWithDerived WHERE PLE <601) / (SELECT CAST(COUNT(PLE) AS decimal(7,2)) FROM #BaseWithDerived))
    SELECT @PctPLEBelow300 = 100 * ((SELECT COUNT(PLE) FROM #BaseWithDerived WHERE PLE <301) / (SELECT CAST(COUNT(PLE) AS decimal(7,2)) FROM #BaseWithDerived))


-- 8) BCHR metrics(Avg, min, % below 95): measures RAM vs workload - 5 below 95 is critical
    -- But the busier the server, the closer to 100 users begin to notice performance lag
    -- this can even result in a noticable difference between something like 99.9% and 99.8%
    -- this default will need to be user-configurable in the future

    -------------------------------------------------------------------------
    -- 8) BCHR metrics
    -------------------------------------------------------------------------

    ;WITH BCHRData AS
    (
        SELECT BCHR
        FROM #BaseWithDerived
        WHERE BCHR IS NOT NULL
    )
    SELECT
          AVG(CAST(BCHR AS decimal(19,4)))                         AS AvgBCHR
        , MIN(BCHR)                                                AS MinBCHR
        , (100.0 * (SUM(CASE WHEN BCHR < 95 THEN 1 ELSE 0 END) / CAST(COUNT(BCHR) as decimal(7,2)))) AS PctBCHRBelow95
    INTO #BCHR
    FROM BCHRData;
    

-- 9) Insert data into the rollup table
    -- Note the ISNULL checks; these might needto be added to other columns
    -- They are present here because my dev SQL instance had perfect performance in those categories
    -- and so was inserting NULLs because no values fit the calculations

    INSERT INTO [Pulse].[Memory_MonthlyRollup]
    (
          RollupMonth
        , ServerName
        , ExpectedPoints
        , CollectedPoints
        , AccuracyPercent

        , AvgSteadyStateRatio
        , MinSteadyStateRatio
        , PctBelow90pctSteady

        , PctWithGrantsPending
        , MaxGrantsPending

        , MedianPLE
        , PLE5thPercentile
        , PctPLEBelow600
        , PctPLEBelow300

        , AvgBCHR
        , MinBCHR
        , PctBCHRBelow95

        , GeneratedUTC
        , GeneratedLocal
    )
    SELECT
          @RollupMonth                                  AS RollupMonth
        , @ServerName                                   AS ServerName
        , @ExpectedPoints                               AS ExpectedPoints
        , p.CollectedPoints                              AS CollectedPoints
        , p.AccuracyPercent                              AS AccuracyPercent

        , ISNULL(s.AvgSteadyStateRatio,0)
        , ISNULL(s.MinSteadyStateRatio,0)
        , ISNULL(s.PctBelow90pctSteady,0)

        , ISNULL(g.PctWithGrantsPending,0)
        , g.MaxGrantsPending

        , @MedianPLE
        , @Ple5thPercentile
        , @PctPLEBelow600
        , @PctPLEBelow300

        , b.AvgBCHR
        , b.MinBCHR
        , b.PctBCHRBelow95

        , @GeneratedUTC                             AS GeneratedUTC
        , @GeneratedLocal                           AS GeneratedLocal
    FROM #Steady s
    CROSS JOIN #Points p
    CROSS JOIN #Grants g
    CROSS JOIN #BCHR   b


-- 10) Cleanup
    
    DROP TABLE #Points;
    DROP TABLE #Steady;
    DROP TABLE #Grants;
    DROP TABLE #BCHR;
    DROP TABLE #BaseWithDerived;

END;
GO


