CREATE PROCEDURE Pulse.Module_Blocking_MonthlyRollup
AS
BEGIN
    SET NOCOUNT ON;

/* *******************************************************************************************************************

Source: SQLPulse: Module_Blocking_MonthlyRollup
Build: 1.2
Build Date: 2026-03-04

This is the monthly rollup of blocking statistics; this table holds the values that get inserted into the 
relevant reports. This procedure will execute every 5 minutes along with the rest of the Pulse stored procedures;
this is a deliberate design decision to maintain a dual job configuration

NOTE: At this time, the various Reporting procedures do NOT follow the convention of the other
stored procedures where the first activity is to execute [dbo].[UpdateLastServerStart]. The
current reasoning is that, since the Reporting procedures are in the tier 3 of the 
Execution order, you can't get here without having gone through all the Monitoring procedures
This may be revisited in the future; I want to evaluate the run time of the master job in release candidate 1

NOTE: Note that this all processes via UTC and NOT by local time. This is a deliberate decision for v1, but a future
version will support user-specified time choices, including Local, Server Time Zone, or even a custom offset

NOTE: Any adjustment to the rollup will require an adjustment to the table Blocking_MonthlyRollup

NOTE: The input parameters are new. After several iterations of manually correcting data in both this and
the Waits 'ByMonth' tables, I wanted a way to force new rollups without deleting previous ones. At publish
time I not only haven't used it, I haven't even tested it. It's a still a good option, but I won't come
back to it until after the monthly Reporting is complete.

It performs the following activities:

    1. Determine if the monthly rollup has already been completed; 
        -- Exit the procedure if this month already has an execution
        -- ServerName is to track if you move an existing Pulse to a new server
    2. Insert the data for the rollup into a temp table
    3. Apply Start‑of‑Month negative adjustments
    4. Aggregate per database
    5. Month‑over‑Month deltas
    6. Insert into final table
    7. Cleanup
    

******************************************************************************************************************* */
    
-------------------------------------------------------------------------
-- 1. Determine if the monthly rollup has already been completed; 
--  Exit the procedure if this month already has an execution
-- ServerName is to track if you move an existing Pulse to a new server
-------------------------------------------------------------------------
        
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
    
    DECLARE @RollupMonth date =
        DATEADD(MONTH, -1, DATEFROMPARTS(
            YEAR(SYSUTCDATETIME()),
            MONTH(SYSUTCDATETIME()),
            1));

    -- Exit if already processed
    IF EXISTS (
        SELECT 1
        FROM Pulse.Blocking_MonthlyRollup
        WHERE RollupMonth = @RollupMonth
          AND ServerName  = @ServerName
    )
        RETURN;

-------------------------------------------------------------------------
-- 2. Insert the data for the rollup into a temp table
-------------------------------------------------------------------------

    ;WITH Boundaries AS (
        SELECT
            ID,
            SnapshotDateUTC,
            SnapshotDateLocal,
            SnapshotType,
            ServerName,
            RollupMonth,
            DatabaseID,
            DatabaseName,
            RowLockWaitMs,
            PageLockWaitMs,
            TotalBlockingWaitMs,
            UptimeSeconds,
            ProcessorCount,
            TotalProcessorTimeSeconds
        FROM Pulse.Blocking_TimeByMonth
        WHERE RollupMonth = @RollupMonth
          AND ServerName  = @ServerName
    )
    SELECT *
    INTO #B
    FROM Boundaries;

    IF NOT EXISTS (SELECT 1 FROM #B)
        RETURN;

-------------------------------------------------------------------------
-- 3. Apply Start‑of‑Month negative adjustments
-------------------------------------------------------------------------

    IF EXISTS (SELECT 1 FROM #B WHERE SnapshotType = 'StartOfMonth')
    BEGIN
        UPDATE #B
        SET
              TotalProcessorTimeSeconds = -ABS(TotalProcessorTimeSeconds)
            , RowLockWaitMs             = -ABS(RowLockWaitMs)
            , PageLockWaitMs            = -ABS(PageLockWaitMs)
            , TotalBlockingWaitMs       = -ABS(TotalBlockingWaitMs)
        WHERE SnapshotType = 'StartOfMonth';
    END

-------------------------------------------------------------------------
-- 4. Aggregate per database
-------------------------------------------------------------------------
    ;WITH Agg AS (
        SELECT
            DatabaseID,
            DatabaseName,
            SUM(RowLockWaitMs)  / 1000.0 AS RowLockWaitSeconds,
            SUM(PageLockWaitMs) / 1000.0 AS PageLockWaitSeconds,
            SUM(TotalBlockingWaitMs) / 1000.0 AS TotalBlockingWaitSeconds,
            SUM(TotalProcessorTimeSeconds) AS TotalProcessorTimeSeconds
        FROM #B
        GROUP BY DatabaseID, DatabaseName
    ),
    Clean AS (
        SELECT *
        FROM Agg
        WHERE DatabaseName <> 'tempdb'
    ),
    InstanceTotals AS (
        SELECT
            SUM(TotalBlockingWaitSeconds) AS InstanceBlockingSeconds,
            SUM(TotalProcessorTimeSeconds) AS InstanceCPUSeconds
        FROM Clean
    ),
    Ranked AS (
        SELECT
            c.*,
            it.InstanceBlockingSeconds,
            it.InstanceCPUSeconds,
            ROW_NUMBER() OVER (ORDER BY c.TotalBlockingWaitSeconds DESC) AS RankWithinInstance
        FROM Clean c
        CROSS JOIN InstanceTotals it
    ),
    FinalCalc AS (
        SELECT
            @RollupMonth AS RollupMonth,
            DatabaseID,
            @ServerName AS ServerName,
            DatabaseName,
            RowLockWaitSeconds,
            PageLockWaitSeconds,
            CASE WHEN TotalBlockingWaitSeconds = 0 THEN NULL
                 WHEN RowLockWaitSeconds >= PageLockWaitSeconds THEN 'ROW'
                 ELSE 'PAGE'
            END AS TopBlockingType,
            CASE WHEN TotalBlockingWaitSeconds = 0 THEN NULL
                 WHEN RowLockWaitSeconds >= PageLockWaitSeconds
                      THEN ROUND((RowLockWaitSeconds / TotalBlockingWaitSeconds) * 100.0, 2)
                 ELSE ROUND((PageLockWaitSeconds / TotalBlockingWaitSeconds) * 100.0, 2)
            END AS TopBlockingTypePct,
            CASE WHEN InstanceBlockingSeconds = 0 THEN NULL
                 ELSE ROUND((TotalBlockingWaitSeconds / InstanceBlockingSeconds) * 100.0, 2)
            END AS PctOfInstanceBlocking,
            RankWithinInstance,
            CASE WHEN InstanceCPUSeconds = 0 THEN NULL
                 ELSE ROUND((TotalProcessorTimeSeconds / InstanceCPUSeconds) * 100.0, 2)
            END AS PctOfTotalProcessorTime,
            TotalBlockingWaitSeconds,
            TotalProcessorTimeSeconds
        FROM Ranked
    )
    SELECT *
    INTO #Current
    FROM FinalCalc;

-------------------------------------------------------------------------
-- 5. Month‑over‑Month deltas
-------------------------------------------------------------------------

    ;WITH Prev AS (
        SELECT *
        FROM Pulse.Blocking_MonthlyRollup
        WHERE RollupMonth = DATEADD(MONTH, -1, @RollupMonth)
          AND ServerName  = @ServerName
    )
    SELECT
        c.RollupMonth,
        c.DatabaseID,
        c.ServerName,
        c.DatabaseName,
        c.RowLockWaitSeconds,
        c.PageLockWaitSeconds,
        c.TopBlockingType,
        c.TopBlockingTypePct,
        c.PctOfInstanceBlocking,
        c.RankWithinInstance,
        c.PctOfTotalProcessorTime,
        CASE WHEN p.TotalBlockingWaitSeconds IS NULL OR p.TotalBlockingWaitSeconds = 0 THEN NULL
             ELSE ROUND(((c.TotalBlockingWaitSeconds - p.TotalBlockingWaitSeconds) / p.TotalBlockingWaitSeconds) * 100.0, 2)
        END AS MoMBlockingChangePct,
        CASE WHEN p.RowLockWaitSeconds IS NULL OR p.RowLockWaitSeconds = 0 THEN NULL
             ELSE ROUND(((c.RowLockWaitSeconds - p.RowLockWaitSeconds) / p.RowLockWaitSeconds) * 100.0, 2)
        END AS MoMRowLockChangePct,
        CASE WHEN p.PageLockWaitSeconds IS NULL OR p.PageLockWaitSeconds = 0 THEN NULL
             ELSE ROUND(((c.PageLockWaitSeconds - p.PageLockWaitSeconds) / p.PageLockWaitSeconds) * 100.0, 2)
        END AS MoMPageLockChangePct
    INTO #Final
    FROM #Current c
    LEFT JOIN Prev p
        ON p.DatabaseID = c.DatabaseID;

-------------------------------------------------------------------------
-- 6. Insert into final table
-------------------------------------------------------------------------

    INSERT INTO Pulse.Blocking_MonthlyRollup (
        RollupMonth,
        DatabaseID,
        ServerName,
        DatabaseName,
        RowLockWaitSeconds,
        PageLockWaitSeconds,
        TopBlockingType,
        TopBlockingTypePct,
        PctOfInstanceBlocking,
        RankWithinInstance,
        PctOfTotalProcessorTime,
        MoMBlockingChangePct,
        MoMRowLockChangePct,
        MoMPageLockChangePct
    )
    SELECT
        RollupMonth,
        DatabaseID,
        ServerName,
        DatabaseName,
        RowLockWaitSeconds,
        PageLockWaitSeconds,
        TopBlockingType,
        TopBlockingTypePct,
        PctOfInstanceBlocking,
        RankWithinInstance,
        PctOfTotalProcessorTime,
        MoMBlockingChangePct,
        MoMRowLockChangePct,
        MoMPageLockChangePct
    FROM #Final;

-------------------------------------------------------------------------
-- 7. Cleanup
-------------------------------------------------------------------------

    DROP TABLE #B
    DROP TABLE #Current
    DROP TABLE #Final

END
GO