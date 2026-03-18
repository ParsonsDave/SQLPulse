/* *************************************************************************************************

Source: SQL Pulse: Create Core Tables
Build: 1.3
Build Date: 2026-03-18

This script is designed to build tables that will always be used by the app, no matter which modules
are installed. 

The tables are commented in-line 

********************************************************************************************** */

USE [SQLPulse]
GO

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