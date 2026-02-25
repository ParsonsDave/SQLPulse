-- This is a cleanup script when moving the Pulse database from one server to another.
-- It needs to be tossed into a 'utilities' folder or something before general release

truncate table [Pulse].[BlockingSessions];
truncate table [Pulse].[BlockingTimeDatabases];
truncate table [Pulse].[CPU_Data];
truncate table [Pulse].[CPU_MonthlyRollup];
truncate table [Pulse].[Deadlocks_Counter];
truncate table [Pulse].[Deadlocks_MonthlyRollup];
truncate table [Pulse].[Disk_Information];
truncate table [Pulse].[Disk_Latency];
truncate table [Pulse].[Disk_MonthlyRollup];
truncate table [Pulse].[Memory_Counters];
truncate table [Pulse].[Memory_MonthlyRollup];
truncate table [Pulse].[ModuleExecutionLog];
truncate table [Pulse].[Waits_StatsArchive];
truncate table [Pulse].[Waits_StatsCurrent];
truncate table [Pulse].[Waits_StatsSnapshots];
truncate table [Pulse].[tblServerRestartDates];
