/* *************************************************************************************************

Source: SQL Pulse: Create Global Tables
Build: 1.2
Build Date: 2026-01-10

This script is designed to build tables that will always be used by the app, no matter which modules
are installed. 

The list of tables and their usage:

- Parameters: This table holds global parameters for the application. 
  Examples include data collection intervals, cleanup intervals, and other settings that affect
  the overall operation of SQL Pulse.

- Modules: This is a list of all installed Pulse modules - ie, CPU, Disk, even Cleanup.

- ModuleActions: This is a list of actions for the aforementioned Modeuls table. Most modules would have
  standard actions like 'Monitor', 'Alert', or 'Report', but some modules might have other unique actions
  This allows expansion, upgrades, etc based on modules

THIS IS A WORK IN PROGRESS

********************************************************************************************** */

USE [SQLPulse]
GO

-- Create the core Parameters table to hold various lookup vaules

	CREATE TABLE [dbo].[Parameters](
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

-- Create the Modules table to track the installed features

	CREATE TABLE [dbo].[Modules](
		[ID] [int] IDENTITY(1,1) NOT NULL,
		[ModuleName] [nvarchar](50) NULL,
		[ModuleVersion] [decimal](5, 3) NULL,
		[ModuleDescription] [nvarchar](255) NULL,
		[IsEnabled] [bit] NULL
	) ON [PRIMARY]
	GO

-- Create the ModuleActions table to track options presented by each Module

	CREATE TABLE [dbo].[ModuleActions](
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

	ALTER TABLE [dbo].[ModuleActions] ADD  DEFAULT ((1)) FOR [IsEnabled]
	GO

	ALTER TABLE [dbo].[ModuleActions] ADD  DEFAULT (sysutcdatetime()) FOR [CreatedDate]
	GO

	ALTER TABLE [dbo].[ModuleActions]  WITH CHECK ADD  CONSTRAINT [FK_ModuleActions_Modules] FOREIGN KEY([ModuleID])
	REFERENCES [dbo].[Modules] ([ID])
	GO

	ALTER TABLE [dbo].[ModuleActions] CHECK CONSTRAINT [FK_ModuleActions_Modules]
	GO

	CREATE INDEX IX_ModuleActions_ModuleID ON dbo.ModuleActions(ModuleID);


-- Create the Module Execution Log table to track processing results
-- This one is still experimental and may change

	CREATE TABLE [dbo].[ModuleExecutionLog](
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

	ALTER TABLE [dbo].[ModuleExecutionLog] ADD  DEFAULT (sysutcdatetime()) FOR [ExecutionTime]
	GO




/* *************************************************************************************************

BP_Parameters Examples

ID	BP_Parameter	BP_Value	DP_Description
1	CPUCollectionInterval	240	This is the last [n] minutes to collect CPU data; it should match the run schedule for the associated agent job. The default is 240 minutes (4 hours)
2	CleanupInterval	90	This is the cleanup interval for the data tables; the default is 90 days. The shortest should be 31-35 days to allow for the monthly rollup reports

********************************************************************************************** */
