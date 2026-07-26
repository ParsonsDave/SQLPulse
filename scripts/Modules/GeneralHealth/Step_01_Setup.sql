USE [SQLPulse]
GO

-- Insert values into the Modules table

	INSERT INTO Pulse.Modules (ModuleName, ModuleVersion, ModuleDescription, IsEnabled)
	VALUES 
		('GeneralHealth', 1.0, 'Collects General Information, including configuration, settings, and incidentals, on the host, instance, and databases', 1)

-- Insert values into the ModuleActions table to cover what the module can do

	INSERT INTO Pulse.ModuleActions (ModuleID, ActionType, SchemaName, SprocName, IsEnabled, ExecutionOrder, ActionDescription)
	VALUES 
		((SELECT ID FROM Pulse.Modules WHERE ModuleName = 'GeneralHealth'), 'Rollup', 'Pulse', 'Module_GeneralHealth_System_MonthlyRollup', 1, 3, 'Gathers monthly rollup information on the host and instance')

	INSERT INTO Pulse.ModuleActions (ModuleID, ActionType, SchemaName, SprocName, IsEnabled, ExecutionOrder, ActionDescription)
	VALUES 
		((SELECT ID FROM Pulse.Modules WHERE ModuleName = 'GeneralHealth'), 'Rollup', 'Pulse', 'Module_GeneralHealth_Database_MonthlyRollup', 1, 3, 'Gathers monthly rollup information on the instance databases')



-- Create the rollup table for the system & instance information

    USE [SQLPulse]
    GO

    SET ANSI_NULLS ON
    GO

    SET QUOTED_IDENTIFIER ON
    GO

    CREATE TABLE [Pulse].[GeneralHealth_System_MonthlyRollup](
        [RollupMonth] [date] NOT NULL,
        [ServerName] [sysname] NOT NULL,
        [CPUCores] [int] NULL,
        [HostName] [sysname] NULL,
        [HostPowerPlan] [nvarchar](50) NULL,
        [HostRAM_MB] [int] NULL,
        [IsVirtualMachine] [bit] NULL,
        [NUMANodes] [int] NULL,
        [InstanceCollation] [nvarchar](128) NULL,
        [InstanceName] [sysname] NULL,
        [IsNameMatching] [bit] NULL,
        [SQLEdition] [nvarchar] (50) NULL,
        [SQLFriendlyVersion] [nvarchar](100) NULL,
        [SQLProductVersion] [nvarchar](20) NULL,
        [AdHocEnabled] [bit] NULL,
        [BackupCompression] [bit] NULL,
        [CToP] [int] NULL,
        [IsAGEnabled] [bit] NULL,
        [IsAGPresent] [bit] NULL,
        [IsClustered] [bit] NULL,
        [LockPagesInMemory] [bit] NULL,
        [MAXDOP] [int] NULL,
        [SQLMaxRAM_MB] [int] NULL,
        [SQLMinRAM_MB] [int] NULL,
        [PerformVolumeMaintenanceTasks] [bit] NULL,
        [HostDistribution] [nvarchar](50) NULL,
        [HostOperatingSystem] [nvarchar](20) NULL
        ,
    CONSTRAINT [PK_GeneralHealth_System_MonthlyRollup] PRIMARY KEY CLUSTERED 
    (
        [RollupMonth] ASC,
        [ServerName] ASC
    )WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
    ) ON [PRIMARY]
GO

-- Create the monthly rollup table for database information

CREATE TABLE [Pulse].[GeneralHealth_Database_MonthlyRollup](
	[RollupMonth] [date] NOT NULL,
	[ServerName] [sysname] NOT NULL,
	[DatabaseName] [sysname] NOT NULL,
	[RecoveryModel] [nvarchar](60) NOT NULL,
	[IsPageVerificationNotChecksum] [bit] NOT NULL,
	[HasHighVLFCount] [bit] NOT NULL,
	[VLFCount] [int] NOT NULL,
	[HasPercentAutogrowth] [bit] NOT NULL,
	[IsBackupOverdue] [bit] NOT NULL,
	[LastFullBackupDate] [datetime] NULL,
	[IsLogBackupOverdue] [bit] NOT NULL,
	[LastLogBackupDate] [datetime] NULL,
	[HasFilesOnCDisk] [bit] NOT NULL,
	[IsAutoShrinkOn] [bit] NOT NULL,
	[IsAutoCloseOn] [bit] NOT NULL,
	[LastGoodCheckDB] [datetime] NULL,
 CONSTRAINT [PK_GeneralHealth_Database_MonthlyRollup] PRIMARY KEY CLUSTERED 
(
	[RollupMonth] ASC,
	[ServerName] ASC,
	[DatabaseName] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO


