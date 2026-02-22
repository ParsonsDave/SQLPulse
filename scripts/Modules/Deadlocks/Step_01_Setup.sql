USE [SQLPulse]
GO

-- Insert values into the Modules table

	INSERT INTO dbo.Modules (ModuleName, ModuleVersion, ModuleDescription, IsEnabled)
	VALUES 
		('Deadlocks', 1.0, 'Monitors SQL Deadlock Information', 1)

-- Insert values into the ModuleActions table to cover what the module can do

	INSERT INTO dbo.ModuleActions (ModuleID, ActionType, SprocName, IsEnabled, ExecutionOrder, ActionDescription)
	VALUES 
		((SELECT ID FROM dbo.Modules WHERE ModuleName = 'Deadlocks'), 'CollectData', 'Module_Deadlocks_CollectData', 1, 1, 'Collects Deadlock data from the SQL Server instance')


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
