USE [SQLPulse];
GO

CREATE PROCEDURE [Pulse].[Module_Disk_MonthlyRollup]
AS
BEGIN
    SET NOCOUNT ON;

/* *******************************************************************************************************************

Source: SQLPulse: Module_Disk_MonthlyRollup
Build: 1.0
Build Date: 2026-02-21

This is one of the reporting routines for the Disk module of SqlPulse
This procedures calculates the various Disk values for the monthly report/health check
This procedure will execute every 5 minutes along with the rest of the Pulse stored procedures;
    this is a deliberate design decision to maintain a dual job configuration

Notes:
    - Rollup is per-server, per-month.
    - Unlike CPU & Memory, this rollup produces multiple rows per month, due to the dual nature of the data collection
    - There are two different factors at play: metrics per-disk and metrics per-database (including per file)
    - Use the RollupMonth field to identify all related rows

NOTE: At this time, the various Reporting procedures do NOT follow the convention of the other
stored procedures where the first activity is to execute [dbo].[UpdateLastServerStart]. The
current reasoning is that, since the Reporting procedures are in the tier 3 of the 
Execution order, you can't get here without having gone through all the Monitoring procedures
This may be revisited in the future; I want to evaluate the run time of the master job in release candidate 1

NOTE: Note that this all processes via UTC and NOT by local time. This is a deliberate decision for v1, but a future
version will support user-specified time choices, including Local, Server Time Zone, or even a custom offset

This procedure is in two sections:
    Section A calculates Disk metrics: size, growth, performance, if has SQL files, etc
    Section B calculates database metrics: file size, performance, VLF counts, etc

It performs the following activities:

    1) Declare the internal variables
        -> Unlike other rollup procedures, there are two exit points, one in each section
        
    SECTION A -- Drive-level rollup
    
    2) Exit if this section of the rollup has already been completed
    3) Build the various data sets
    4) Insert the drive rollup data
        -> Not all table columns are applicable, but all are ennumerated so values are controlled
    
    SECTION B -- Database-level rollup

    5) Exit if this section of the rollup has already been completed
    6) Precompute VLF counts for the rollup
        -> Necessary due to the use of DBCC

    NOTE: In SQL 2016 and above, getting VLF data is trivial via [sys.dm_db_log_info]
        The code in this sproc is more complex for SQL 2012/14 compatibility
    
    7) Build the various data sets

    NOTE: The VLF values that determine the urgency are semi-arbitrary. Anything under 100 is acceptable
        Anything over 200 should be addressed quickly; by the time you've passed 500, it's a real problem
        I chose 100, 500, and 1000 as my compromise breakpoints, but YMMV

    8) Insert the database rollup data
        -> Not all table columns are applicable, but all are ennumerated so values are controlled
        
******************************************************************************************************************* */

-- 1) Declare the internal variables

    DECLARE @ServerName SYSNAME = @@SERVERNAME
    
    DECLARE @RollupMonth DATE =
        DATEADD(MONTH, -1,
            DATEFROMPARTS(
                YEAR(SYSUTCDATETIME()),
                MONTH(SYSUTCDATETIME()),
                1));

    DECLARE 
        @StartDate DATETIME2(3) = @RollupMonth,                     -- 1st of month UTC
        @EndDate   DATETIME2(3) = DATEADD(MONTH, 1, @RollupMonth),  -- 1st of next month UTC
        @GeneratedLocal datetime2(3) = SYSDATETIME(),
        @GeneratedUTC datetime2(3) = SYSUTCDATETIME()
           

/* ************************************************

    SECTION A -- Disk Rollup

************************************************ */

-- 2) Exit if this section of the rollup has already been completed

    IF EXISTS (
        SELECT 1
        FROM Pulse.Disk_MonthlyRollup
        WHERE RollupMonth = @RollupMonth
          AND ServerName = @ServerName
          AND RollupType = 'Drive'
    )
    BEGIN
        PRINT 'Drive rollup already exists for this month.';
    END
    ELSE
    BEGIN


-- 3) Build the various data sets

    -- Raw Disk_Information with window functions

        ;WITH Raw AS
        (
            SELECT
                DriveLetterOrMountPath,
                DriveType,
                Label AS DriveLabel,
                IsMountPoint,
                SizeKB,
                FreeSpaceKB,
                UsedSpaceKB,
                PercentFree,
                PercentUsed,
                EventTimeUTC,

                FIRST_VALUE(UsedSpaceKB) OVER (
                    PARTITION BY DriveLetterOrMountPath
                    ORDER BY EventTimeUTC
                ) AS FirstUsedKB,

                LAST_VALUE(UsedSpaceKB) OVER (
                    PARTITION BY DriveLetterOrMountPath
                    ORDER BY EventTimeUTC
                    ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
                ) AS LastUsedKB
            FROM Pulse.Disk_Information
            WHERE EventTimeUTC >= @StartDate
                AND EventTimeUTC <  @EndDate
                AND DriveType != 'CD-ROM'
        ),

       
    -- Aggregated Disk_Information
       
        Info AS
        (
            SELECT
                DriveLetterOrMountPath,
                DriveType,
                DriveLabel,
                IsMountPoint,

                AVG(SizeKB)        AS AvgSizeKB,
                AVG(FreeSpaceKB)   AS AvgFreeSpaceKB,
                AVG(UsedSpaceKB)   AS AvgUsedSpaceKB,
                AVG(PercentFree)   AS AvgPercentFree,
                AVG(PercentUsed)   AS AvgPercentUsed,

                MIN(FirstUsedKB) AS FirstUsedKB,
                MAX(LastUsedKB)  AS LastUsedKB,

                MAX(UsedSpaceKB) AS MaxUsedSpaceKB,
                MIN(FreeSpaceKB) AS MinFreeSpaceKB,

                SUM(CASE WHEN PercentFree < 10 THEN 1 ELSE 0 END) AS DaysAtCriticalFree
            FROM Raw
            GROUP BY DriveLetterOrMountPath, DriveType, DriveLabel, IsMountPoint
        ),


    -- Resolve mount point for each file and aggregate latency

        Latency AS
        (
            SELECT
                mp.DriveLetterOrMountPath,
                AVG(dl.ReadLatency)  AS AvgReadLatency_ms,
                AVG(dl.WriteLatency) AS AvgWriteLatency_ms,
                AVG(dl.AvgLatency)   AS AvgOverallLatency_ms,
                MAX(dl.AvgLatency)   AS WorstObservedLatency_ms
            FROM Pulse.Disk_Latency dl
            CROSS APPLY
            (
                SELECT TOP 1 di.DriveLetterOrMountPath
                FROM Pulse.Disk_Information di
                WHERE di.DriveLetterOrMountPath = LEFT(dl.PhysicalName, LEN(di.DriveLetterOrMountPath))
                ORDER BY LEN(di.DriveLetterOrMountPath) DESC
            ) AS mp
            WHERE dl.EventTimeUTC >= @StartDate
              AND dl.EventTimeUTC <  @EndDate
            GROUP BY mp.DriveLetterOrMountPath
        ),


    -- Last sample of the month for "current state" snapshot

        LastSample AS
        (
            SELECT di.DriveLetterOrMountPath,
                   di.FreeSpaceKB AS RollupFreeSpaceKB,
                   di.PercentFree AS RollupPercentFree
            FROM Pulse.Disk_Information di
            INNER JOIN
            (
                SELECT DriveLetterOrMountPath,
                       MAX(EventTimeUTC) AS MaxEventTimeUTC
                FROM Pulse.Disk_Information
                WHERE EventTimeUTC >= @StartDate
                  AND EventTimeUTC <  @EndDate
                GROUP BY DriveLetterOrMountPath
            ) AS x
                ON di.DriveLetterOrMountPath = x.DriveLetterOrMountPath
               AND di.EventTimeUTC = x.MaxEventTimeUTC
        )


-- 4) Insert the drive rollup data
    -- Not all table columns are applicable, but all are ennumerated so values are controlled

    INSERT INTO Pulse.Disk_MonthlyRollup
    (
        RollupMonth,
        RollupType,
        ServerName,

        DriveLetterOrMountPath,
        DriveLabel,
        DriveType,
        IsMountPoint,

        TotalSizeKB,
        FreeSpaceKB,
        UsedSpaceKB,
        PercentFree,
        PercentUsed,

        AbsoluteGrowthKB,
        PercentGrowth,
        DaysAtCriticalFree,
        MaxUsedSpaceKB,
        MinFreeSpaceKB,

        AvgReadLatency_ms,
        AvgWriteLatency_ms,
        AvgOverallLatency_ms,
        WorstObservedLatency_ms,

        IsSqlDisk,
            
        RollupFreeSpaceKB,
        RollupPercentFree,

        GeneratedUTC,
        GeneratedLocal
    )
    SELECT
        @RollupMonth,
        'Drive',
        @ServerName,

        i.DriveLetterOrMountPath,
        i.DriveLabel,
        i.DriveType,
        i.IsMountPoint,

        i.AvgSizeKB,
        i.AvgFreeSpaceKB,
        i.AvgUsedSpaceKB,
        i.AvgPercentFree,
        i.AvgPercentUsed,

        (i.LastUsedKB - i.FirstUsedKB) AS AbsoluteGrowthKB,
        CASE WHEN i.FirstUsedKB > 0
                THEN (CAST(i.LastUsedKB - i.FirstUsedKB AS DECIMAL(18,4)) / i.FirstUsedKB)
                ELSE NULL
        END AS PercentGrowth,

        i.DaysAtCriticalFree,
        i.MaxUsedSpaceKB,
        i.MinFreeSpaceKB,

        l.AvgReadLatency_ms,
        l.AvgWriteLatency_ms,
        l.AvgOverallLatency_ms,
        l.WorstObservedLatency_ms,

        CASE WHEN l.DriveLetterOrMountPath IS NOT NULL THEN 1 ELSE 0 END AS IsSqlDisk,

        ls.RollupFreeSpaceKB,
        ls.RollupPercentFree,

        @GeneratedUTC,
        @GeneratedLocal
    FROM Info i
    LEFT JOIN Latency l
        ON l.DriveLetterOrMountPath = i.DriveLetterOrMountPath
    LEFT JOIN LastSample ls
        ON ls.DriveLetterOrMountPath = i.DriveLetterOrMountPath;

END  -- end drive rollup block



/* ************************************************

    SECTION B -- Database Rollup

************************************************ */

-- 5) Exit if this section of the rollup has already been completed

    IF EXISTS (
        SELECT 1
        FROM Pulse.Disk_MonthlyRollup
        WHERE RollupMonth = @RollupMonth
          AND ServerName = @ServerName
          AND RollupType = 'DatabaseFile'
    )
    BEGIN
        PRINT 'Database-file rollup already exists for this month.';
        RETURN;
    END


-- 6) Precompute VLF counts for the rollup
        -- Necessary due to the use of DBCC
       
    IF OBJECT_ID('tempdb.dbo.#VLFResults', 'U') IS NOT NULL
        DROP TABLE #VLFResults;

    CREATE TABLE #VLFResults
    (
        DatabaseName SYSNAME,
        VLFCount INT
    );

    DECLARE @db SYSNAME;
    DECLARE @sql NVARCHAR(MAX);

    DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT name
    FROM sys.databases
    WHERE state = 0;  -- online only

    OPEN db_cursor;
    FETCH NEXT FROM db_cursor INTO @db;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        CREATE TABLE #loginfo
        (
            RecoveryUnitId INT NULL,
            FileId SMALLINT NULL,
            FileSize BIGINT NULL,
            StartOffset BIGINT NULL,
            FSeqNo INT NULL,
            Status TINYINT NULL,
            Parity TINYINT NULL,
            CreateLSN NUMERIC(25,0) NULL
        );

        SET @sql = N'DBCC LOGINFO (' + QUOTENAME(@db,'''') + ')';

        INSERT INTO #loginfo
        EXEC (@sql);

        INSERT INTO #VLFResults (DatabaseName, VLFCount)
        SELECT @db, COUNT(*) FROM #loginfo;

        DROP TABLE #loginfo;

        FETCH NEXT FROM db_cursor INTO @db;
    END

    CLOSE db_cursor;
    DEALLOCATE db_cursor;


-- 7) Build the various data sets

    -- Get raw latency numbers in prep for the aggregate
    
        ;WITH RawLatency AS
        (
            SELECT
                dl.DatabaseName,
                dl.PhysicalName,
                dl.ReadLatency,
                dl.WriteLatency,
                dl.AvgLatency,
                dl.EventTimeUTC,

                mp.DriveLetterOrMountPath
            FROM Pulse.Disk_Latency dl
            CROSS APPLY
            (
                SELECT TOP 1 di.DriveLetterOrMountPath
                FROM Pulse.Disk_Information di
                WHERE di.DriveLetterOrMountPath = LEFT(dl.PhysicalName, LEN(di.DriveLetterOrMountPath))
                ORDER BY LEN(di.DriveLetterOrMountPath) DESC
            ) AS mp
            WHERE dl.EventTimeUTC >= @StartDate
              AND dl.EventTimeUTC <  @EndDate
        ),

    -- Average out the values
    
        LatencyAgg AS
        (
            SELECT
                DatabaseName,
                PhysicalName,
                DriveLetterOrMountPath,

                AVG(ReadLatency)  AS AvgReadLatency_ms,
                AVG(WriteLatency) AS AvgWriteLatency_ms,
                AVG(AvgLatency)   AS AvgOverallLatency_ms,
                MAX(AvgLatency)   AS WorstObservedLatency_ms
            FROM RawLatency
            GROUP BY DatabaseName, PhysicalName, DriveLetterOrMountPath
        ),

    -- Get info on the individual files for each database
    
        FileInfo AS
        (
            SELECT
                DB_NAME(mf.database_id) AS DatabaseName,
                mf.physical_name AS PhysicalName,
                mf.type_desc AS FileType,
                mf.size * 8 AS FileSizeKB,
                mf.growth * 8 AS FileGrowthKB,
                LEFT(mf.physical_name, 2) AS FileDrive
            FROM sys.master_files mf
        ),

    -- Additional file info; name should be changed as it was originally chosen for addtional metrics
    
        DBHealth AS
        (
            SELECT
                DB_NAME(database_id) AS DatabaseName,
                SUM(CASE WHEN type_desc = 'ROWS' THEN 1 ELSE 0 END) AS DataFileCount,
                SUM(CASE WHEN type_desc = 'LOG'  THEN 1 ELSE 0 END) AS LogFileCount,
                SUM(size * 8) AS TotalDatabaseSizeKB
            FROM sys.master_files
            GROUP BY database_id
        ),

    -- Get the VLF count for each database and evaluate urgency
    
        VLF AS
        (
            SELECT
                DatabaseName,
                VLFCount,
                CASE 
                    WHEN VLFCount < 100 THEN 'Normal'
                    WHEN VLFCount < 500 THEN 'Warning'
                    WHEN VLFCount < 1000 THEN 'Severe'
                    ELSE 'Critical'
                END AS VLFSeverity
            FROM #VLFResults
        )

-- 8) Insert the database rollup data
    -- Not all table columns are applicable, but all are ennumerated so values are controlled

    INSERT INTO Pulse.Disk_MonthlyRollup
    (
        RollupMonth,
        RollupType,
        ServerName,

        DriveLetterOrMountPath,
        DriveLabel,
        DriveType,
        IsMountPoint,
        IsSqlDisk,

        DatabaseName,
        PhysicalName,
        FileType,
        FileDrive,

        FileSizeKB,
        FileGrowthKB,

        AvgReadLatency_ms,
        AvgWriteLatency_ms,
        AvgOverallLatency_ms,
        WorstObservedLatency_ms,

        VLFCount,
        VLFSeverity,
        DataFileCount,
        LogFileCount,
        TotalDatabaseSizeKB,
        TotalDatabaseGrowthKB,

        GeneratedUTC,
        GeneratedLocal
    )
    SELECT
        @RollupMonth,
        'DatabaseFile',
        @ServerName,

        l.DriveLetterOrMountPath,
        NULL, NULL, NULL,
        1,  -- Always SQL disk for file rows

        l.DatabaseName,
        l.PhysicalName,
        fi.FileType,
        fi.FileDrive,

        fi.FileSizeKB,
        fi.FileGrowthKB,

        l.AvgReadLatency_ms,
        l.AvgWriteLatency_ms,
        l.AvgOverallLatency_ms,
        l.WorstObservedLatency_ms,

        v.VLFCount,
        v.VLFSeverity,
        dh.DataFileCount,
        dh.LogFileCount,
        dh.TotalDatabaseSizeKB,
        NULL,  -- TotalDatabaseGrowthKB (optional for v1)

        SYSUTCDATETIME(),
        SYSDATETIME()
    FROM LatencyAgg l
    LEFT JOIN FileInfo fi
        ON fi.DatabaseName = l.DatabaseName
       AND fi.PhysicalName = l.PhysicalName
    LEFT JOIN DBHealth dh
        ON dh.DatabaseName = l.DatabaseName
    LEFT JOIN VLF v
        ON v.DatabaseName = l.DatabaseName;


END
GO
