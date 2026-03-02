/* ****************************************************************************************************

Source: SQL Pulse: Create Disk Latency Table
Build: 2.0
Build Date: 2025-11-29

The purpose of this script is to create the table that tracks the disk latency data. 

**************************************************************************************************** */

USE [SQLPulse]
GO

-- Insert values into the Modules table

	INSERT INTO Pulse.Modules (ModuleName, ModuleVersion, ModuleDescription, IsEnabled)
	VALUES 
		('Disk', 2.1, 'Monitors Disk Usage, Size, and Performance', 1)

-- Insert values into the ModuleActions table to cover what the module can do

	INSERT INTO Pulse.ModuleActions (ModuleID, ActionType, SchemaName, SprocName, IsEnabled, ExecutionOrder, ActionDescription)
	VALUES 
		((SELECT ID FROM Pulse.Modules WHERE ModuleName = 'Disk'), 'CollectData', 'Pulse', 'Module_Disk_CollectLatency', 1, 1, 'Collects Disk Latency data from the OS (cannot instance-isolate)')

	INSERT INTO Pulse.ModuleActions (ModuleID, ActionType, SchemaName, SprocName, IsEnabled, ExecutionOrder, ActionDescription)
	VALUES 
		((SELECT ID FROM Pulse.Modules WHERE ModuleName = 'Disk'), 'CollectData', 'Pulse', 'Module_Disk_CollectInformation', 1, 2, 'Collects Disk Size data from OS (cannot instance-isolate)')

	INSERT INTO Pulse.ModuleActions (ModuleID, ActionType, SchemaName, SprocName, IsEnabled, ExecutionOrder, ActionDescription)
	VALUES 
		((SELECT ID FROM Pulse.Modules WHERE ModuleName = 'Disk'), 'Rollup', 'Pulse', 'Module_Disk_MonthlyRollup', 1, 3, 'Performs the Monthly Rollup calculations for the Disk module')


-- Create the table to hold disk latency data

CREATE TABLE [Pulse].[Disk_Latency](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[EventTimeUTC] [datetime2](3) NOT NULL,
	[EventTimeLocal] [datetime2](3) NOT NULL,
	[ReadLatency] [int] NULL,
	[WriteLatency] [int] NULL,
	[AvgLatency] [int] NULL,
	[AvgKBsPerTransfer] [int] NULL,
	[Drive] [nvarchar](10) NULL,
	[DatabaseName] [nvarchar](255) NULL,
	[PhysicalName] [nvarchar](900) NULL
) ON [PRIMARY]
	GO

-- Create the table to hold disk size data

CREATE TABLE [Pulse].[Disk_Information](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[EventTimeUTC] [datetime2](3) NOT NULL,
	[EventTimeLocal] [datetime2](3) NOT NULL,
	[DriveLetterOrMountPath] [nvarchar](255) NULL,
	[Label] [nvarchar](255) NULL,
	[SizeKB] [bigint] NULL,
	[FreeSpaceKB] [bigint] NULL,
	[UsedSpaceKB] [bigint] NULL,
	[PercentFree] [decimal](5, 2) NULL,
	[PercentUsed] [decimal](5, 2) NULL,
	[DriveType] [nvarchar](50) NULL,
	[IsMountPoint] [bit] NULL,
PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO

-- Create the table for the monthly rollup data

CREATE TABLE [Pulse].[Disk_MonthlyRollup]
(
    -- Identity & Time
    RollupID            INT IDENTITY(1,1) NOT NULL,
    RollupMonth         DATE NOT NULL,   -- e.g., 2025-01-01 for January rollup
    RollupType          VARCHAR(20) NOT NULL,  -- 'Drive' or 'DatabaseFile'
    ServerName          SYSNAME NOT NULL,

    ------------------------------------------------------------
    -- Drive-Level Identity (NULL for DatabaseFile rows)
    ------------------------------------------------------------
    DriveLetterOrMountPath   NVARCHAR(255) NULL,
    DriveLabel               NVARCHAR(255) NULL,
    DriveType                NVARCHAR(50) NULL,
    IsMountPoint             BIT NULL,
    IsSqlDisk                BIT NULL,

    ------------------------------------------------------------
    -- Database File Identity (NULL for Drive rows)
    ------------------------------------------------------------
    DatabaseName        NVARCHAR(255) NULL,
    PhysicalName        NVARCHAR(2000) NULL,
    FileType            VARCHAR(20) NULL,   -- 'Data' or 'Log'
    FileDrive           NVARCHAR(10) NULL,  -- extracted from PhysicalName

    ------------------------------------------------------------
    -- Space & Capacity (Drive-level)
    ------------------------------------------------------------
    TotalSizeKB         BIGINT NULL,
    FreeSpaceKB         BIGINT NULL,
    UsedSpaceKB         BIGINT NULL,
    RollupFreeSpaceKB   BIGINT NULL,
    PercentFree         DECIMAL(5,2) NULL,
    PercentUsed         DECIMAL(5,2) NULL,
    RollupPercentFree   DECIMAL(5,2) NULL,


    -- Growth (Drive-level)
    AbsoluteGrowthKB    BIGINT NULL,
    PercentGrowth       DECIMAL(10,4) NULL,
    DaysAtCriticalFree  INT NULL,
    MaxUsedSpaceKB      BIGINT NULL,
    MinFreeSpaceKB      BIGINT NULL,

    ------------------------------------------------------------
    -- Latency (Drive-level or File-level)
    ------------------------------------------------------------
    AvgReadLatency_ms       INT NULL,
    AvgWriteLatency_ms      INT NULL,
    AvgOverallLatency_ms    INT NULL,
    WorstObservedLatency_ms INT NULL,

    ------------------------------------------------------------
    -- File Size & Growth (DatabaseFile-level)
    ------------------------------------------------------------
    FileSizeKB          BIGINT NULL,
    FileGrowthKB        BIGINT NULL,

    ------------------------------------------------------------
    -- Report-Time Database Health (DatabaseFile-level)
    ------------------------------------------------------------
    VLFCount            INT NULL,
    VLFSeverity         VARCHAR(20) NULL,  -- 'Normal', 'Warning', 'Critical'
    DataFileCount       INT NULL,
    LogFileCount        INT NULL,
    TotalDatabaseSizeKB BIGINT NULL,
    TotalDatabaseGrowthKB BIGINT NULL,

    ------------------------------------------------------------
    -- Metadata
    ------------------------------------------------------------
    GeneratedUTC          DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    GeneratedLocal        DATETIME2(3) NOT NULL DEFAULT SYSDATETIME(),

    CONSTRAINT PK_Disk_MonthlyRollup PRIMARY KEY CLUSTERED (RollupID)
);
GO