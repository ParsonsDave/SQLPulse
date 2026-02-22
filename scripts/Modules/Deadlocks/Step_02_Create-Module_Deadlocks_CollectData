USE [SQLPulse]
GO

/****** Object:  StoredProcedure [dbo].[Module_Deadlocks_CollectData]    Script Date: 1/17/2026 4:23:38 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO



CREATE PROCEDURE [dbo].[Module_Deadlocks_CollectData] 
	
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	/* *********************************************************************************

	Source: SQLPulse: Get Deadlock information
	Build: 1.0
	Build Date: 2026-01-17

	This sproc gathers and records SQL Deadlock data
	NOTE: As mentioned in the README, this version is tracking total occurances via sys.dm_os_performance_counters
	   At the current time, the data is for the monthly reporting, not for ad hoc alerting / diagnosing
	   So this procedure is less complex than most

	The variables for the counters are INT rather than BIGINT for two key reasons:
		1) INT is half the size of BIGINT and Pulse is intended to be lightweight
		2) AS hilarious as BIGINT would normally be, there is actually a legitimate chance INT might overflow,
		   and frankly that's extremely useful as an indicator something is severely wrong with the server

	NOTE: As crazy as #2 sounds, I have actually seen real life production systems that could conceivably overflow INT if left running long enough

	It performs the following activities:

	   1) Get the last server restart time via the stored procedure [dbo].[UpdateLastServerStart]
	   2) Declare the internal variables and set their values
	   3) Get the current deadlock counter
	   4) Get the previous counter value from the table Deadlocks_Counter
	   5) Calculate the delta between counter values
	   6) Insert the data into table Deadlocks_Counter
	   7) Object cleanup

	** NOTE ** - Ensure that the AlertVersion variable is always kept up-to-date!
		--Note 2: There is currently no AlertVersion variable; perhaps later

	********************************************************************************* */

	-- 1) Get the last server restart time via the stored procedure [dbo].[UpdateLastServerStart]

		EXECUTE [dbo].[UpdateLastServerStart]

	-- 2) Declare the internal variables and set their values
		
			DECLARE @CurrentValue int
			DECLARE @PreviousValue int
			DECLARE @Delta int
			DECLARE @LastStartup datetime = (SELECT MAX(RestartDate) FROM tblServerRestartDates)
			DECLARE @EventTime datetime = (SELECT SYSUTCDATETIME())

	-- 3) Get the current deadlock counter

		SELECT @CurrentValue = cntr_value
			FROM sys.dm_os_performance_counters
			WHERE counter_name = 'Number of Deadlocks/sec'
			AND instance_name = '_Total';

	-- 4) Get the previous counter value from the table Deadlocks_Counter

		SELECT TOP (1) @PreviousValue = RawCounterValue
			FROM dbo.Deadlocks_Counter
			ORDER BY SampleID DESC;

	-- 5) Calculate the delta between counter values

		IF @PreviousValue IS NULL
			SET @Delta = 0;  -- First run
		ELSE IF @CurrentValue < @PreviousValue
			SET @Delta = @CurrentValue;  -- Counter reset (restart/failover)
		ELSE
			SET @Delta = @CurrentValue - @PreviousValue;

	-- 6) Insert the data into table Deadlocks_Counter

		INSERT INTO Deadlocks_Counter
			(
				SampleTimeLocal,
				RawCounterValue,
				DeadlocksSinceLast
			)
		VALUES
			(
				SYSDATETIME(),
				@CurrentValue,
				@Delta
			)

	-- 7) Object cleanup

		-- This space intentionally blank

END
GO

