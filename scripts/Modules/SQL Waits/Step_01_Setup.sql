USE [SQLPulse]
GO

-- Insert values into the Modules table

	INSERT INTO dbo.Modules (ModuleName, ModuleVersion, ModuleDescription, IsEnabled)
	VALUES 
		('Waits', 1.0, 'Monitors SQL Wait Statistics', 1)

-- Insert values into the ModuleActions table to cover what the module can do

	INSERT INTO dbo.ModuleActions (ModuleID, ActionType, SprocName, IsEnabled, ExecutionOrder, ActionDescription)
	VALUES 
		((SELECT ID FROM dbo.Modules WHERE ModuleName = 'Waits'), 'CollectData', 'Module_Waits_CollectData', 1, 1, 'Collects Wait data from the SQL Server instance')


-- Create the data table(s)

	CREATE TABLE Waits_StatsCurrent(
			[EventTime] [datetime] NULL,
			[WaitType] [nvarchar](60) NULL,
			[Category] [nvarchar](20) NULL,
			[WaitSeconds] [decimal](14,2) NULL,
			[ResourceSeconds] [decimal](14,2),
			[SignalSeconds] [decimal](14,2),
			[TotalWaitPct] [decimal](5,2),
			[WaitingTasksCount] [bigint] NULL
			)

	CREATE TABLE Waits_StatsSnapshots(
			[EventTime] [datetime] NULL,
			[WaitType] [nvarchar](60) NULL,
			[Category] [nvarchar](20) NULL,
			[WaitSeconds] [decimal](14,2) NULL,
			[ResourceSeconds] [decimal](14,2),
			[SignalSeconds] [decimal](14,2),
			[TotalWaitPct] [decimal](5,2),
			[WaitingTasksCount] [bigint] NULL
			)

	CREATE TABLE Waits_StatsArchive(
			[EventTime] [datetime] NULL,
			[WaitType] [nvarchar](60) NULL,
			[Category] [nvarchar](20) NULL,
			[WaitSeconds] [decimal](14,2) NULL,
			[ResourceSeconds] [decimal](14,2),
			[SignalSeconds] [decimal](14,2),
			[TotalWaitPct] [decimal](5,2),
			[WaitingTasksCount] [bigint] NULL
			)
