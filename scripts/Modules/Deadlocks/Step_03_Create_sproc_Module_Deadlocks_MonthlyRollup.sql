USE [SQLPulse]
GO

/****** Object:  StoredProcedure [Pulse].[Module_Deadlocks_MonthlyRollup]    Script Date: 2/22/2026 9:13:04 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE PROCEDURE [Pulse].[Module_Deadlocks_MonthlyRollup]

AS
BEGIN

    SET NOCOUNT ON;


/* *******************************************************************************************************************

Source: SQLPulse: Module_Deadlocks_MonthlyRollup
Build: 1.0
Build Date: 2026-02-22

This is one of the reporting routines for the Deadlocks module of SqlPulse
This procedures calculates the various Deadlock values for the monthly report/health check
This procedure will execute every 5 minutes along with the rest of the Pulse stored procedures;
    this is a deliberate design decision to maintain a dual job configuration

Metrics (This should be copied or moved into the main documentation)
    TotalDeadlocks - The total number of deadlocks recorded in the Rollup Month
    AvgPerDay - The average number of deadlocks per day; this is based on the real day count of the month
    AvgPerWeek - The average number of deadlocks per week, based on the real day count of the month / 7
    Busiest Day - The date of the month that had the most deadlocks in total
    BusiestDayCount - The number of total deadlocks on the busiest day
    MonthOverMonthDelta - The difference in deadlocks between this month and the previous month
    ZeroDeadlockDays - The number of days in the month with no deadlocks at all
    PeakHourLocal - The hour of the day - in LOCAL time, NOT UTC - with the most deadlocks
    PeakHourLocalTxt - The PeakHour translated to a human-friendly format, ex: [7 PM]
    PeakHourCount - The number of deadlocks in the month that happened during that particula hour
    
NOTE: At this time, the various Reporting procedures do NOT follow the convention of the other
stored procedures where the first activity is to execute [dbo].[UpdateLastServerStart]. The
current reasoning is that, since the Reporting procedures are in the tier 3 of the 
Execution order, you can't get here without having gone through all the Monitoring procedures
This may be revisited in the future; I want to evaluate the run time of the master job in release candidate 1

NOTE: Note that unlike other rollups, this processes at least one item in local time rather than UTC (see above)
I'm not cencessarily sold on this idea, but Deadlocks is, by far, the most sparse module to be included in v1 of Pulse
This will be reevaluated at a later time.

As always, UTC is hard-coded, but a future version will support user-specified time choices, including Local, Server Time Zone, or even a custom offset

It performs the following activities:

    1) Declare the internal variables
    2) Exit if this section of the rollup has already been completed
    3) Capture Daily Aggregates into a Table Variable
        -> Previously I'd gone nuts with CTEs for rollups, but I had a huge issue here with the multiple steps to get metrics
        -> Normally this would have meant a temp table, but I went Table Variable after looking into max speed
        -> The last rollup module I did was Disk, which is taking waaaay too long to run atm (2-3 SECONDS)
    4) Math! Calculate Metrics
        -> There are notes for each calculation. I didn't eave spacing, so it may look too cluttered. Will look again later
    5) Insert the database rollup data
    6) Sanity Checking
        -> This is a commented code block to grab all returned data and variables
        -> Used in the event you pull the code out of the sproc for manual execution
            
******************************************************************************************************************* */

-- 1) Declare the internal variables

    DECLARE @Today                date = CAST(SYSUTCDATETIME() AS date);
    DECLARE @FirstOfThisMonth     date = DATEFROMPARTS(YEAR(@Today), MONTH(@Today), 1);
    DECLARE @FirstOfLastMonth     date = DATEADD(MONTH, -1, @FirstOfThisMonth);
    DECLARE @FirstOfTwoMonthsAgo  date = DATEADD(MONTH, -1, @FirstOfLastMonth);
    DECLARE @GeneratedUTC         datetime2(3) = SYSUTCDATETIME();
    DECLARE @GeneratedLocal       datetime2(3) = SYSDATETIME();

    DECLARE @ServerName            sysname         = @@SERVERNAME;
    DECLARE @TotalDeadlocks        int             = 0;
    DECLARE @AvgPerDay             decimal(10,2)   = 0;
    DECLARE @AvgPerWeek            decimal(10,2)   = 0;
    DECLARE @ZeroDays              int             = 0;
    DECLARE @BusiestDay            date            = NULL;
    DECLARE @BusiestDayCount       int             = 0;
    DECLARE @PeakHour              tinyint         = NULL;
    DECLARE @PeakHourCount         int             = 0;
    DECLARE @PrevMonthTotal        int             = 0;
    DECLARE @MonthDelta            int             = NULL;
    DECLARE @DaysInLastMonth       int;
    
    SET @DaysInLastMonth = DATEDIFF(DAY, @FirstOfLastMonth, @FirstOfThisMonth);

    
-- 2) Exit if this section of the rollup has already been completed

    IF EXISTS (
        SELECT 1
        FROM Pulse.Deadlocks_MonthlyRollup
        WHERE RollupMonth = @FirstOfLastMonth
          AND ServerName = @ServerName
    )
    BEGIN
        PRINT 'Deadlocks rollup already exists for this month.';
        RETURN;
    END
        
-- 3) Capture Daily Aggregates into a Table Variable

    DECLARE @DailyStats TABLE (
        EventDate date PRIMARY KEY,
        DailyDeadlocks int
    );

    INSERT INTO @DailyStats (EventDate, DailyDeadlocks)
    SELECT 
        CAST(EventTimeLocal AS date), 
        SUM(DeadlocksSinceLast)
    FROM Pulse.Deadlocks_Counter
    WHERE EventTimeLocal >= @FirstOfLastMonth 
      AND EventTimeLocal <  @FirstOfThisMonth
    GROUP BY CAST(EventTimeLocal AS date);


-- 4) Math! Calculate Metrics
    
    -- Total and Zero-Deadlock Days
    -- (Corrected to account for days missing from the table entirely)
        SELECT @TotalDeadlocks = ISNULL(SUM(DailyDeadlocks), 0) FROM @DailyStats;
    
        SELECT @ZeroDays = @DaysInLastMonth - COUNT(*) 
        FROM @DailyStats 
        WHERE DailyDeadlocks > 0;

    -- Busiest Day
        SELECT TOP (1)
            @BusiestDay      = EventDate,
            @BusiestDayCount = DailyDeadlocks
        FROM @DailyStats
        ORDER BY DailyDeadlocks DESC, EventDate ASC;

    -- Peak Hour (Aggregated across the whole month)
        SELECT TOP (1)
            @PeakHour      = DATEPART(HOUR, EventTimeLocal),
            @PeakHourCount = SUM(DeadlocksSinceLast)
        FROM Pulse.Deadlocks_Counter
        WHERE EventTimeLocal >= @FirstOfLastMonth 
          AND EventTimeLocal <  @FirstOfThisMonth
        GROUP BY DATEPART(HOUR, EventTimeLocal)
        ORDER BY SUM(DeadlocksSinceLast) DESC, DATEPART(HOUR, EventTimeLocal) ASC;

    -- Averages
        IF @DaysInLastMonth > 0
            SET @AvgPerDay = CAST(@TotalDeadlocks AS decimal(10,2)) / @DaysInLastMonth;

        SET @AvgPerWeek = CAST(@TotalDeadlocks AS decimal(10,2)) / (@DaysInLastMonth / 7.0);

    -- Month-over-month delta
    -- This *could* have just been left as my original query:
    --SELECT @PrevMonthTotal = (SELECT TotalDeadlocks FROM Pulse.Deadlocks_MonthlyRollup WHERE RollupMonth = @FirstOfTwoMonthsAgo)
    -- BUT, I don't want a NULL sitting in the column. I'd rather have a 0 and note it in the documentation or report

        SELECT @PrevMonthTotal = 
	    COALESCE(
		    (SELECT TotalDeadlocks FROM Pulse.Deadlocks_MonthlyRollup WHERE RollupMonth = @FirstOfTwoMonthsAgo),
		    0
	    );

        -- We only show a delta if there was data in the previous month (or if it was 0)
        SET @MonthDelta = @TotalDeadlocks - @PrevMonthTotal;


-- 5) Insert the database rollup data

    INSERT INTO Pulse.Deadlocks_MonthlyRollup
    (
        RollupMonth
        , ServerName
        , TotalDeadlocks
        , AvgPerDay
        , AvgPerWeek
        , BusiestDay
        , BusiestDayCount
        , MonthOverMonthDelta
        , ZeroDeadlockDays
        , PeakHourLocal
        , PeakHourLabel
        , PeakHourCount
        , GeneratedUTC
        , GeneratedLocal
    )
    VALUES
    (
        @FirstOfLastMonth
        , @ServerName
        , @TotalDeadlocks
        , @AvgPerDay
        , @AvgPerWeek
        , @BusiestDay
        , @BusiestDayCount
        , @MonthDelta
        , @ZeroDays
        , @PeakHour
        , CASE 
                WHEN @PeakHour = 0  THEN '12 AM'
                WHEN @PeakHour < 12 THEN CAST(@PeakHour AS varchar(2)) + ' AM'
                WHEN @PeakHour = 12 THEN '12 PM'
            ELSE CAST(@PeakHour - 12 AS varchar(2)) + ' PM'
            END
        , @PeakHourCount
        , @GeneratedUTC
        , @GeneratedLocal
    );


-- 6) Sanity Checking
    -- This is a commented code block to grab all returned data and variables
    -- Used in the event you pull the code out of the sproc for manual execution

    --SELECT 
    --    @FirstOfLastMonth AS RollupMonth
    --    , @ServerName AS ServerName
    --    , @TotalDeadlocks AS TotalDeadlocks
    --    , @AvgPerDay AS AvgPerDay
    --    , @AvgPerWeek AS AvgPerWeek
    --    , @BusiestDay AS BusiestDay
    --    , @BusiestDayCount AS BusiestDayCount
    --    , @MonthDelta AS MonthDelta
    --    , @ZeroDays AS ZeroDays
    --    , @PeakHour AS PeakHour
    --    , @PeakHourCount AS PeakHourCount
    --    , @GeneratedUTC AS GeneratedUTC
    --    , @GeneratedLocal AS GeneratedLocal
    --    , @Today AS Today
    --    , @FirstOfThisMonth AS FirstOfThisMonth
    --    , @FirstOfLastMonth AS FirstOfLastMonth
    --    , @FirstOfTwoMonthsAgo AS FirstOfTwoMonthsAgo
    --    , @DaysInLastMonth AS DaysInRollupMonth
    --    , CASE 
    --            WHEN @PeakHour = 0  THEN '12 AM'
    --            WHEN @PeakHour < 12 THEN CAST(@PeakHour AS varchar(2)) + ' AM'
    --            WHEN @PeakHour = 12 THEN '12 PM'
    --        ELSE CAST(@PeakHour - 12 AS varchar(2)) + ' PM'
    --        END AS PeakHourLabel;

END;
GO


