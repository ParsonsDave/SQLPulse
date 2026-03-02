USE [SQLPulse]
GO


SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE PROCEDURE [Pulse].[Module_Waits_MonthlyRollup]

AS
BEGIN

    SET NOCOUNT ON;


/* *******************************************************************************************************************

Source: SQLPulse: Module_Waits_MonthlyRollup
Build: 1.0
Build Date: 2026-03-01

This is one of the reporting routines for the Waits module of SqlPulse
This procedures calculates the various Waits values for the monthly report/health check
This procedure will execute every 5 minutes along with the rest of the Pulse stored procedures;
    this is a deliberate design decision to maintain a dual job configuration

NOTE: At this time, the various Reporting procedures do NOT follow the convention of the other
stored procedures where the first activity is to execute [dbo].[UpdateLastServerStart]. The
current reasoning is that, since the Reporting procedures are in the tier 3 of the 
Execution order, you can't get here without having gone through all the Monitoring procedures
This may be revisited in the future; I want to evaluate the run time of the master job in release candidate 1

NOTE: Note that this all processes via UTC and NOT by local time. This is a deliberate decision for v1, but a future
version will support user-specified time choices, including Local, Server Time Zone, or even a custom offset

NOTE: There are more wait Categories being captured by the data collection procedure than are being rolled up
here. This is a deliberate decision, as the collection and rollup have no mutual dependencies; the collector
can be continually adjusted, and the rollup only cares about category names starting in section 6) Data Aggregation.

NOTE: Any adjustment to the rollup will require an adjustment to the table Waits_MonthlyRollup

It performs the following activities:

    1) Determine if the monthly rollup has already been completed; this should only ever execute once per month
        -> Exit the procedure if this month already has an execution
    2) Insert the data for the rollup into a working temp table
    3) Exit if there is no data for the rollup month in the temp table
    4) Adjust working data to account for any carryover from the previous month
    5) Begin rolling up the data by category
    6) Begin data aggregation
    7) Extract category totals into variables
    8) Calculate Percentages
    9) Derived totals
        -> I can't for the life of me remember why I had this in here originally. Leaving for now.
    10) Calculate Top 3 Wait Types
    11) Calculate blocking-specific metrics
    12) Month-Over-Month Trends
        -> This has not yet had a practical test, as only 1 month has been rolled up
    13) Insert the data
    14) Cleanup temp tables

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
        FROM [Pulse].[Waits_MonthlyRollup]
        WHERE RollupMonth = @RollupMonth
        AND ServerName = @ServerName
        )
    BEGIN
        RETURN;
    END

    SELECT @ServerName AS ServerName, @RollupMonth as RollupMonth


-- 2) Insert the data for the rollup into a temp table

      ;WITH Boundaries AS (
        SELECT
              ID,
              SnapshotDateUTC,
              SnapshotDateLocal,
              SnapshotType,
              TotalServerTimeSeconds,
              WaitType,
              Category,
              WaitSeconds,
              ResourceSeconds,
              SignalSeconds,
              WaitingTasksCount
        FROM Pulse.Waits_StatsByMonth
        WHERE RollupMonth = @RollupMonth
          AND ServerName = @ServerName
    )
       
    SELECT * INTO #B FROM Boundaries;


-- 3) Exit if there is no data for the rollup month in the temp table

    IF NOT EXISTS (SELECT 1 FROM #B)
        RETURN;


-- 4) Adjust working data to account for any carryover from the previous month
   
        IF EXISTS (SELECT 1 FROM #B WHERE SnapshotType = 'StartOfMonth')
    BEGIN
        UPDATE #B
        SET
              TotalServerTimeSeconds = -ABS(TotalServerTimeSeconds)
            , WaitSeconds            = -ABS(WaitSeconds)
            , ResourceSeconds        = -ABS(ResourceSeconds)
            , SignalSeconds          = -ABS(SignalSeconds)
        WHERE SnapshotType = 'StartOfMonth';
    END


-- 5) Begin rolling up the data by category


    ;WITH WaitTypeRollup AS (
        SELECT
            WaitType,
            Category,
            SUM(TotalServerTimeSeconds) AS TotalServerTimeSeconds,
            SUM(WaitSeconds) AS MonthlyWaitSeconds,
            SUM(ResourceSeconds) AS MonthlyResourceSeconds,
            SUM(SignalSeconds) AS MonthlySignalSeconds
        FROM #B
        GROUP BY WaitType, Category
    )
    SELECT
          Category
        , AVG(TotalServerTimeSeconds) AS TotalServerTimeSeconds
        , SUM(MonthlyWaitSeconds)     AS MonthlyWaitSeconds
        , SUM(MonthlyResourceSeconds) AS MonthlyResourceSeconds
        , SUM(MonthlySignalSeconds)   AS MonthlySignalSeconds
        , CASE 
              WHEN SUM(MonthlyWaitSeconds) = 0 THEN 0
              ELSE ROUND(SUM(MonthlyWaitSeconds) / AVG(TotalServerTimeSeconds), 2)
          END AS TotalWaitPct
    FROM WaitTypeRollup
    GROUP BY Category
    ORDER BY Category;


-- 6) Begin data aggregation
   
    ;WITH CategoryAgg AS (
        SELECT
              Category
            , SUM(WaitSeconds)     AS TotalWaitSeconds
            , SUM(ResourceSeconds) AS TotalResourceSeconds
            , SUM(SignalSeconds)   AS TotalSignalSeconds
        FROM #B
        GROUP BY Category
    ),
    Overall AS (
        SELECT
              SUM(WaitSeconds)     AS TotalWaitSeconds
            , SUM(ResourceSeconds) AS TotalResourceSeconds
            , SUM(SignalSeconds)   AS TotalSignalSeconds
        FROM #B
    )
    SELECT
          ca.Category
        , ca.TotalWaitSeconds
        , ca.TotalResourceSeconds
        , ca.TotalSignalSeconds
        , o.TotalWaitSeconds AS GrandTotalWaitSeconds
    INTO #Category
    FROM CategoryAgg ca
    CROSS JOIN Overall o;


-- 7) Extract category totals into variables

    DECLARE
          @CPUWaitSeconds      decimal(18,2)
        , @MemoryWaitSeconds   decimal(18,2)
        , @DiskWaitSeconds     decimal(18,2)
        , @BlockingWaitSeconds decimal(18,2)
        , @OtherWaitSeconds    decimal(18,2)
        , @TotalWaitSeconds    decimal(18,2)
        , @TotalResourceSeconds decimal(18,2)
        , @TotalSignalSeconds   decimal(18,2);

    SELECT
          @CPUWaitSeconds      = SUM(CASE WHEN Category = 'CPU'      THEN TotalWaitSeconds ELSE 0 END)
        , @MemoryWaitSeconds   = SUM(CASE WHEN Category = 'Memory'   THEN TotalWaitSeconds ELSE 0 END)
        , @DiskWaitSeconds     = SUM(CASE WHEN Category = 'Disk'     THEN TotalWaitSeconds ELSE 0 END)
        , @BlockingWaitSeconds = SUM(CASE WHEN Category = 'Blocking' THEN TotalWaitSeconds ELSE 0 END)
        , @OtherWaitSeconds    = SUM(CASE WHEN Category = 'Other'    THEN TotalWaitSeconds ELSE 0 END)
        , @TotalWaitSeconds    = MAX(GrandTotalWaitSeconds)
    FROM #Category;

    SELECT
          @TotalResourceSeconds = SUM(ResourceSeconds)
        , @TotalSignalSeconds   = SUM(SignalSeconds)
    FROM #B;


-- 8) Calculate Percentages

    DECLARE
          @CPUWaitPct      decimal(5,2)
        , @MemoryWaitPct   decimal(5,2)
        , @DiskWaitPct     decimal(5,2)
        , @BlockingWaitPct decimal(5,2)
        , @OtherWaitPct    decimal(5,2);

    SET @CPUWaitPct      = CASE WHEN @TotalWaitSeconds = 0 THEN 0 ELSE ROUND(@CPUWaitSeconds      / @TotalWaitSeconds * 100, 2) END;
    SET @MemoryWaitPct   = CASE WHEN @TotalWaitSeconds = 0 THEN 0 ELSE ROUND(@MemoryWaitSeconds   / @TotalWaitSeconds * 100, 2) END;
    SET @DiskWaitPct     = CASE WHEN @TotalWaitSeconds = 0 THEN 0 ELSE ROUND(@DiskWaitSeconds     / @TotalWaitSeconds * 100, 2) END;
    SET @BlockingWaitPct = CASE WHEN @TotalWaitSeconds = 0 THEN 0 ELSE ROUND(@BlockingWaitSeconds / @TotalWaitSeconds * 100, 2) END;
    SET @OtherWaitPct    = CASE WHEN @TotalWaitSeconds = 0 THEN 0 ELSE ROUND(@OtherWaitSeconds    / @TotalWaitSeconds * 100, 2) END;


-- 9) Derived totals
    -- I can't for the life of me remember why I had this in here originally. Leaving for now.

    DECLARE @SignalToResourceRatio decimal(10,4);
    SET @SignalToResourceRatio =
        CASE WHEN @TotalResourceSeconds = 0 THEN NULL
             ELSE ROUND(@TotalSignalSeconds / @TotalResourceSeconds, 4)
        END;


-- 10) Calculate Top 3 Wait Types


    ;WITH WaitTypeRollup AS (
        SELECT
              WaitType
            , SUM(WaitSeconds) AS TotalWaitSeconds
        FROM #B
        GROUP BY WaitType
    ),
    Ranked AS (
        SELECT
              WaitType
            , TotalWaitSeconds
            , ROW_NUMBER() OVER (ORDER BY TotalWaitSeconds DESC) AS rn
        FROM WaitTypeRollup
    )
    SELECT *
    INTO #TopWaits
    FROM Ranked
    WHERE rn <= 3;

    DECLARE
          @TopWaitType1 nvarchar(60), @TopWaitType1Seconds decimal(18,2), @TopWaitType1Pct decimal(5,2)
        , @TopWaitType2 nvarchar(60), @TopWaitType2Seconds decimal(18,2), @TopWaitType2Pct decimal(5,2)
        , @TopWaitType3 nvarchar(60), @TopWaitType3Seconds decimal(18,2), @TopWaitType3Pct decimal(5,2);

    SELECT
          @TopWaitType1        = (SELECT WaitType FROM #TopWaits WHERE rn = 1)
        , @TopWaitType1Seconds = (SELECT TotalWaitSeconds FROM #TopWaits WHERE rn = 1)
        , @TopWaitType1Pct     = CASE WHEN @TotalWaitSeconds = 0 THEN 0 ELSE ROUND((SELECT TotalWaitSeconds FROM #TopWaits WHERE rn = 1) / @TotalWaitSeconds * 100, 2) END;

    SELECT
          @TopWaitType2        = (SELECT WaitType FROM #TopWaits WHERE rn = 2)
        , @TopWaitType2Seconds = (SELECT TotalWaitSeconds FROM #TopWaits WHERE rn = 2)
        , @TopWaitType2Pct     = CASE WHEN @TotalWaitSeconds = 0 THEN 0 ELSE ROUND((SELECT TotalWaitSeconds FROM #TopWaits WHERE rn = 2) / @TotalWaitSeconds * 100, 2) END;

    SELECT
          @TopWaitType3        = (SELECT WaitType FROM #TopWaits WHERE rn = 3)
        , @TopWaitType3Seconds = (SELECT TotalWaitSeconds FROM #TopWaits WHERE rn = 3)
        , @TopWaitType3Pct     = CASE WHEN @TotalWaitSeconds = 0 THEN 0 ELSE ROUND((SELECT TotalWaitSeconds FROM #TopWaits WHERE rn = 3) / @TotalWaitSeconds * 100, 2) END;


-- 11) Calculate blocking-specific metrics


    DECLARE @PeakBlockingHourLocal tinyint;
    DECLARE @TopBlockingWaitType nvarchar(60);
    --DECLARE 

    ;WITH Blocking AS (
        SELECT
              DATEPART(HOUR, SnapshotDateLocal) AS HourLocal
            , SUM(WaitSeconds) AS BlockingSeconds
        FROM #B
        WHERE Category = 'Blocking'
        GROUP BY DATEPART(HOUR, SnapshotDateLocal)
    )
    SELECT TOP (1)
          @PeakBlockingHourLocal = HourLocal
    FROM Blocking
    ORDER BY BlockingSeconds DESC;

    SELECT TOP (1)
          @TopBlockingWaitType = WaitType
    FROM #B
    WHERE Category = 'Blocking'
    GROUP BY WaitType
    ORDER BY SUM(WaitSeconds) DESC;


-- 12) Month-Over-Month Trends
    -- This has not yet had a practical test, as only 1 month has been rolled up

    DECLARE
          @PrevTotalWaitSeconds      decimal(18,2)
        , @PrevCPUWaitSeconds        decimal(18,2)
        , @PrevMemoryWaitSeconds     decimal(18,2)
        , @PrevDiskWaitSeconds       decimal(18,2)
        , @PrevBlockingWaitSeconds   decimal(18,2);

    SELECT
          @PrevTotalWaitSeconds    = TotalWaitSeconds
        , @PrevCPUWaitSeconds      = CPUWaitSeconds
        , @PrevMemoryWaitSeconds   = MemoryWaitSeconds
        , @PrevDiskWaitSeconds     = DiskWaitSeconds
        , @PrevBlockingWaitSeconds = BlockingWaitSeconds
    FROM Pulse.Waits_MonthlyRollup
    WHERE RollupMonth = DATEADD(MONTH, -1, @RollupMonth)
      AND ServerName = @ServerName;

    DECLARE
          @MoMTotalWaitChangePct    decimal(6,2)
        , @MoMCPUWaitChangePct      decimal(6,2)
        , @MoMMemoryWaitChangePct   decimal(6,2)
        , @MoMDiskWaitChangePct     decimal(6,2)
        , @MoMBlockingWaitChangePct decimal(6,2);

    SET @MoMTotalWaitChangePct =
        CASE WHEN @PrevTotalWaitSeconds = 0 OR @PrevTotalWaitSeconds IS NULL THEN NULL
             ELSE ROUND((@TotalWaitSeconds - @PrevTotalWaitSeconds) / @PrevTotalWaitSeconds * 100, 2)
        END;

    SET @MoMCPUWaitChangePct =
        CASE WHEN @PrevCPUWaitSeconds = 0 OR @PrevCPUWaitSeconds IS NULL THEN NULL
             ELSE ROUND((@CPUWaitSeconds - @PrevCPUWaitSeconds) / @PrevCPUWaitSeconds * 100, 2)
        END;

    SET @MoMMemoryWaitChangePct =
        CASE WHEN @PrevMemoryWaitSeconds = 0 OR @PrevMemoryWaitSeconds IS NULL THEN NULL
             ELSE ROUND((@MemoryWaitSeconds - @PrevMemoryWaitSeconds) / @PrevMemoryWaitSeconds * 100, 2)
        END;

    SET @MoMDiskWaitChangePct =
        CASE WHEN @PrevDiskWaitSeconds = 0 OR @PrevDiskWaitSeconds IS NULL THEN NULL
             ELSE ROUND((@DiskWaitSeconds - @PrevDiskWaitSeconds) / @PrevDiskWaitSeconds * 100, 2)
        END;

    SET @MoMBlockingWaitChangePct =
        CASE WHEN @PrevBlockingWaitSeconds = 0 OR @PrevBlockingWaitSeconds IS NULL THEN NULL
             ELSE ROUND((@BlockingWaitSeconds - @PrevBlockingWaitSeconds) / @PrevBlockingWaitSeconds * 100, 2)
        END;


-- 13) Insert the data

    INSERT INTO Pulse.Waits_MonthlyRollup (
          RollupMonth
        , ServerName
        , TotalWaitSeconds
        , TotalResourceSeconds
        , TotalSignalSeconds
        , SignalToResourceRatio
        , CPUWaitSeconds
        , MemoryWaitSeconds
        , DiskWaitSeconds
        , BlockingWaitSeconds
        , OtherWaitSeconds
        , CPUWaitPct
        , MemoryWaitPct
        , DiskWaitPct
        , BlockingWaitPct
        , OtherWaitPct
        , TopWaitType1
        , TopWaitType1Seconds
        , TopWaitType1Pct
        , TopWaitType2
        , TopWaitType2Seconds
        , TopWaitType2Pct
        , TopWaitType3
        , TopWaitType3Seconds
        , TopWaitType3Pct
        , PeakBlockingHourLocal
        , TopBlockingWaitType
        , MoMTotalWaitChangePct
        , MoMCPUWaitChangePct
        , MoMMemoryWaitChangePct
        , MoMDiskWaitChangePct
        , MoMBlockingWaitChangePct
    )
    VALUES (
          @RollupMonth
        , @ServerName
        , @TotalWaitSeconds
        , @TotalResourceSeconds
        , @TotalSignalSeconds
        , @SignalToResourceRatio
        , @CPUWaitSeconds
        , @MemoryWaitSeconds
        , @DiskWaitSeconds
        , @BlockingWaitSeconds
        , @OtherWaitSeconds
        , @CPUWaitPct
        , @MemoryWaitPct
        , @DiskWaitPct
        , @BlockingWaitPct
        , @OtherWaitPct
        , @TopWaitType1
        , @TopWaitType1Seconds
        , @TopWaitType1Pct
        , @TopWaitType2
        , @TopWaitType2Seconds
        , @TopWaitType2Pct
        , @TopWaitType3
        , @TopWaitType3Seconds
        , @TopWaitType3Pct
        , @PeakBlockingHourLocal
        , @TopBlockingWaitType
        , @MoMTotalWaitChangePct
        , @MoMCPUWaitChangePct
        , @MoMMemoryWaitChangePct
        , @MoMDiskWaitChangePct
        , @MoMBlockingWaitChangePct
    );


-- 14) Cleanup temp tables

    DROP TABLE #B
    DROP TABLE #Category
    DROP TABLE #TopWaits

END;
GO


