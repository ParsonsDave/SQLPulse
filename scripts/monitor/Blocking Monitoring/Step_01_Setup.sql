USE [SQLPulse]
GO

-- Insert values into the Modules table

	INSERT INTO dbo.Modules (ModuleName, ModuleVersion, ModuleDescription, IsEnabled)
	VALUES 
		('Blocking', 1.0, 'Monitors SQL Blocking Statistics', 1)

-- Insert values into the ModuleActions table to cover what the module can do

	INSERT INTO dbo.ModuleActions (ModuleID, ActionType, SprocName, IsEnabled, ExecutionOrder, ActionDescription)
	VALUES 
		((SELECT ID FROM dbo.Modules WHERE ModuleName = 'Blocking'), 'CollectData', 'Module_Blocking_CollectData', 1, 1, 'Collects Blocking data from the SQL Server instance')


-- Create data table: Database Blocking Statistics
-- This is cumlative data on the amount of blocking time experienced within each database
-- It isn't directly mappable to the sessions data (below), but is an excellent insight to what databases have the most blocking activity

CREATE TABLE BlockingTimeDatabases
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

CREATE TABLE BlockingSessions
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
);