USE [SQLPulse]
GO

-- Insert values into the Modules table

	INSERT INTO Pulse.Modules (ModuleName, ModuleVersion, ModuleDescription, IsEnabled)
	VALUES 
		('Blocking', 1.0, 'Monitors SQL Blocking Statistics', 1)

-- Insert values into the ModuleActions table to cover what the module can do

	INSERT INTO Pulse.ModuleActions (ModuleID, ActionType, SchemaName, SprocName, IsEnabled, ExecutionOrder, ActionDescription)
	VALUES 
		((SELECT ID FROM dbo.Modules WHERE ModuleName = 'Blocking'), 'CollectData', 'Pulse', 'Module_Blocking_CollectData', 1, 1, 'Collects Blocking data from the SQL Server instance')

INSERT INTO Pulse.ModuleActions (ModuleID, ActionType, SchemaName, SprocName, IsEnabled, ExecutionOrder, ActionDescription)
	VALUES 
		((SELECT ID FROM dbo.Modules WHERE ModuleName = 'Blocking'), 'CollectData', 'Pulse', 'Module_Blocking_MonthlyRollup', 1, 3, 'Performs monthly rollup of blocking data to aggregate and reduce storage of historical data')


-- Create data table: Database Blocking Statistics
-- This is cumlative data on the amount of blocking time experienced within each database
-- It isn't directly mappable to the sessions data (below), but is an excellent insight to what databases have the most blocking activity
-- This is also for historical use; rollup data is handled from the TimeByMonth table (below)

CREATE TABLE Pulse.BlockingTimeDatabases
(
    ID                   bigint IDENTITY(1,1) PRIMARY KEY,

    -- When the sample was taken
    EventTimeUTC              datetime2(3) NOT NULL,
    EventTimeLocal            datetime2(3) NOT NULL,

    -- Database identity
    DatabaseID                 int NOT NULL,
    DatabaseName               sysname NOT NULL,

    -- Cumulative blocking time since last restart
    RowLockWaitMs              bigint NOT NULL,
    PageLockWaitMs             bigint NOT NULL,
    TotalBlockingWaitMs        AS (RowLockWaitMs + PageLockWaitMs) PERSISTED,

    -- Optional: store the server uptime snapshot for context
    UptimeSeconds              bigint NOT NULL,
    ProcessorCount             int NOT NULL,
    TotalProcessorTimeSeconds  bigint NOT NULL
);

-- Create Table: Blocking Session Data
-- This is a snapshot of things blocked at a point in time
-- Reporting on this data will be focused on the type of command (SELECT, DELETE, etc) and tracking how long sessions are blocked

CREATE TABLE Pulse.BlockingSessions
(
    ID               bigint IDENTITY(1,1) PRIMARY KEY,

    -- When the sample was taken
    EventTimeUTC          datetime2(3) NOT NULL,
    EventTimeLocal        datetime2(3) NOT NULL,

    -- Blocked session info
    SessionID              int NOT NULL,
    BlockingSessionID      int NOT NULL,
    WaitType               nvarchar(60) NULL,
    WaitTimeMs             int NOT NULL,
    DatabaseID             int NOT NULL,
    DatabaseName           sysname NOT NULL,
    SqlHandle              varbinary(64) NULL,

    -- Blocking session info
    BlockedCommand         nvarchar(32) NULL,
    BlockingCommand        nvarchar(32) NULL
);

-- Create Table: Blocking Time By Month
-- This is akin to the Waits table strucutre; this captures data before and after restarts and at the bounradies of months to allow for reporting on blocking trends over time without the data being skewed by restarts or the amount of time between restarts
-- Blocking rollup is based on the data in this table; other than capturing ServerName and RollupMonth, the data is the same as the BlockingTimeDatabases table, but with the blocking time aggregated for the month and database; this allows for long term trending without the data being skewed by restarts or the amount of time between restarts

CREATE TABLE [Pulse].[Blocking_TimeByMonth](
	[ID] [bigint] IDENTITY(1,1) NOT NULL,

    -- Converts EventTime to SnapshotDate to denote that it's not the collection time that's relevant, but the SnapshotType column
    [SnapshotDateUTC] [datetime2](3) NOT NULL,
	[SnapshotDateLocal] [datetime2](3) NOT NULL,
	
    -- Metadata for the rollup procedure
    [SnapshotType] [nvarchar](20) NOT NULL,
	[ServerName] [sysname] NOT NULL,
	[RollupMonth] [date] NOT NULL,
	
    --Database Identity
    [DatabaseID] [int] NOT NULL,
	[DatabaseName] [sysname] NOT NULL,
	
    -- Cumulative blocking time since last restart
    -- NOTE: StartOfMonth snapshots will have these numbers swapped to negative numbers to clear any carryover data from the previous month from the totals
    [RowLockWaitMs] [bigint] NOT NULL,
	[PageLockWaitMs] [bigint] NOT NULL,
	[TotalBlockingWaitMs]  AS ([RowLockWaitMs]+[PageLockWaitMs]) PERSISTED,
	
    -- Optional: store the server uptime snapshot for context
    [UptimeSeconds] [bigint] NOT NULL,
	[ProcessorCount] [int] NOT NULL,
	[TotalProcessorTimeSeconds] [bigint] NOT NULL,
PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO


-- Create Table: Blocking MonthlyRollup
-- This table holds the reporting rollup data for the month

CREATE TABLE [Pulse].[Blocking_MonthlyRollup](
	
    -- ID marking which month this is for
    [RollupMonth] [date] NOT NULL,
	
    -- Database identity & servername (in case Pulse is copied to another server or the server name changes)
    [DatabaseID] [int] NOT NULL,
	[ServerName] [sysname] NOT NULL,
	[DatabaseName] [sysname] NOT NULL,
	
    -- Time totals for the month. These will be used with the blockign waits for reporting
    [RowLockWaitSeconds] [decimal](18, 2) NOT NULL,
	[PageLockWaitSeconds] [decimal](18, 2) NOT NULL,
	[TotalBlockingWaitSeconds]  AS ([RowLockWaitSeconds]+[PageLockWaitSeconds]) PERSISTED,
	
    -- 
    [TopBlockingType] [nvarchar](20) NULL,
	[TopBlockingTypePct] [decimal](5, 2) NULL,
	[PctOfInstanceBlocking] [decimal](6, 2) NULL,
	[RankWithinInstance] [int] NULL,
	[PctOfTotalProcessorTime] [decimal](6, 2) NULL,
	
    -- Handy month-over-month comparisons
    [MoMBlockingChangePct] [decimal](6, 2) NULL,
	[MoMRowLockChangePct] [decimal](6, 2) NULL,
	[MoMPageLockChangePct] [decimal](6, 2) NULL,
	
    -- When the report was created. This is useful, as anything other than the first of the month should be investigated
    [CreatedAtUTC] [datetime2](0) NOT NULL,
 CONSTRAINT [PK_Blocking_MonthlyRollup] PRIMARY KEY CLUSTERED 
(
	[RollupMonth] ASC,
	[DatabaseID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO

ALTER TABLE [Pulse].[Blocking_MonthlyRollup] ADD  DEFAULT (sysutcdatetime()) FOR [CreatedAtUTC]
GO
