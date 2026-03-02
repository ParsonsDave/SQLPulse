USE [SQLPulse]
GO

-- Insert values into the Modules table

	INSERT INTO Pulse.Modules (ModuleName, ModuleVersion, ModuleDescription, IsEnabled)
	VALUES 
		('Waits', 1.0, 'Monitors SQL Wait Statistics', 1)

-- Insert values into the ModuleActions table to cover what the module can do

	INSERT INTO Pulse.ModuleActions (ModuleID, ActionType, SchemaName, SprocName, IsEnabled, ExecutionOrder, ActionDescription)
	VALUES 
		((SELECT ID FROM Pulse.Modules WHERE ModuleName = 'Waits'), 'CollectData', 'Pulse', 'Module_Waits_CollectData', 1, 1, 'Collects Wait data from the SQL Server instance')

	INSERT INTO Pulse.ModuleActions (ModuleID, ActionType, SchemaName, SprocName, IsEnabled, ExecutionOrder, ActionDescription)
	VALUES 
		((SELECT ID FROM Pulse.Modules WHERE ModuleName = 'Waits'), 'Rollup', 'Pulse', 'Module_Waits_MonthlyRollup', 1, 3, 'Performs the Monthly Rollup calculations for the Waits module')


-- Waits Archive Table

	CREATE TABLE [Pulse].[Waits_StatsArchive](
	[EventTimeUTC] [datetime2](3) NULL,
	[EventTimeLocal] [datetime2](3) NULL,
	[TotalServerTimeSeconds] [float] NULL,
	[WaitType] [nvarchar](60) NULL,
	[Category] [nvarchar](20) NULL,
	[WaitSeconds] [decimal](14, 2) NULL,
	[ResourceSeconds] [decimal](14, 2) NULL,
	[SignalSeconds] [decimal](14, 2) NULL,
	[TotalWaitPct] [decimal](5, 2) NULL,
	[WaitingTasksCount] [bigint] NULL
) ON [PRIMARY]

-- StatsByMonth Table

CREATE TABLE [Pulse].[Waits_StatsByMonth](
	[ID] [bigint] IDENTITY(1,1) NOT NULL,
	[SnapshotDateUTC] [datetime2](3) NOT NULL,
	[SnapshotDateLocal] [datetime2](3) NOT NULL,
	[SnapshotType] [varchar](20) NOT NULL,
	[ServerName] [sysname] NOT NULL,
	[RollupMonth] [date] NOT NULL,
	[TotalServerTimeSeconds] [float] NULL,
	[WaitType] [nvarchar](60) NOT NULL,
	[Category] [nvarchar](20) NOT NULL,
	[WaitSeconds] [decimal](14, 2) NOT NULL,
	[ResourceSeconds] [decimal](14, 2) NOT NULL,
	[SignalSeconds] [decimal](14, 2) NOT NULL,
	[TotalWaitPct] [decimal](5, 2) NOT NULL,
	[WaitingTasksCount] [bigint] NOT NULL,
 CONSTRAINT [PK_Waits_StatsByMonth] PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO

ALTER TABLE [Pulse].[Waits_StatsByMonth]  WITH CHECK ADD  CONSTRAINT [CK_Waits_StatsByMonth_SnapshotType] CHECK  (([SnapshotType]='PostRestart' OR [SnapshotType]='PreRestart' OR [SnapshotType]='EndOfMonth' OR [SnapshotType]='StartOfMonth'))
GO

ALTER TABLE [Pulse].[Waits_StatsByMonth] CHECK CONSTRAINT [CK_Waits_StatsByMonth_SnapshotType]
GO

-- Rollup Table

CREATE TABLE [Pulse].[Waits_MonthlyRollup](
	[RollupMonth] [date] NOT NULL,
	[ServerName] [sysname] NOT NULL,
	[TotalWaitSeconds] [decimal](18, 2) NULL,
	[TotalResourceSeconds] [decimal](18, 2) NULL,
	[TotalSignalSeconds] [decimal](18, 2) NULL,
	[SignalToResourceRatio] [decimal](10, 4) NULL,
	[CPUWaitSeconds] [decimal](18, 2) NULL,
	[MemoryWaitSeconds] [decimal](18, 2) NULL,
	[DiskWaitSeconds] [decimal](18, 2) NULL,
	[BlockingWaitSeconds] [decimal](18, 2) NULL,
	[OtherWaitSeconds] [decimal](18, 2) NULL,
	[CPUWaitPct] [decimal](5, 2) NULL,
	[MemoryWaitPct] [decimal](5, 2) NULL,
	[DiskWaitPct] [decimal](5, 2) NULL,
	[BlockingWaitPct] [decimal](5, 2) NULL,
	[OtherWaitPct] [decimal](5, 2) NULL,
	[TopWaitType1] [nvarchar](60) NULL,
	[TopWaitType1Seconds] [decimal](18, 2) NULL,
	[TopWaitType1Pct] [decimal](5, 2) NULL,
	[TopWaitType2] [nvarchar](60) NULL,
	[TopWaitType2Seconds] [decimal](18, 2) NULL,
	[TopWaitType2Pct] [decimal](5, 2) NULL,
	[TopWaitType3] [nvarchar](60) NULL,
	[TopWaitType3Seconds] [decimal](18, 2) NULL,
	[TopWaitType3Pct] [decimal](5, 2) NULL,
	[PeakBlockingHourLocal] [tinyint] NULL,
	[TopBlockingWaitType] [nvarchar](60) NULL,
	[MoMTotalWaitChangePct] [decimal](6, 2) NULL,
	[MoMCPUWaitChangePct] [decimal](6, 2) NULL,
	[MoMMemoryWaitChangePct] [decimal](6, 2) NULL,
	[MoMDiskWaitChangePct] [decimal](6, 2) NULL,
	[MoMBlockingWaitChangePct] [decimal](6, 2) NULL,
	[CreatedAtUTC] [datetime2](0) NOT NULL,
 CONSTRAINT [PK_Waits_MonthlyRollup] PRIMARY KEY CLUSTERED 
(
	[RollupMonth] ASC,
	[ServerName] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO

ALTER TABLE [Pulse].[Waits_MonthlyRollup] ADD  DEFAULT (sysutcdatetime()) FOR [CreatedAtUTC]
GO
