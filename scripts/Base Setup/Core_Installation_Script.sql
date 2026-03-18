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
   2) Switch to the new database
   3) Create the [Pulse] schema in the installation database
   4) Create the core tables
   5) Create the stored procedure [Module_Core_GetReportDates]
   6) Create the stored procedure [Module_Core_ServerRestartDates]
   7) Create the SQL Agent job [SQLPulse - Core Processing]
   8) Create the SQL Agent job [SQLPulse - External Actions]

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


-- 2) Switch to the new database

	USE [SQLPulse]
	GO


-- 3) Create the [Pulse] schema in the installation database

	DECLARE @sql NVARCHAR(255)
    IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Pulse')
        BEGIN
            SET @sql = 'CREATE SCHEMA Pulse;';
            EXEC(@sql);
        END;


-- 4) Create the core tables

	-- The [Parameters] table holds various lookup vaules for the project
		CREATE TABLE [Pulse].[Core_Parameters](
			[ID] [int] IDENTITY(1,1) NOT NULL,
			[ParameterName] [nvarchar](50) NULL,
			[ParameterValue] [nvarchar](50) NULL,
			[ParameterNumber] [decimal](18, 2) NULL,
			[ParameterDescription] [nvarchar](255) NULL,
		CONSTRAINT [PK_Parameters] PRIMARY KEY CLUSTERED 
		(
			[ID] ASC
		)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
		) ON [PRIMARY]
		GO

	-- The [Modules] table tracks the installed features
		CREATE TABLE [Pulse].[Core_Modules](
			[ID] [int] IDENTITY(1,1) NOT NULL,
			[ModuleName] [nvarchar](50) NOT NULL,
			[ModuleVersion] [decimal](5, 3) NULL,
			[ModuleDescription] [nvarchar](255) NULL,
			[IsEnabled] [bit] NOT NULL,
			[CreatedDate] [datetime2](7) NOT NULL,
			[ModifiedDate] [datetime2](7) NULL,
		PRIMARY KEY CLUSTERED 
		(
			[ID] ASC
		)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY],
		 CONSTRAINT [UQ_Modules_ModuleName] UNIQUE NONCLUSTERED 
		(
			[ModuleName] ASC
		)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
		) ON [PRIMARY]
		GO

		ALTER TABLE [Pulse].[Core_Modules] ADD  DEFAULT ((1)) FOR [IsEnabled]
		GO

		ALTER TABLE [Pulse].[Core_Modules] ADD  DEFAULT (sysutcdatetime()) FOR [CreatedDate]
		GO

	-- The [ModuleActions] table ennumerates the actions available to each Module listed in the [Modules] table
		CREATE TABLE [Pulse].[Core_ModuleActions](
			[ID] [int] IDENTITY(1,1) NOT NULL,
			[ModuleID] [int] NOT NULL,
			[ActionType] [nvarchar](50) NOT NULL,
			[SprocName] [nvarchar](50) NOT NULL,
			[IsEnabled] [bit] NOT NULL,
			[ExecutionOrder] [int] NULL,
			[ActionDescription] [nvarchar](255) NULL,
			[CreatedDate] [datetime2](7) NOT NULL,
			[ModifiedDate] [datetime2](7) NULL,
		PRIMARY KEY CLUSTERED 
		(
			[ID] ASC
		)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
		) ON [PRIMARY]
		GO

		ALTER TABLE [Pulse].[Core_ModuleActions] ADD  DEFAULT ((1)) FOR [IsEnabled]
		GO

		ALTER TABLE [Pulse].[Core_ModuleActions] ADD  DEFAULT (sysutcdatetime()) FOR [CreatedDate]
		GO

		ALTER TABLE [Pulse].[Core_ModuleActions]  WITH CHECK ADD  CONSTRAINT [FK_Core_ModuleActions_Core_Modules] FOREIGN KEY([ModuleID])
		REFERENCES [Pulse].[Core_Modules] ([ID])
		GO

		ALTER TABLE [Pulse].[Core_ModuleActions] CHECK CONSTRAINT [FK_Core_ModuleActions_Core_Modules]
		GO

		CREATE INDEX IX_Core_ModuleActions_ModuleID ON Pulse.Core_ModuleActions(ModuleID);


	-- The [ModuleExecution] table stores execution results of actions ennumerated in the [ModuleActions] table
		CREATE TABLE [Pulse].[Core_ModuleExecutionLog](
			[ID] [int] IDENTITY(1,1) NOT NULL,
			[ModuleID] [int] NULL,
			[ActionType] [nvarchar](50) NOT NULL,
			[SprocName] [nvarchar](128) NOT NULL,
			[ExecutionTime] [datetime2](7) NOT NULL,
			[Success] [bit] NOT NULL,
			[ErrorMessage] [nvarchar](4000) NULL,
			[RowsAffected] [int] NULL,
			[AdditionalInfo] [nvarchar](4000) NULL,
		PRIMARY KEY CLUSTERED 
		(
			[ID] ASC
		)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
		) ON [PRIMARY]
		GO

		ALTER TABLE [Pulse].[Core_ModuleExecutionLog] ADD  DEFAULT (sysutcdatetime()) FOR [ExecutionTime]
		GO


-- 5) Create the stored procedure [Module_Core_GetReportDates]

		CREATE PROCEDURE [Pulse].[Module_Core_GetReportDates] 
			(@StartofMonth date OUTPUT, @EndofMonth date OUTPUT, @TotalMinutes int OUTPUT)
	
		AS
		BEGIN

		/* ****************************************************************************************************

		Source: SQL Pulse Core Module Stored Procedure: Get Report Dates
		Build: 2.2
		Build Date: 2026-02-26

		Note: This stored procedure has never actually been used, but it's elegant enough that I'm retaining it for potential future use.

		The purpose of this stored procedure is to return the following values:
			1) Start of month (ex: 2025-01-01)
			2) End of Month (ex: 2025-01-31)
			3) How many minutes were in the month (ex: 44640)

		This is because all reporting is done at the start of one month for the previous month;
		additionally, different metrics are gathered at different intervals, but all are minute-based

		This centralizes dates out of the reporting procedures and will allow the input of custom values for reporting months, if desired 

		It performs the following activities:

		   1) Set NOCOUNT ON to prevent extra result sets from interfering with SELECT statements
		   2) Declare the internal variables and values
		   3) Calculate the outputs
   
		**************************************************************************************************** */

			-- 1) Set NOCOUNT ON to prevent extra result sets from interfering with SELECT statements
			
				SET NOCOUNT ON;
		
			-- 2) Declare the internal variables and values
			
				-- This section intentionally blank for future expansion
		
			-- 3) Calculate the output
		
				-- Step 1: Calculate the last day of the previous month (EndofMonth)
					SET @EndofMonth = DATEADD(day, -1, DATEADD(month, DATEDIFF(month, 0, GetDate()), 0));
			
				-- Step 2: Calculate the first day of the previous month (StartofMonth)
					SET @StartofMonth = DATEADD(month, DATEDIFF(month, 0, @EndofMonth), 0);
			
				-- Step 3: Calculate the total minutes in the period 
					SET @TotalMinutes = DATEDIFF(MINUTE, @StartofMonth, DATEADD(day, 1, @EndofMonth));
		

		END
		GO


-- 6) Create the stored procedure [Module_Core_ServerRestartDates]

		CREATE PROCEDURE [Pulse].[Module_Core_ServerRestartDates]
	
		AS

		BEGIN

		/* *********************************************************************************

		Source: SQL Pulse: Update [Pulse].[Core_ServerRestartDates]
		Build: 1.3
		Build Date: 2026-03-08

		This sproc is called by every other stored procedure on execution for the purposes of coordinating data gathering,
		eliminating duplicates, and general bookkeeping. 

		The code could definitely be tighter and more efficient; it is structured this way in the interests of being as human-readable as possible

		This sproc performs the following activities:

		   1) Declare the internal variables
		   2) Set the variables for processing
		   3) Insert values into [Pulse].[Core_ServerRestartDates] with duplicate checking
   
		********************************************************************************* */

		-- 1) Declare internal variables

			DECLARE @SystemThreadLogin datetime
			DECLARE @RunDate datetime
	

		-- 2) Set the values for processing

			--SET @SystemThreadLogin = CAST((SELECT sqlserver_start_time FROM sys.dm_os_sys_info) as smalldatetime)

			SELECT @SystemThreadLogin = CAST(
				DATEADD(second, DATEDIFF(second, GETDATE(), GETUTCDATE()), sqlserver_start_time) 
				AS smalldatetime)
				FROM sys.dm_os_sys_info

			--SELECT @SystemThreadLogin

			SET @RunDate = CAST(SYSUTCDATETIME() as smalldatetime)


		-- 3) Insert values into [Pulse].[Module_Core_ServerRestartDates] with duplicate checking

			IF NOT EXISTS (SELECT 1 FROM [Pulse].[Core_ServerRestartDates] WHERE RestartDate = @SystemThreadLogin)
				INSERT INTO [Pulse].[Core_ServerRestartDates] (RestartDate, RunDate) VALUES (@SystemThreadLogin, @RunDate)


		END
		GO


-- 7) Create the SQL Agent job [SQLPulse - Core Processing]

		USE [msdb]
		GO

		BEGIN TRANSACTION
		DECLARE @ReturnCode INT
		SELECT @ReturnCode = 0

		IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'Data Collector' AND category_class=1)
		BEGIN
		EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'Data Collector'
		IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

		END

		DECLARE @jobId BINARY(16)
		EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'SQLPulse - Core Processing', 
				@enabled=1, 
				@notify_level_eventlog=0, 
				@notify_level_email=0, 
				@notify_level_netsend=0, 
				@notify_level_page=0, 
				@delete_level=0, 
				@description=N'No description available.', 
				@category_name=N'Data Collector', 
				@owner_login_name=N'sa', @job_id = @jobId OUTPUT
		IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

		EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Module Actions: Data Collection', 
				@step_id=1, 
				@cmdexec_success_code=0, 
				@on_success_action=1, 
				@on_success_step_id=0, 
				@on_fail_action=2, 
				@on_fail_step_id=0, 
				@retry_attempts=0, 
				@retry_interval=0, 
				@os_run_priority=0, @subsystem=N'TSQL', 
				@command=N'SET NOCOUNT ON;

		DECLARE @SchemaName sysname;
		DECLARE @SprocName sysname;
		DECLARE @SQL nvarchar(4000);

		-- Temp table to hold the list of monitor actions
		CREATE TABLE #MonitorActions
		(
			ID int IDENTITY(1,1),
			SchemaName sysname,
			SprocName sysname
		);

		INSERT INTO #MonitorActions (SchemaName, SprocName)
		SELECT SchemaName, SprocName
		FROM Pulse.Core_ModuleActions
		--WHERE ActionType = ''CollectData''
		--  AND IsEnabled = 1
		WHERE IsEnabled = 1
		ORDER BY ExecutionOrder, ID;

		DECLARE @MaxID int = (SELECT MAX(ID) FROM #MonitorActions);
		DECLARE @CurrentID int = 1;

		WHILE @CurrentID <= @MaxID
		BEGIN
			SELECT
			 @SchemaName = SchemaName,
			 @SprocName = SprocName
			FROM #MonitorActions
			WHERE ID = @CurrentID;

			BEGIN TRY
				SET @SQL = N''EXEC '' + QUOTENAME(@SchemaName) + ''.'' + QUOTENAME(@SprocName) + '';'';
				EXEC (@SQL);

				-- Optional: log success
				INSERT INTO Pulse.Core_ModuleExecutionLog
				(
					ActionType,
					SprocName,
					ExecutionTime,
					Success,
					ErrorMessage
				)
				VALUES
				(
					''Monitor'',
					@SprocName,
					SYSUTCDATETIME(),
					1,
					NULL
				);
			END TRY
			BEGIN CATCH
				-- Log failure but continue to next module
				INSERT INTO Pulse.Core_ModuleExecutionLog
				(
					ActionType,
					SprocName,
					ExecutionTime,
					Success,
					ErrorMessage
				)
				VALUES
				(
					''Monitor'',
					@SprocName,
					SYSUTCDATETIME(),
					0,
					ERROR_MESSAGE()
				);
			END CATCH;

			SET @CurrentID += 1;
		END;', 
				@database_name=N'SQLPulse', 
				@flags=0
		IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
		EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
		IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
		EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'Every_5_Minutes', 
				@enabled=1, 
				@freq_type=4, 
				@freq_interval=1, 
				@freq_subday_type=4, 
				@freq_subday_interval=5, 
				@freq_relative_interval=0, 
				@freq_recurrence_factor=0, 
				@active_start_date=20260110, 
				@active_end_date=99991231, 
				@active_start_time=0, 
				@active_end_time=235959, 
				@schedule_uid=N'b597fd25-25f4-43da-98e4-10660c1a299c'
		IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
		EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
		IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
		COMMIT TRANSACTION
		GOTO EndSave
		QuitWithRollback:
			IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
		EndSave:
		GO


-- 8) Create the SQL Agent job [SQLPulse - External Actions]

		/* ****************************************************************************************************

		Source: SQL Pulse Core Module: Create External Actions Agent Job
		Build: 1.1
		Build Date: 2026-02-26

		This script creates the SQL Agent job [SQLPulse - External Actions]; this job handles
		various activities that cannot or should not be done in a normal stored procedure.

		The Actions are separated into job steps, with each action being administratively 
		contained by logic that causes a step to exit after execution rather than proceeding
		to the next step. 

		>>> NOTE!!!! At release, this code needs to be parameterized to accomodate custom database installation

		**************************************************************************************************** */

		USE [msdb]
		GO


		BEGIN TRANSACTION
		DECLARE @ReturnCode2 INT
		SELECT @ReturnCode2 = 0

		IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'[Uncategorized (Local)]' AND category_class=1)
		BEGIN
		EXEC @ReturnCode2 = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'[Uncategorized (Local)]'
		IF (@@ERROR <> 0 OR @ReturnCode2 <> 0) GOTO QuitWithRollback2

		END

		DECLARE @jobId2 BINARY(16)
		EXEC @ReturnCode2 =  msdb.dbo.sp_add_job @job_name=N'SQLPulse - External Actions', 
				@enabled=1, 
				@notify_level_eventlog=0, 
				@notify_level_email=0, 
				@notify_level_netsend=0, 
				@notify_level_page=0, 
				@delete_level=0, 
				@description=N'No description available.', 
				@category_name=N'[Uncategorized (Local)]', 
				@owner_login_name=N'sa', @job_id = @jobId2 OUTPUT
		IF (@@ERROR <> 0 OR @ReturnCode2 <> 0) GOTO QuitWithRollback2

		EXEC @ReturnCode2 = msdb.dbo.sp_add_jobstep @job_id=@jobId2, @step_name=N'Module - Disk - CollectInformation', 
				@step_id=1, 
				@cmdexec_success_code=0, 
				@on_success_action=1, 
				@on_success_step_id=0, 
				@on_fail_action=2, 
				@on_fail_step_id=0, 
				@retry_attempts=0, 
				@retry_interval=0, 
				@os_run_priority=0, @subsystem=N'PowerShell', 
				@command=N'# CONFIGURATION SECTION
		$serverName   = "localhost"
		$databaseName = "SQLPulse"
		$tableName    = "[Pulse].[Disk_Information]"
		$eventTimeUTC = (Get-Date).ToUniversalTime()
		$eventTimeLocal = (Get-Date)


		# SQL Connection Setup
		$connectionString = "Server=$serverName;Database=$databaseName;Integrated Security=True;"
		$sqlConnection = New-Object System.Data.SqlClient.SqlConnection
		$sqlConnection.ConnectionString = $connectionString
		$sqlConnection.Open()

		# Function to translate DriveType integer to string
		function Get-DriveTypeName($type) {
			switch ($type) {
				0 { "Unknown" }
				1 { "No Root Directory" }
				2 { "Removable Disk" }
				3 { "Local Disk" }
				4 { "Network Drive" }
				5 { "CD-ROM" }
				6 { "RAM Disk" }
				default { "Other" }
			}
		}

		# Use Get-WmiObject instead of Get-CimInstance for compatibility
		$volumes = Get-WmiObject Win32_Volume | Where-Object {
			($_.DriveType -ge 2 -and $_.DriveType -le 6) -and
			$_.FileSystem -ne $null -and
			$_.Label -ne "Recovery" -and
			($_.DriveLetter -or $_.Name -match "^.:\\")
		}

		foreach ($volume in $volumes) {
			$mountPath   = $volume.Name.TrimEnd(''\'')
			$label       = $volume.Label
			$sizeKB      = [math]::Round($volume.Capacity / 1KB)
			$freeKB      = [math]::Round($volume.FreeSpace / 1KB)
			$usedKB      = $sizeKB - $freeKB
			$percentFree = if ($sizeKB -ne 0) { [math]::Round(($freeKB / $sizeKB) * 100, 2) } else { 0 }
			$percentUsed = 100 - $percentFree
			$driveType   = Get-DriveTypeName $volume.DriveType
			$isMountPoint   = if ($volume.DriveLetter) { 0 } else { 1 }

			# Escape single quotes in SQL strings
			$mountPathSql = $mountPath -replace "''", "''''"
			$labelSql     = $label -replace "''", "''''"
			$driveTypeSql = $driveType -replace "''", "''''"

			# Build SQL Insert
			$insertCmd = $sqlConnection.CreateCommand()
			$insertCmd.CommandText = @"
		INSERT INTO $tableName (
			EventTimeUTC,
			EventTimeLocal,
			DriveLetterOrMountPath,
			Label,
			SizeKB,
			FreeSpaceKB,
			UsedSpaceKB,
			PercentFree,
			PercentUsed,
			DriveType,
			IsMountPoint
		) VALUES (
			''$eventTimeUTC'',
			''$eventTimeLocal'',
			''$mountPathSql'',
			''$labelSql'',
			$sizeKB,
			$freeKB,
			$usedKB,
			$percentFree,
			$percentUsed,
			''$driveTypeSql'',
			$isMountPoint
		);
		"@

			# Execute Insert
			$insertCmd.ExecuteNonQuery() | Out-Null
		}

		# Cleanup
		$sqlConnection.Close()', 
				@database_name=N'master', 
				@flags=0
		IF (@@ERROR <> 0 OR @ReturnCode2 <> 0) GOTO QuitWithRollback2
		EXEC @ReturnCode2 = msdb.dbo.sp_update_job @job_id = @jobId2, @start_step_id = 1
		IF (@@ERROR <> 0 OR @ReturnCode2 <> 0) GOTO QuitWithRollback2
		EXEC @ReturnCode2 = msdb.dbo.sp_add_jobserver @job_id = @jobId2, @server_name = N'(local)'
		IF (@@ERROR <> 0 OR @ReturnCode2 <> 0) GOTO QuitWithRollback2
		COMMIT TRANSACTION
		GOTO EndSave2
		QuitWithRollback2:
			IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
		EndSave2:

		------------------------------------------------------------------------------------------------------------------------------
		-- Update the new job to replace [localhost] with the actual SQL servername
		-- The job step is named the same in either case
		------------------------------------------------------------------------------------------------------------------------------

		DECLARE @jobName SYSNAME = N'SQLPulse - External Actions';
		DECLARE @stepName SYSNAME = N'Module - Disk - CollectInformation';
		DECLARE @serverName NVARCHAR(128);
		DECLARE @stepCommand NVARCHAR(MAX);
		DECLARE @stepId INT;

		-- Get the actual server name
		SELECT @serverName = CAST(SERVERPROPERTY('ServerName') AS NVARCHAR(128));

		-- Get the job ID and step ID
		SELECT 
			@jobId2 = job_id
		FROM msdb.dbo.sysjobs
		WHERE name = @jobName;

		SELECT 
			@stepId = step_id,
			@stepCommand = command
		FROM msdb.dbo.sysjobsteps
		WHERE job_id = @jobId2
		  AND step_name = @stepName;

		-- Replace "localhost" with actual server name
		SET @stepCommand = REPLACE(@stepCommand, '"localhost"', '"' + @serverName + '"');

		-- Update the job step with the new command
		EXEC msdb.dbo.sp_update_jobstep
			@job_id = @jobId2,
			@step_id = @stepId,
			@command = @stepCommand;
