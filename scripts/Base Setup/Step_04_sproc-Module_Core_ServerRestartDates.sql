USE [SQLPulse]
GO


SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO



CREATE PROCEDURE [Pulse].[Module_Core_ServerRestartDates]
	
AS

BEGIN

/* *********************************************************************************

Source: SQL Pulse: Update [Pulse].[Core_ServerRestartDates]
Build: 1.3
Build Date: 2026-03-08

This sproc is called by every other stored procedure on execution for the purposes of coordinating data gathering,
eliminating duplicates, and general bookkeeping. 

The code could definitely be tighter and more efficient; it is structured this way in the interests of being as human-readable as possible

This sproc performs the following activities:

   1) Declare the internal variables
   2) Set the variables for processing
   3) Insert values into [Pulse].[Core_ServerRestartDates] with duplicate checking
   
********************************************************************************* */

-- 1) Declare internal variables

	DECLARE @SystemThreadLogin datetime
	DECLARE @RunDate datetime
	

-- 2) Set the values for processing

	--SET @SystemThreadLogin = CAST((SELECT sqlserver_start_time FROM sys.dm_os_sys_info) as smalldatetime)

	SELECT @SystemThreadLogin = CAST(
		DATEADD(second, DATEDIFF(second, GETDATE(), GETUTCDATE()), sqlserver_start_time) 
		AS smalldatetime)
		FROM sys.dm_os_sys_info

	--SELECT @SystemThreadLogin

	SET @RunDate = CAST(SYSUTCDATETIME() as smalldatetime)


-- 3) Insert values into [Pulse].[Module_Core_ServerRestartDates] with duplicate checking

	IF NOT EXISTS (SELECT 1 FROM [Pulse].[Core_ServerRestartDates] WHERE RestartDate = @SystemThreadLogin)
		INSERT INTO [Pulse].[Core_ServerRestartDates] (RestartDate, RunDate) VALUES (@SystemThreadLogin, @RunDate)


END
GO


