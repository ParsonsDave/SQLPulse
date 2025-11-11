USE [SQLPulse]
GO

/****** Object:  StoredProcedure [dbo].[GetReportDates]    Script Date: 11/11/2025 3:41:30 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE PROCEDURE [dbo].[GetReportDates] 
	(@StartofMonth date OUTPUT, @EndofMonth date OUTPUT, @TotalMinutes int OUTPUT)
	
AS
BEGIN

/* ****************************************************************************************************

Source: Dave's Basic Monitoring Protocol: Get Report Dates
Build: 2.1
Build Date: 2025-11-11

The purpose of this stored procedure is to return the following values:
	1) Start of month (ex: 2025-01-01)
	2) End of Month (ex: 2025-01-31)
	3) How many minutes were in the month (ex: 44640)

This is because all reporting is done at the start of one month for the previous month;
additionally, different metrics are gathered at different intervals, but all are minute-based

This centralizes a large code block out of the reporting procedures 

It performs the following activities:

   1) Set NOCOUNT ON to prevent extra result sets from interfering with SELECT statements
   2) Declare the internal variables and values
   3) Calculate the outputs
   
**************************************************************************************************** */

	-- 1) Set NOCOUNT ON to prevent extra result sets from interfering with SELECT statements
			
		SET NOCOUNT ON;
		
	-- 2) Declare the internal variables and values
			
		-- This section intentionally blank for future expansion
		
	-- 3) Calculate the output
		
		-- Step 1: Calculate the last day of the previous month (EndofMonth)
			SET @EndofMonth = DATEADD(day, -1, DATEADD(month, DATEDIFF(month, 0, GetDate()), 0));
			
		-- Step 2: Calculate the first day of the previous month (StartofMonth)
			SET @StartofMonth = DATEADD(month, DATEDIFF(month, 0, @EndofMonth), 0);
			
		-- Step 3: Calculate the total minutes in the period 
			SET @TotalMinutes = DATEDIFF(MINUTE, @StartofMonth, DATEADD(day, 1, @EndofMonth));
		

END
GO
