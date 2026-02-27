/* ****************************************************************************************************

Source: SQL Pulse Core Module: Create Core Processing Agent Job
Build: 1.1
Build Date: 2026-02-26

This script creates the SQL Agent job [SQLPulse - Core Processing]; this job handles
all the core processing for the installed features, and is properly noted as job 1 of 2
for the entire project. 

Operation is very simple: it looks up all enabled actions in the [ModuleActions] table.
The entries in this table are all stored procedures, and have a key parameter stote in the
[ExecutionOrder] column, which is the order in which activity phases are executed:

1: Data Collection
2: External Actions (these are job steps in [SQLPulse - External Actions])
3: Reserverd for future expansion (very likely to be Alerting Activities)
4: Rollup Activities (monthly at release, adding weekly, quarteryl, etc later)
5: Reporting Activities

Note that each Module of Pulse is self-contained, so there is no requirement that any given
module's peer procedure (collection, rollup, etc) runs before any other.

One the Actions list is generated, the job steps through each until all Actions have been
completed. All results are logged into the table [ModuleExecutionLog].

>>> NOTE!!!! At release, this code needs to be parameterized to accomodate custom database installation

**************************************************************************************************** */

USE [msdb]
GO


BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0

IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'Data Collector' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'Data Collector'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'SQLPulse - Core Processing', 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'No description available.', 
		@category_name=N'Data Collector', 
		@owner_login_name=N'sa', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [Module Actions: Data Collection]    Script Date: 2/26/2026 9:22:24 PM ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Module Actions: Data Collection', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'SET NOCOUNT ON;

DECLARE @SchemaName sysname;
DECLARE @SprocName sysname;
DECLARE @SQL nvarchar(4000);

-- Temp table to hold the list of monitor actions
CREATE TABLE #MonitorActions
(
    ID int IDENTITY(1,1),
    SchemaName sysname,
    SprocName sysname
);

INSERT INTO #MonitorActions (SchemaName, SprocName)
SELECT SchemaName, SprocName
FROM Pulse.ModuleActions
--WHERE ActionType = ''CollectData''
--  AND IsEnabled = 1
WHERE IsEnabled = 1
ORDER BY ExecutionOrder, ID;

DECLARE @MaxID int = (SELECT MAX(ID) FROM #MonitorActions);
DECLARE @CurrentID int = 1;

WHILE @CurrentID <= @MaxID
BEGIN
    SELECT
     @SchemaName = SchemaName,
     @SprocName = SprocName
    FROM #MonitorActions
    WHERE ID = @CurrentID;

    BEGIN TRY
        SET @SQL = N''EXEC '' + QUOTENAME(@SchemaName) + ''.'' + QUOTENAME(@SprocName) + '';'';
        EXEC (@SQL);

        -- Optional: log success
        INSERT INTO Pulse.ModuleExecutionLog
        (
            ActionType,
            SprocName,
            ExecutionTime,
            Success,
            ErrorMessage
        )
        VALUES
        (
            ''Monitor'',
            @SprocName,
            SYSUTCDATETIME(),
            1,
            NULL
        );
    END TRY
    BEGIN CATCH
        -- Log failure but continue to next module
        INSERT INTO Pulse.ModuleExecutionLog
        (
            ActionType,
            SprocName,
            ExecutionTime,
            Success,
            ErrorMessage
        )
        VALUES
        (
            ''Monitor'',
            @SprocName,
            SYSUTCDATETIME(),
            0,
            ERROR_MESSAGE()
        );
    END CATCH;

    SET @CurrentID += 1;
END;', 
		@database_name=N'SQLPulse', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'Every_5_Minutes', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=4, 
		@freq_subday_interval=5, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20260110, 
		@active_end_date=99991231, 
		@active_start_time=0, 
		@active_end_time=235959, 
		@schedule_uid=N'b597fd25-25f4-43da-98e4-10660c1a299c'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:
GO


