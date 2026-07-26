USE [SQLPulse]
GO

/****** Object:  StoredProcedure [Pulse].[Module_GeneralHealth_System_MonthlyRollup]    Script Date: 7/25/2026 1:39:54 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO



CREATE PROCEDURE [Pulse].[Module_GeneralHealth_System_MonthlyRollup]
AS
BEGIN
    SET NOCOUNT ON;

/* *******************************************************************************************************************

Source: SQLPulse: GeneralHealth_System_MonthlyRollup
Build: 1.0
Build Date: 2026-07-25

This is one of the reporting routines for the CPU module of SqlPulse
This procedures fetches various system configuretion and instance settings for the monthly report/health check
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
   2) Execute the stored procedure Pulse.Module_Core_GetServerProperties
   3) Declare the internal variables
   4) Get OS Information
   5) Get Instance Information
   6) Get Instance Configuration Information
   7) Get version-specific values

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
   11) Insert the values into the table Pulse.GeneralHealth_System_MonthlyRollup

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
        FROM [Pulse].[GeneralHealth_System_MonthlyRollup]
        WHERE RollupMonth = @RollupMonth
        AND ServerName = @ServerName
        )
    BEGIN
        RETURN;
    END


-- 2) Execute the stored procedure Pulse.Module_Core_GetServerProperties

	EXEC [SQLPulse].[Pulse].[Module_Core_GetServerProperties]


-- 3) Declare the internal variables
	
	-- OS Information

		DECLARE @CPUCores int
		DECLARE @HostName nvarchar(50)
		DECLARE @HostPowerPlan nvarchar(50)
		DECLARE @HostRAM_MB int
		DECLARE @IsVirtualMachine bit
		DECLARE @NUMANodes int

	-- SQL Information

		DECLARE @InstanceCollation nvarchar(128)
		DECLARE @InstanceName nvarchar(128)
		DECLARE @IsNameMatching bit
		DECLARE @SQLEdition nvarchar(50)
		DECLARE @SQLFriendlyVersion nvarchar(100)
		DECLARE @SQLProductVersion nvarchar(20)	

	-- SQL Configuration

		DECLARE @AdHocEnabled bit
		DECLARE @BackupCompression bit
		DECLARE @CToP int				-- Cost threshold for parallelism
		DECLARE @IsAGEnabled bit
		DECLARE @IsAGPresent bit
		DECLARE @IsClustered bit
		DECLARE @LockPagesInMemory bit
		DECLARE @MAXDOP int
		DECLARE @SQLMaxRAM_MB int
		DECLARE @SQLMinRAM_MB int

	-- Version-specific data

		-- SQL 2014+
		
			DECLARE @PerformVolumeMaintenanceTasks bit --Requires SQL Server 2014+

		-- SQL 2016+

		-- SQL 2017+
		
			DECLARE @HostDistribution nvarchar(50) -- Requires SQL Server 2017+
			DECLARE @HostOperatingSystem nvarchar(20) -- Requires SQL Server 2017+

		-- SQL 2019+

		-- SQL 2022+

		-- SQL 2025+

/* ********************************************************************************************* */

-- 4) Get OS Information

	SET @CPUCores = (SELECT cpu_count FROM sys.dm_os_sys_info);
	SET @HostName = (SELECT PropertyValue from ##ServerProperties WHERE PropertyName = 'ServerName');
	
	SET @HostRAM_MB = (SELECT total_physical_memory_kb / 1024 FROM sys.dm_os_sys_memory);
	SET @IsVirtualMachine = (SELECT CASE virtual_machine_type_desc
								WHEN 'NONE' THEN 0
								ELSE 1
								END AS IsVirtualMachine
								FROM sys.dm_os_sys_info);
	
	
	
	/* **********************************************************

	This command can be used in SQL 2019 and above:

		SET @NUMANodes = (SELECT numa_node_count FROM sys.dm_os_sys_info)

	-- New code block for NUMA and CPU data ; replace the above line and declare the additional variables
	-- Unlike the above line, this will work with SQL 2012 and above, but with the expanded
	-- columns in in SQL 2019+ in sys.dm_os_sys_info, this is probably more suitable
	-- for the version blocks rather than right here. It may be better to have them in 
	-- a future version / update though

	WITH SchedulerData AS
	(
		SELECT 
			parent_node_id,
			status
		FROM sys.dm_os_schedulers
		WHERE parent_node_id < 64
	)

	SELECT
		COUNT(DISTINCT parent_node_id) AS NUMA_Node_Count,
		SUM(CASE WHEN status = 'VISIBLE ONLINE'  THEN 1 ELSE 0 END) AS Online_CPU_Count,
		SUM(CASE WHEN status = 'VISIBLE OFFLINE' THEN 1 ELSE 0 END) AS Offline_CPU_Count,
		SUM(CASE WHEN status IN ('VISIBLE ONLINE','VISIBLE OFFLINE') THEN 1 ELSE 0 END) AS Allocated_CPU_Count
	FROM SchedulerData;

	********************************************************** */

	WITH SchedulerData AS
	(
		SELECT 
			parent_node_id,
			status
		FROM sys.dm_os_schedulers
		WHERE parent_node_id < 64
	)

	SELECT @NUMANodes = (SELECT COUNT(DISTINCT parent_node_id) FROM SchedulerData);


	/* **********************************************************


	Time to get the OS power plan
	We're going to use a call to the agent job [SQLPulse - External Actions] and specify the [Module - Core - GetOSPowerPlan] step

	A brief history

		The original idea I had for this was creating a minimalist global temp table and update the one row.
		I changed this with the idea that I would track the server/instance configuration over time in otder to
		inform (possibly even alert) when the configuration changed. That psuedocode is preserved here:

				CREATE TABLE ##PowerPlanResult
				(
					ExecutionID UNIQUEIDENTIFIER NOT NULL,
					Status VARCHAR(20) NOT NULL DEFAULT 'Pending',
					RawOutput NVARCHAR(4000) NULL
				);

				DECLARE @ExecutionID UNIQUEIDENTIFIER = NEWID();

				INSERT INTO ##PowerPlanResult (ExecutionID) VALUES (@ExecutionID);

				EXEC msdb.dbo.sp_start_job @job_name = 'GetPowerPlan';

		I sat on this for over a month, stuck with some of the complexity plus burnout plus Windrose. Finally, I got my mind
		back down to 'it's version 1, keep it simple'; HOWEVER, I decided that the infrastructure for the future state
		should remain for the power plan, so this is much more complicated than it needs to be as a reminder to future me
		that this is the direction we're going to go. 

	********************************************************** */

		-- 1. Declare a variable to hold the ID of the row we are inserting
		DECLARE @InsertedID UNIQUEIDENTIFIER;

		-- 2. Create a table variable to capture the OUTPUT of the INSERT
		DECLARE @OutputTable TABLE (ExecutionID UNIQUEIDENTIFIER);

		-- 3. Insert the row and capture the generated ID
		INSERT INTO [Pulse].[Core_PowerPlanResults] (
			RequestedAt,
			Status
		)
		OUTPUT inserted.ExecutionID INTO @OutputTable
		VALUES (
			SYSUTCDATETIME(),
			'Pending'
		);

		-- Move the ID from the table variable to our scalar variable
		SELECT TOP 1 @InsertedID = ExecutionID FROM @OutputTable;

		-- 4. Start the SQL Agent Job
		EXEC msdb.dbo.sp_start_job @job_name = 'SQLPulse - External Actions', @step_name = N'Module - Core - GetPowerScheme';

		-- 5. Loop and wait until the status is no longer 'Pending'
		-- (We'll also add a safety timeout loop so it doesn't run forever if the script fails)
		DECLARE @Counter INT = 0;
		DECLARE @MaxChecks INT = 30; -- 30 checks * 2 seconds = 60 second max timeout

		WHILE EXISTS (
			SELECT 1 
			FROM [Pulse].[Core_PowerPlanResults] 
			WHERE [ExecutionID] = @InsertedID AND [Status] = 'Pending'
		) AND @Counter < @MaxChecks
		BEGIN
			WAITFOR DELAY '00:00:02'; -- Wait exactly 2 seconds
			SET @Counter = @Counter + 1;
		END

		-- Optional: Let you know if it timed out or succeeded
		IF @Counter >= @MaxChecks
		BEGIN
			RAISERROR('The PowerShell script for the power plan timed out before updating the status.', 16, 1);
		END

		-- Finally: Get the actual data point
		SET @HostPowerPlan = (SELECT SchemeName FROM [Pulse].[Core_PowerPlanResults] WHERE ExecutionID = @InsertedID);
		

-- 5) Get Instance Information

	SET @InstanceCollation = (SELECT PropertyValue FROM ##ServerProperties WHERE PropertyName = 'Collation')
	
	SET @InstanceName = (
		SELECT ISNULL(CAST(PropertyValue AS NVARCHAR(128)), 'MSSQLSERVER (Default Instance)')
		FROM ##ServerProperties 
		WHERE PropertyName = 'InstanceName'
	);

	-- Does the internal SQL name match the OS host name?

		DECLARE @ControlName SYSNAME = (SELECT PropertyValue from ##ServerProperties WHERE PropertyName = 'ServerName')
		DECLARE @TestName SYSNAME = (SELECT PropertyValue from ##ServerProperties WHERE PropertyName = 'InternalSQLName')

		IF @ControlName = @TestName
			SET @IsNameMatching = 1
		ELSE
				SET @IsNameMatching = 0

	SET @SQLEdition = (SELECT PropertyValue FROM ##ServerProperties WHERE PropertyName = 'Edition')
	SET @SQLFriendlyVersion = (SELECT LEFT(REPLACE(REPLACE(@@VERSION, CHAR(10), ' '), CHAR(13), ' '), CHARINDEX('-', REPLACE(REPLACE(@@VERSION, CHAR(10), ' '), CHAR(13), ' ')) - 1))
	SET @SQLProductVersion = (SELECT PropertyValue FROM ##ServerProperties WHERE PropertyName = 'ProductVersion')


/* ********************************************************************************************* */

-- 6) Get Instance Configuration Information

	SELECT 
		@AdHocEnabled      = MAX(CASE WHEN name = 'optimize for ad hoc workloads' THEN CAST(value AS int) END),
		@BackupCompression = MAX(CASE WHEN name = 'backup compression default'   THEN CAST(value AS int) END),
		@CToP              = MAX(CASE WHEN name = 'cost threshold for parallelism' THEN CAST(value AS int) END),
		@MAXDOP            = MAX(CASE WHEN name = 'max degree of parallelism' THEN CAST(value AS int) END),
		@SQLMinRAM_MB      = MAX(CASE WHEN name = 'min server memory (MB)' THEN CAST(value AS int) END),
		@SQLMaxRAM_MB      = MAX(CASE WHEN name = 'max server memory (MB)' THEN CAST(value AS int) END)
	FROM sys.configurations
	WHERE name IN ('optimize for ad hoc workloads', 'backup compression default', 'cost threshold for parallelism', 'max degree of parallelism', 'min server memory (MB)', 'max server memory (MB)');
	
	SET @IsAGEnabled = (SELECT PropertyValue FROM ##ServerProperties WHERE PropertyName = 'IsHadrEnabled')
	
	SET @IsAGPresent = 
		CASE 
			WHEN EXISTS (SELECT 1 FROM sys.availability_groups) 
			THEN 1 
			ELSE 0 
		END;

	SET @IsClustered = (SELECT PropertyValue FROM ##ServerProperties WHERE PropertyName = 'IsClustered')
	SET @LockPagesInMemory = 
		CASE
			WHEN ((SELECT locked_page_allocations_kb FROM sys.dm_os_process_memory) > 0)
			THEN 1
			ELSE 0
		END

	
/* ********************************************************************************************* */

-- 7) Get version-specific values

	DECLARE @MajorVersion int
	-- SET @MajorVersion = (SELECT PropertyValue FROM ##ServerProperties WHERE PropertyName = 'ProductMajorVersion')

	SET @MajorVersion = ISNULL(
    (SELECT PropertyValue FROM ##ServerProperties WHERE PropertyName = 'ProductMajorVersion'), 
    11
);

	-- SQL 2025+ (Major version 17+)
		IF @MajorVersion >= 17
		BEGIN
			SELECT 1
		END

	-- SQL 2022+ (Major version 16+)
		IF @MajorVersion >= 16
		BEGIN
			-- future variables here
			SELECT 1;
		END

	-- SQL 2019+ (Major version 15+)
		IF @MajorVersion >= 15
		BEGIN
			-- future variables here
			SELECT 1;
		END

	-- SQL 2017+ (Major version 14+)
		IF @MajorVersion >= 14
		BEGIN
			SET @HostDistribution   = (SELECT PropertyValue FROM ##ServerProperties WHERE PropertyName = 'HostDistribution');
			SET @HostOperatingSystem = (SELECT PropertyValue FROM ##ServerProperties WHERE PropertyName = 'HostOperatingSystem');
			
		-- Use dynamic SQL to hide the column name from the SQL 2012 compiler
		DECLARE @SQL NVARCHAR(MAX);
		SET @SQL = N'
			SELECT @Result = CASE WHEN EXISTS (
				SELECT 1
				FROM sys.dm_server_services
				WHERE servicename LIKE ''SQL Server (%''
				  AND instant_file_initialization_enabled = 1
			) THEN 1 ELSE 0 END;';

		EXEC sp_executesql 
			@SQL, 
			N'@Result bit OUTPUT', 
			@Result = @PerformVolumeMaintenanceTasks OUTPUT;
		END

	-- SQL 2016+ (Major version 13+)
		IF @MajorVersion >= 13
		BEGIN
			-- future variables here
			SELECT 1;
		END

	-- SQL 2014+ (Major version 12+)
		IF @MajorVersion >= 12
		BEGIN
			-- future variables here
			SELECT 1;
		END

	-- SQL 2012+ (Major version 11+)
		IF @MajorVersion >= 11
		BEGIN
			-- future variables here
			SELECT 1;
		END


/* *********************************************************************************************
	-- The big reveal - now that the data gathering runs without error, let's see if the data coming back is accurate
	-- This section commented out in the production sproc, but it's still here if you need to pull it out for manual execution
	
		SELECT 
			@RollupMonth AS RollupMonth
		 ,@ServerName AS ServerName
		 ,@CPUCores AS CPUCores
		 ,@HostName AS HostName
		 ,@HostPowerPlan HostPowerPlan
		 ,@HostRAM_MB AS HostRAM_MB
		 ,@IsVirtualMachine AS IsVirtualMachine
		 ,@NUMANodes AS NUMANodes

	-- SQL Information

		, @InstanceCollation AS InstanceCollation
		, @InstanceName AS InstanceName
		, @IsNameMatching AS IsNameMatching
		, @SQLEdition AS SQLEdition
		, @SQLFriendlyVersion AS SQLFriendlyVersion
		, @SQLProductVersion AS SQLProductVersion

	-- SQL Configuration

		, @AdHocEnabled AS AdHocEnabled
		, @BackupCompression AS BackupCompression
		, @CToP as CToP
		, @IsAGEnabled AS IsAGEnabled
		, @IsAGPresent AS IsAGPresent
		, @IsClustered AS IsClustered
		, @LockPagesInMemory AS LockPagesInMemory
		, @MAXDOP AS MAXDOP
		, @SQLMaxRAM_MB AS SQLMaxRAM_MB
		, @SQLMinRAM_MB AS SQLMinRAM_MB
		, @PerformVolumeMaintenanceTasks AS PerformVolumeMaintenanceTasks
		, @HostDistribution AS HostDistribution
		, @HostOperatingSystem AS HostOperatingSystem

********************************************************************************************* */


-- 8) Insert the values into the table Pulse.GeneralHealth_System_MonthlyRollup

	INSERT INTO [Pulse].[GeneralHealth_System_MonthlyRollup]
	(
		[RollupMonth]
		,[ServerName]
		,[CPUCores]
		,[HostName]
		,[HostPowerPlan]
		,[HostRAM_MB]
		,[IsVirtualMachine]
		,[NUMANodes]
		,[InstanceCollation]
		,[InstanceName]
		,[IsNameMatching]
		,[SQLEdition]
		,[SQLFriendlyVersion]
		,[SQLProductVersion]
		,[AdHocEnabled]
		,[BackupCompression]
		,[CToP]
		,[IsAGEnabled]
		,[IsAGPresent]
		,[IsClustered]
		,[LockPagesInMemory]
		,[MAXDOP]
		,[SQLMaxRAM_MB]
		,[SQLMinRAM_MB]
		,[PerformVolumeMaintenanceTasks]
		,[HostDistribution]
		,[HostOperatingSystem]
    )
    VALUES
    (
		@RollupMonth
		 ,@ServerName
		 ,@CPUCores
		 ,@HostName
		 ,@HostPowerPlan
		 ,@HostRAM_MB
		 ,@IsVirtualMachine
		 ,@NUMANodes

	-- SQL Information

		, @InstanceCollation
		, @InstanceName
		, @IsNameMatching
		, @SQLEdition
		, @SQLFriendlyVersion
		, @SQLProductVersion

	-- SQL Configuration

		, @AdHocEnabled
		, @BackupCompression
		, @CToP
		, @IsAGEnabled
		, @IsAGPresent
		, @IsClustered
		, @LockPagesInMemory
		, @MAXDOP
		, @SQLMaxRAM_MB
		, @SQLMinRAM_MB
		, @PerformVolumeMaintenanceTasks
		, @HostDistribution
		, @HostOperatingSystem
	)
		

END
GO


