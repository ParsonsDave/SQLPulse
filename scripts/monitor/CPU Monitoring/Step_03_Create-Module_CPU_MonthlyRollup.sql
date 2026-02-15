USE [SQLPulse]
GO

/****** Object:  StoredProcedure [Pulse].[Module_CPU_MonthlyRollup]    Script Date: 2/15/2026 3:05:02 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [Pulse].[Module_CPU_MonthlyRollup]
AS
BEGIN
    SET NOCOUNT ON;

/* *******************************************************************************************************************

Source: SQLPulse: CPU_Reporting_MonthlyRollup
Build: 1.0
Build Date: 2026-02-14

This is one of the reporting routines for the CPU module of SqlPulse
This procedures calculates the various CPU values for the monthly report/health check
This procedure will execute every 5 minutes along with the rest of the Pulse stored procedures;
    this is a deliberate design decision to maintain a dual job configuration

NOTE: At this time, the various Reporting procedures do NOT follow the convention of the other
stored procedures where the first activity is to execute [dbo].[UpdateLastServerStart]. The
current reasoning is that, since the Reporting procedures are in the tier 3 of the 
Execution order, you can't get here without having gone through all the Monitoring procedures
This may be revisited in the future; I want to evaluate the run time of the master job in release candidate 1

NOTE: Note that this all processes via UTC and NOT by local time. This is a deliberate decision for v1, but a future
version will support user-specified time choices, including Local, Server Time Zone, or even a custom offset

It performs the following activities:

   1) Determine if the monthly rollup has already been completed; this should only ever execute once per month
        -> Exit the procedure if this month already has an execution
   2) Declare the internal variables
   3) Create and populate the temp table for calculating everything

   NOTE: Due to the number of calculations and how easily they are grouped administratively, there
   are many "steps" listed here, even though they could easily be done in a single batch; as noted elsewhere, 
   one of the key goals for Pulse is ease of accessibility for the code

   4) Calculate Data Completeness: How much of the possible data is present in the table?
   5) Calculate Overall Load percentages
   6) Calculate Median values
   7) Calculate Load Above Median for various counters; that is, the average of utilization above the median value
   8) Calculate the 90th percentile values
   9) Calculate Saturation values: How many datapoints are above 70% & when does the greatest cpu stress start
   10) Calculate SQL vs Non-SQL - Differentiating the type of server load; very valuable on mixed-use systems
   11) Insert the values into the table Pulse_CPUMonthlyRollup

******************************************************************************************************************* */

-- 0) Drop the temp table if it exists ; you'll thank me if you pull this code out to futz with it

    IF OBJECT_ID('tempdb.dbo.#CPU', 'U') IS NOT NULL
        DROP TABLE #CPU;
        
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
        FROM [Pulse].[CPU_MonthlyRollup]
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
                        
        -- Values to calculate

        -- Data Completeness
            @CollectedPoints int,
            @ExpectedPoints int,
            @AccuracyPercent decimal(5,2),

        -- Overall Load percentages
            @AvgTotalCPU decimal(5,2),
            @PeakTotalCPU decimal(5,2),
            @P90TotalCPU decimal(5,2),
        
        -- Median Values
            @MedianSQLCPU decimal(5,2),
            @MedianNonSQLCPU decimal(5,2),
            @MedianTotalCPU decimal(5,2),
        
        -- Load Above Median
            @LoadAboveMedianSQL decimal(5,2),
            @LoadAboveMedianNonSQL decimal(5,2),
            @LoadAboveMedianTotal decimal(5,2),
        
         -- 90th Percentile Values
            @P90SQLCPU decimal(5,2),
            @P90NonSQLCPU decimal(5,2),
            @PctInTop10Total decimal(5,2),
        
        -- Saturation Values
            @SaturationHours int,
            @WorstHourStart datetime2(0),
       
        -- SQL vs Non-SQL
            @SQLPercentOfTotal decimal(5,2),
            @NonSQLPercentOfTotal decimal(5,2);


-- 3) Create and populate the temp table for calculating everything

    ;WITH Raw AS
    (
        SELECT
            EventTimeUTC,
            SqlService,
            NonSqlProcess,
            IdleProcess,
            (100 - IdleProcess) AS TotalCPU
        FROM Pulse.CPU_Data
        WHERE EventTimeUTC >= @StartDate
          AND EventTimeUTC <  @EndDate
    )
    SELECT *
    INTO #CPU
    FROM Raw;

   
-- 4) Calculate Data Completeness: How much of the possible data is present in the table?

    SET @ExpectedPoints = DATEDIFF(MINUTE, @StartDate, @EndDate);   -- 1 row per minute expected
    SET @CollectedPoints = (SELECT COUNT(*) FROM #CPU);             -- The number of rows actually gathered
    SET @AccuracyPercent = 
        CASE WHEN @ExpectedPoints = 0 THEN 0
            ELSE (100.0 * @CollectedPoints / @ExpectedPoints)
        END;                                                        -- WHat percentage of the potential data was actually recorded


-- 5) Calculate Overall Load percentages

    SET @AvgTotalCPU = (SELECT AVG(CAST(TotalCPU AS decimal(5,2))) FROM #CPU)
    SET @PeakTotalCPU = (SELECT MAX(TotalCPU) FROM #CPU)
    
      
/* *****************************************************************************************************************************************

This big, messy block was me trying to work out why the heck I was getting this error in the [;WITH P] block below:

    Arithmetic overflow error converting numeric to data type numeric

This looks to be a quirk of the database engine wanting to do integer math before actually converting things to decimal,
even when the values are in friggin decimal already. The solution was just to make the landing decimal value
large enough to take whatever integer calculation is was doing before the final type assignment, but I wanted to leave this
block here as a reminder to myself of trying to work this nonsense out.

I'm leaving the lines with the additional comment marker '--' just so they don't appear to be anything useful no matter
how you might look at this code.

--   DECLARE @TotalRecords int = (SELECT COUNT(*) FROM #CPU)
--   DECLARE @90PctMark decimal(5,2) = (SELECT DISTINCT(PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY TotalCPU) OVER ()) FROM #CPU)
--   --DECLARE @NumberOver90Pct decimal(5,2) = (CAST(SELECT COUNT(*) FROM #CPU WHERE TotalCPU > @90PctMark) AS decimal(5,2))
--   DECLARE @NumberOver90Pct decimal(7,2) =
--    CAST(
--        (SELECT COUNT(TotalCPU)
--         FROM #CPU
--         WHERE TotalCPU > @90PctMark)
--        AS decimal(7,2)
--    );
--    SELECT @90PctMark, @NumberOver90Pct

--   --SET @NumberOver90Pct = (SELECT CAST(@NumberOver90Pct AS decimal(18,9)))
--   DECLARE @TheAnswer decimal(10,5) = ((SELECT @NumberOver90Pct / @TotalRecords))
--   SELECT (@NumberOver90Pct / @TotalRecords) * 100 AS Mathing
--   --SELECT * FROM #CPU
--   SELECT @TotalRecords as TotalRecords, @90PctMark As [90PctMark], @NumberOver90Pct as NumberOver90Pct, @TheAnswer as TheAnswer

***************************************************************************************************************************************** */

    ;WITH P AS
    (
        SELECT P90 = (SELECT DISTINCT(PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY TotalCPU) OVER ()) FROM #CPU)
    )
    SELECT @PctInTop10Total =
    (
        SELECT CAST(
                   (100.0 * COUNT(*) / NULLIF(@CollectedPoints, 0))
                   AS decimal(7,2)
               )
        FROM #CPU
        CROSS JOIN P
        WHERE TotalCPU >= P.P90
    );
    

-- 6) Calculate Median values

    SELECT @MedianSQLCPU =
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY SqlService)
        OVER ()
    FROM #CPU;

   SELECT @MedianNonSQLCPU =
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY NonSqlProcess)
        OVER ()
    FROM #CPU;

   SELECT @MedianTotalCPU =
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY TotalCPU)
        OVER ()
    FROM #CPU;
    

-- 7) Calculate Load Above Median for various counters; that is, the average of utilization above the median value

    SELECT @LoadAboveMedianSQL =
    (
        SELECT AVG(SqlService)
        FROM #CPU
        WHERE SqlService > @MedianSQLCPU
    );

    -- NonSQL
    SELECT @LoadAboveMedianNonSQL =
    (
        SELECT AVG(NonSqlProcess)
        FROM #CPU
        WHERE NonSqlProcess > @MedianNonSQLCPU
    );

    -- Total
    SELECT @LoadAboveMedianTotal =
    (
        SELECT AVG(TotalCPU)
        FROM #CPU
        WHERE TotalCPU > @MedianTotalCPU
    );


-- 8) Calculate the 90th percentile values

    SELECT @P90SQLCPU =
        PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY SqlService)
        OVER ()
    FROM #CPU;
    
    SELECT @P90NonSQLCPU =
        PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY NonSqlProcess)
        OVER ()
    FROM #CPU;

    SET @P90TotalCPU = (SELECT DISTINCT(PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY TotalCPU) OVER ()) FROM #CPU);

-- 9) Calculate Saturation values: How many datapoints are above 70% & when does the greatest cpu stress start

    ---------------------------------------------------------------------
    -- CPU Saturation Hours and Worst Hour Detection
    -- Saturation = any hour where TotalCPU > 85%
    ---------------------------------------------------------------------

    ;WITH Hourly AS
    (
        SELECT
            DATEADD(HOUR,
                    DATEDIFF(HOUR, 0, EventTimeUTC),
                    0) AS HourStart,
            AVG(TotalCPU) AS AvgCPU
        FROM #CPU
        GROUP BY DATEADD(HOUR,
                         DATEDIFF(HOUR, 0, EventTimeUTC),
                         0)
    ),
    Saturated AS
    (
        SELECT *
        FROM Hourly
        WHERE AvgCPU > 85  -- saturation threshold
    )
    SELECT
        @SaturationHours = COUNT(*),
        @WorstHourStart = (
            SELECT TOP (1) HourStart
            FROM Saturated
            ORDER BY AvgCPU DESC
        )
    FROM Saturated;
    
   
-- 10) Calculate SQL vs Non-SQL - Differentiating the type of server load; very valuable on mixed-use systems

    DECLARE @TotalSQL bigint,
            @TotalNonSQL bigint,
            @TotalCPU bigint;

    -- Sum CPU usage across all minutes
    SELECT
        @TotalSQL    = SUM(SqlService),
        @TotalNonSQL = SUM(NonSqlProcess),
        @TotalCPU    = SUM(SqlService + NonSqlProcess)
    FROM #CPU;

    -- Avoid divide-by-zero
    IF @TotalCPU = 0
    BEGIN
        SET @SQLPercentOfTotal = 0;
        SET @NonSQLPercentOfTotal = 0;
    END
    ELSE
    BEGIN
        SET @SQLPercentOfTotal    = (100.0 * @TotalSQL    / @TotalCPU);
        SET @NonSQLPercentOfTotal = (100.0 * @TotalNonSQL / @TotalCPU);
    END;
   
   
-- 11) Insert the values into the table Pulse_CPUMonthlyRollup

    INSERT INTO Pulse.CPU_MonthlyRollup
    (
        RollupMonth,
        ServerName,

        ExpectedPoints,
        CollectedPoints,
        AccuracyPercent,

        AvgTotalCPU,
        PeakTotalCPU,
        P90TotalCPU,

        MedianSQLCPU,
        MedianNonSQLCPU,
        MedianTotalCPU,

        LoadAboveMedianSQL,
        LoadAboveMedianNonSQL,
        LoadAboveMedianTotal,

        P90SQLCPU,
        P90NonSQLCPU,
        PctInTop10Total,

        SaturationHours,
        WorstHourStart,

        SQLPercentOfTotal,
        NonSQLPercentOfTotal,

        GeneratedUTC,
        GeneratedLocal,
        ReportGenerationTimeMethod
    )
    VALUES
    (
        @RollupMonth,
        @ServerName,

        @ExpectedPoints,
        @CollectedPoints,
        @AccuracyPercent,

        @AvgTotalCPU,
        @PeakTotalCPU,
        @P90TotalCPU,

        @MedianSQLCPU,
        @MedianNonSQLCPU,
        @MedianTotalCPU,

        @LoadAboveMedianSQL,
        @LoadAboveMedianNonSQL,
        @LoadAboveMedianTotal,

        @P90SQLCPU,
        @P90NonSQLCPU,
        @PctInTop10Total,

        @SaturationHours,
        @WorstHourStart,

        @SQLPercentOfTotal,
        @NonSQLPercentOfTotal,

        @GeneratedUTC,
        @GeneratedLocal,
        @ReportGenerationTimeMethod
    )

END
GO


