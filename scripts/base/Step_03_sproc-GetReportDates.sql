USE [SQLPulse]
GO

/****** Object:  StoredProcedure [dbo].[GetReportDates]    Script Date: 3/2/2025 4:34:30 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE PROCEDURE [dbo].[GetReportDates] 
	(@StartofMonth date OUTPUT, @EndofMonth date OUTPUT, @TotalMinutes int OUTPUT)
	
AS
BEGIN

/* ****************************************************************************************************

Source: SQL Pulse: Get Report Dates
Build: 1.1
Build Date: 2025-03-02

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
   3) Calculate the ouputs
   
**************************************************************************************************** */

	-- 1) Set NOCOUNT ON to prevent extra result sets from interfering with SELECT statements
		
		SET NOCOUNT ON;


    -- 2) Declare the internal variables and values
		
		Declare @StartDate date
		Declare @EndDate date
		Declare @ReportMonth int = (select month(DATEADD(month, -1, Getdate())))
		Declare @YearInQuestion varchar(4)
		Declare @IsLeapYear int = dbo.fn_IsLeapYear(Year(GetDate()))
		
		Declare @WorkingDays int = 0

			If @ReportMonth = 1  Set @WorkingDays = 31
			If @ReportMonth = 3  Set @WorkingDays = 31
			If @ReportMonth = 5  Set @WorkingDays = 31
			If @ReportMonth = 7  Set @WorkingDays = 31
			If @ReportMonth = 8  Set @WorkingDays = 31
			If @ReportMonth = 10  Set @WorkingDays = 31
			If @ReportMonth = 12  Set @WorkingDays = 31
	
			If @ReportMonth = 4  Set @WorkingDays = 30
			If @ReportMonth = 6  Set @WorkingDays = 30
			If @ReportMonth = 9  Set @WorkingDays = 30
			If @ReportMonth = 11  Set @WorkingDays = 30

			If @ReportMonth = 2 AND @IsLeapYear = 1 Set @WorkingDays = 29
			If @ReportMonth = 2 AND @IsLeapYear = 0 Set @WorkingDays = 28

		If @ReportMonth = 12 Set @YearInQuestion = CAST(Year(GetDate()) - 1 as varchar(4)) Else Set @YearInQuestion = CAST(Year(GetDate()) as varchar(4))

		Set @StartDate = @YearInQuestion + '-' + CAST(@ReportMonth as varchar(2)) + '-01'
		Set @EndDate = @YearInQuestion + '-' + CAST(@ReportMonth as varchar(2)) + '-' + CAST(@WorkingDays as varchar(2))
	
	-- 3) Calculate the ouputs

		Set @TotalMinutes = @WorkingDays * 1440
		Set @StartofMonth = CAST(@StartDate as date)
		Set @EndofMonth = CAST(@EndDate as date)

END
GO
