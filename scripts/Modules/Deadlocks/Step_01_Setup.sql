USE [SQLPulse]
GO

-- Insert values into the Modules table

	INSERT INTO Pulse.Modules (ModuleName, ModuleVersion, ModuleDescription, IsEnabled)
	VALUES 
		('Deadlocks', 1.0, 'Monitors SQL Deadlock Information', 1)

-- Insert values into the ModuleActions table to cover what the module can do

	INSERT INTO Pulse.ModuleActions (ModuleID, ActionType, SchemaName, SprocName, IsEnabled, ExecutionOrder, ActionDescription)
	VALUES 
		((SELECT ID FROM Pulse.Modules WHERE ModuleName = 'Deadlocks'), 'CollectData', 'Pulse', 'Module_Deadlocks_CollectData', 1, 1, 'Collects Deadlock data from the SQL Server instance')

	INSERT INTO Pulse.ModuleActions (ModuleID, ActionType, SchemaName, SprocName, IsEnabled, ExecutionOrder, ActionDescription)
	VALUES 
		((SELECT ID FROM Pulse.Modules WHERE ModuleName = 'Deadlocks'), 'Rollup', 'Pulse',  'Module_Deadlocks_MonthlyRollup', 1, 3, 'Performs the Monthly Rollup calculations for the Deadlocks module')



-- Create the data table(s)
-- Internally: this is the first location where I put in [datetime2] instead of [datetime]
	-- It's the "recommended" value, but I'm not sold, mostly because I just don't have anything that requires such precision
	-- It does present an issue where I will need to decide whether to go 2 everywhere, or revert this back to [datetime]
	-- It's also the first time I put in both UTC and Local timestamp columns. I'll probably end up doing this everywhere

CREATE TABLE Deadlocks_Counter
(
    SampleID            bigint IDENTITY(1,1) PRIMARY KEY,
    SampleTimeUTC       datetime2(3) NOT NULL,
    SampleTimeLocal     datetime2(3) NOT NULL,
    RawCounterValue     bigint NOT NULL,
    DeadlocksSinceLast  int NOT NULL
);

-- Create the Monthly Rollup table for Deadlocks

USE [SQLPulse]
GO

/****** Object:  Table [Pulse].[Deadlocks_MonthlyRollup]    Script Date: 2/22/2026 7:52:00 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [Pulse].[Deadlocks_MonthlyRollup](
	[RollupMonth] [date] NOT NULL,
	[ServerName] [sysname] NOT NULL,
	[TotalDeadlocks] [int] NOT NULL,
	[AvgPerDay] [decimal](10, 2) NOT NULL,
	[AvgPerWeek] [decimal](10, 2) NOT NULL,
	[BusiestDay] [date] NULL,
	[BusiestDayCount] [int] NULL,
	[MonthOverMonthDelta] [int] NULL,
	[ZeroDeadlockDays] [int] NOT NULL,
	[PeakHourLocal] [tinyint] NULL,
	[PeakHourCount] [int] NULL,
	[GeneratedUTC] [datetime2](3) NOT NULL,
	[GeneratedLocal] [datetime2](3) NOT NULL,
 CONSTRAINT [PK_Deadlocks_MonthlyRollup] PRIMARY KEY CLUSTERED 
(
	[RollupMonth] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO