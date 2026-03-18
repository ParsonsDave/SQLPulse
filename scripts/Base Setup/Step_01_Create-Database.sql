/* ****************************************************************************************************

Source: SQL Pulse Core Installation: Database Installation
Build: 1.5
Build Date: 2026-03-18

This script creates the SQLPulse database and the [Pulse] schema. The database is created with a fixed 
initial size and growth settings to avoid issues with auto-growth during initial data collection activities.

It's no frills and uses the default paths to create the database and log files.

Note: If the default database paths have not been modified, this may end up with the database files
on something like C:, if the installation was done by accepting the default values in the 
wizard - this is extremely common, so a future feature might be to check the path(s) in 
use by the largest database and locate the SQLPulse files there instead, but at this time
I am not trying to be creative.

Note 2: The script will gleefully delete any existing database names [SQLPulse]; this is by design,
so I recommend you be really, REALLY sure you mean it before you execute this script.

This script performs the following activities:

   1) Create the SQPulse database; drop the existing database if it exists
   2) Be in the right spot
   3) Create the [Pulse] schema in the installation database

**************************************************************************************************** */

-- 1) Create the SQPulse database; drop the existing database if it exists

	-- Drop the database if it's there
	IF EXISTS (SELECT 1 FROM sys.databases WHERE name = 'SQLPulse')
	BEGIN
		ALTER DATABASE [SQLPulse] SET  SINGLE_USER WITH ROLLBACK IMMEDIATE;
		DROP DATABASE SQLPulse;
	END

	-- Declare variable to use for the creation
    DECLARE @DataPath   NVARCHAR(512),
        @LogPath    NVARCHAR(512),
        @DataFile   NVARCHAR(512),
        @LogFile    NVARCHAR(512),
        @SQL        NVARCHAR(MAX);

	-- Retrieve the instance default paths
	SELECT @DataPath = CAST(SERVERPROPERTY('InstanceDefaultDataPath') AS NVARCHAR(512));
	SELECT @LogPath  = CAST(SERVERPROPERTY('InstanceDefaultLogPath')  AS NVARCHAR(512));

	-- Ensure trailing backslash
	IF RIGHT(@DataPath, 1) <> '\' SET @DataPath = @DataPath + '\';
	IF RIGHT(@LogPath,  1) <> '\' SET @LogPath  = @LogPath  + '\';

	-- Build full file paths
	SET @DataFile = @DataPath + N'SQLPulse.mdf';
	SET @LogFile  = @LogPath  + N'SQLPulse_log.ldf';

	-- Build and execute the CREATE DATABASE statement
	SET @SQL = N'
	CREATE DATABASE [SQLPulse]
		CONTAINMENT = NONE
		ON PRIMARY
		(
			NAME        = N''SQLPulse'',
			FILENAME    = N''' + @DataFile + N''',
			SIZE        = 262144KB,
			MAXSIZE     = UNLIMITED,
			FILEGROWTH  = 131072KB
		)
		LOG ON
		(
			NAME        = N''SQLPulse_log'',
			FILENAME    = N''' + @LogFile + N''',
			SIZE        = 262144KB,
			MAXSIZE     = 2048GB,
			FILEGROWTH  = 131072KB
		);';

	EXEC sp_executesql @SQL;
	GO

	-- Set recovery model to SIMPLE
	ALTER DATABASE [SQLPulse] SET RECOVERY SIMPLE;
	GO


-- 2) Be in the right spot

	USE [SQLPulse]
	GO


-- 3) Create the [Pulse] schema in the installation database

	DECLARE @sql NVARCHAR(255)
    IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Pulse')
        BEGIN
            SET @sql = 'CREATE SCHEMA Pulse;';
            EXEC(@sql);
        END;

