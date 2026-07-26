USE [SQLPulse]
GO

/****** Object:  StoredProcedure [Pulse].[Module_GeneralHealth_Database_MonthlyRollup]    Script Date: 7/25/2026 9:10:15 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO



CREATE PROCEDURE [Pulse].[Module_GeneralHealth_Database_MonthlyRollup]
AS
BEGIN
    SET NOCOUNT ON;

/* *******************************************************************************************************************

Source: SQLPulse: GeneralHealth_Database_MonthlyRollup
Build: 1.0
Build Date: 2026-07-25

This is one of the reporting routines for the CPU module of SqlPulse
This procedures fetches database information and settings for the monthly report/health check
This procedure will execute every 5 minutes along with the rest of the Pulse stored procedures;
    this is a deliberate design decision to maintain a dual job configuration

NOTE: At this time, the various Reporting procedures do NOT follow the convention of the other
stored procedures where the first activity is to execute [Pulse].[Module_Core_ServerRestartDates]. The
current reasoning is that, since the Reporting procedures are in the tier 3 of the 
Execution order, you can't get here without having gone through all the Monitoring procedures
This may be revisited in the future; I want to evaluate the run time of the master job in release candidate 1

NOTE: Note that this all processes via UTC and NOT by local time. This is a deliberate decision for v1, but a future
version will support user-specified time choices, including Local, Server Time Zone, or even a custom offset

NOTE: The earlier the SQL version this is monitoring, the more of the various data points will end up
with NULL values; this is intentional to make the project as compatible as possible. Be aware that this means
the destination table will take NULLs in every single data field. 

It performs the following activities:

   1) Determine if the monthly rollup has already been completed; this should only ever execute once per month
        -> Exit the procedure if this month already has an execution
   2) Build out VLF data
        A. Create a staging table to hold our final consolidated counts
        B. Build the version-safe dynamic SQL block for 2012+ DBCC LOGINFO structure
        C. Execute the block to populate our temp staging table
   3) Get the last known DBCC date
   4) Build out various CTEs with DB info
        A. Aggregate File Level Metrics (Drive letters, Percent Growth)
        B. Get the Latest Full and Log Backups from msdb
   5) Insert the values into the table GeneralHealth_Database_MonthlyRollup
   6) Clean up when finished

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
        FROM [Pulse].[GeneralHealth_Database_MonthlyRollup]
        WHERE RollupMonth = @RollupMonth
        AND ServerName = @ServerName
        )
    BEGIN
        RETURN;
    END


-- 2) Build out VLF data

    -- A. Create a staging table to hold our final consolidated counts

    IF OBJECT_ID('tempdb..#VLFCounts') IS NOT NULL DROP TABLE #VLFCounts;
    CREATE TABLE #VLFCounts (
        database_id INT,
        VLFCount INT,
        HasHighVLFCount BIT
    );

    -- B. Build the version-safe dynamic SQL block for 2012+ DBCC LOGINFO structure
    DECLARE @VLFQuery NVARCHAR(MAX) = N'';

    SELECT @VLFQuery = @VLFQuery + N'
        DECLARE @LogInfo2012_' + CAST(database_id AS NVARCHAR(10)) + N' TABLE (
            RecoveryUnitId INT, fileid SMALLINT, file_size BIGINT, start_offset BIGINT, 
            fseqno INT, [status] TINYINT, parity TINYINT, create_lsn NUMERIC(25,0)
        );
        INSERT INTO @LogInfo2012_' + CAST(database_id AS NVARCHAR(10)) + N' EXEC (''DBCC LOGINFO(['' + ' + QUOTENAME(name, '''') + ' + '']) WITH NO_INFOMSGS'');
        INSERT INTO #VLFCounts (database_id, VLFCount, HasHighVLFCount)
        SELECT ' + CAST(database_id AS NVARCHAR(10)) + N', @@ROWCOUNT, CASE WHEN @@ROWCOUNT > 99 THEN 1 ELSE 0 END;
    '
    FROM sys.databases 
    WHERE state = 0  -- Only loop through ONLINE databases
      AND name <> 'tempdb';

    -- C. Execute the block to populate our temp staging table

    EXEC sp_executesql @VLFQuery;


-- 3) Get the last known DBCC date

    /* *******************************************************************

    Get the last known DBCC date

    This is a lesser version of what's possible as of 2016 SP2, but
    all code in this version of Pulse is designed for a completely
    unpatched version of SQL 2012. This means the results from this
    query can be only partially positive - checktable and physical_only
    will both mark this as successful. 

    ******************************************************************* */

    SET NOCOUNT ON;

    CREATE TABLE #CheckDBResults (
        DatabaseName NVARCHAR(128),
        LastKnownGood DATETIME
    );

    CREATE TABLE #DBInfo (
        ParentObject NVARCHAR(255),
        Object NVARCHAR(255),
        Field NVARCHAR(255),
        Value NVARCHAR(255)
    );

    DECLARE @DatabaseName NVARCHAR(128);
    DECLARE @SQL NVARCHAR(500);

    DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT name
    FROM sys.databases
    WHERE database_id > 4      -- exclude system DBs
      AND state_desc = 'ONLINE'
    ORDER BY name;

    OPEN db_cursor;
    FETCH NEXT FROM db_cursor INTO @DatabaseName;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        TRUNCATE TABLE #DBInfo;

        SET @SQL = N'DBCC DBINFO([' + @DatabaseName + N']) WITH TABLERESULTS, NO_INFOMSGS;';

        BEGIN TRY
            INSERT INTO #DBInfo (ParentObject, Object, Field, Value)
            EXEC (@SQL);

            INSERT INTO #CheckDBResults (DatabaseName, LastKnownGood)
            SELECT @DatabaseName,
                   CASE WHEN Value = '1900-01-01 00:00:00.000'
                        THEN NULL
                        ELSE CONVERT(DATETIME, Value, 121)
                   END
            FROM #DBInfo
            WHERE Field = 'dbi_dbccLastKnownGood';
        END TRY
        BEGIN CATCH
            INSERT INTO #CheckDBResults (DatabaseName, LastKnownGood)
            VALUES (@DatabaseName, NULL);
        END CATCH;

        FETCH NEXT FROM db_cursor INTO @DatabaseName;
    END;

    CLOSE db_cursor;
    DEALLOCATE db_cursor;

    --SELECT *
    --FROM #CheckDBResults
    --ORDER BY LastKnownGood;


-- 4) Build out various CTEs with DB info

    WITH 
    -- A. Aggregate File Level Metrics (Drive letters, Percent Growth)
    FileMetrics AS (
        SELECT 
            database_id,
            MAX(CASE WHEN type = 0 AND is_percent_growth = 1 THEN 1 ELSE 0 END) AS HasPercentAutogrowth,
            MAX(CASE WHEN physical_name LIKE 'C:\%' THEN 1 ELSE 0 END) AS HasFilesOnCDisk
        FROM sys.master_files
        GROUP BY database_id
    ),



    -- B. Get the Latest Full and Log Backups from msdb
    BackupMetrics AS (
        SELECT 
            database_name,
            MAX(CASE WHEN type = 'D' THEN backup_finish_date END) AS LastFullBackupDate,
            MAX(CASE WHEN type = 'L' THEN backup_finish_date END) AS LastLogBackupDate
        FROM msdb.dbo.backupset
        GROUP BY database_name
    )



-- 4. Final Compilation and Evaluation Block

    INSERT INTO [Pulse].[GeneralHealth_Database_MonthlyRollup] 
    (
        [RollupMonth]
        ,[ServerName]
        ,[DatabaseName]
        ,[RecoveryModel]
        ,[IsPageVerificationNotChecksum]
        ,[HasHighVLFCount]
        ,[VLFCount]
        ,[HasPercentAutogrowth]
        ,[IsBackupOverdue]
        ,[LastFullBackupDate]
        ,[IsLogBackupOverdue]
        ,[LastLogBackupDate]
        ,[HasFilesOnCDisk]
        ,[IsAutoShrinkOn]
        ,[IsAutoCloseOn]
        ,[LastGoodCheckDB]
    )
    SELECT 
        @RollupMonth
        ,@ServerName
        ,d.name AS DatabaseName
        ,d.recovery_model_desc AS RecoveryModel
    
        -- Checksum validation
        ,CASE WHEN d.page_verify_option_desc <> 'CHECKSUM' THEN 1 ELSE 0 END AS IsPageVerificationNotChecksum
    
        -- VLF Status
        ,ISNULL(v.HasHighVLFCount, 0) AS HasHighVLFCount
        ,ISNULL(v.VLFCount, 0) AS VLFCount
    
        -- Autogrowth configuration
        ,ISNULL(f.HasPercentAutogrowth, 0) AS HasPercentAutogrowth
    
        -- Full Backup validation (Older than 7 days or never happened)
        ,CASE 
            WHEN d.name = 'tempdb' THEN 0
            WHEN b.LastFullBackupDate IS NULL THEN 1
            WHEN b.LastFullBackupDate < DATEADD(DAY, -7, GETDATE()) THEN 1 
            ELSE 0 
        END AS IsBackupOverdue
        ,b.LastFullBackupDate
    
        -- Log Backup validation (FULL/BULK_LOGGED with no backup in 24 hours)
        ,CASE 
            WHEN d.name = 'tempdb' THEN 0
            WHEN d.recovery_model_desc = 'SIMPLE' THEN 0
            WHEN b.LastLogBackupDate IS NULL THEN 1
            WHEN b.LastLogBackupDate < DATEADD(HOUR, -24, GETDATE()) THEN 1 
            ELSE 0 
        END AS IsLogBackupOverdue
        ,b.LastLogBackupDate
    
        -- File Location (Exclude system databases from C: drive alerting if desired, here checking User DBs)
        ,CASE WHEN d.database_id > 4 AND f.HasFilesOnCDisk = 1 THEN 1 ELSE 0 END AS HasFilesOnCDisk
    
        -- Anti-features
        ,d.is_auto_shrink_on AS IsAutoShrinkOn
        ,d.is_auto_close_on AS IsAutoCloseOn
    
        -- The Native Last Good DBCC Check (see notes above)
        ,(SELECT LastKnownGood FROM #CheckDBResults c WHERE DatabaseName = d.name)

    FROM sys.databases d
    LEFT JOIN FileMetrics f ON d.database_id = f.database_id
    LEFT JOIN #VLFCounts v ON d.database_id = v.database_id -- Now pointing to the staging table
    LEFT JOIN BackupMetrics b ON d.name = b.database_name

    WHERE d.name <> 'tempdb';


-- 6) Clean up when finished

    DROP TABLE #VLFCounts;
    DROP TABLE #CheckDBResults
    DROP TABLE #DBInfo

END
GO


