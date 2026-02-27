/* ****************************************************************************************************

Source: SQL Pulse Core Module: Create External Actions Agent Job
Build: 1.1
Build Date: 2026-02-26

This script creates the SQL Agent job [SQLPulse - External Actions]; this job handles
various activities that cannot or should not be done in a normal stored procedure.

The Actions are separated into job steps, with each action being administratively 
contained by logic that causes a step to exit after execution rather than proceeding
to the next step. 

>>> NOTE!!!! At release, this code needs to be parameterized to accomodate custom database installation

**************************************************************************************************** */

USE [msdb]
GO


BEGIN TRANSACTION
DECLARE @ReturnCode2 INT
SELECT @ReturnCode2 = 0

IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'[Uncategorized (Local)]' AND category_class=1)
BEGIN
EXEC @ReturnCode2 = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'[Uncategorized (Local)]'
IF (@@ERROR <> 0 OR @ReturnCode2 <> 0) GOTO QuitWithRollback2

END

DECLARE @jobId2 BINARY(16)
EXEC @ReturnCode2 =  msdb.dbo.sp_add_job @job_name=N'SQLPulse - External Actions', 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'No description available.', 
		@category_name=N'[Uncategorized (Local)]', 
		@owner_login_name=N'sa', @job_id = @jobId2 OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode2 <> 0) GOTO QuitWithRollback2
/****** Object:  Step [Module - Disk - CollectInformation]    Script Date: 2/26/2026 10:06:56 PM ******/
EXEC @ReturnCode2 = msdb.dbo.sp_add_jobstep @job_id=@jobId2, @step_name=N'Module - Disk - CollectInformation', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'PowerShell', 
		@command=N'# CONFIGURATION SECTION
$serverName   = "localhost"
$databaseName = "SQLPulse"
$tableName    = "[Pulse].[Disk_Information]"
$eventTimeUTC = (Get-Date).ToUniversalTime()
$eventTimeLocal = (Get-Date)


# SQL Connection Setup
$connectionString = "Server=$serverName;Database=$databaseName;Integrated Security=True;"
$sqlConnection = New-Object System.Data.SqlClient.SqlConnection
$sqlConnection.ConnectionString = $connectionString
$sqlConnection.Open()

# Function to translate DriveType integer to string
function Get-DriveTypeName($type) {
    switch ($type) {
        0 { "Unknown" }
        1 { "No Root Directory" }
        2 { "Removable Disk" }
        3 { "Local Disk" }
        4 { "Network Drive" }
        5 { "CD-ROM" }
        6 { "RAM Disk" }
        default { "Other" }
    }
}

# Use Get-WmiObject instead of Get-CimInstance for compatibility
$volumes = Get-WmiObject Win32_Volume | Where-Object {
    ($_.DriveType -ge 2 -and $_.DriveType -le 6) -and
    $_.FileSystem -ne $null -and
    $_.Label -ne "Recovery" -and
    ($_.DriveLetter -or $_.Name -match "^.:\\")
}

foreach ($volume in $volumes) {
    $mountPath   = $volume.Name.TrimEnd(''\'')
    $label       = $volume.Label
    $sizeKB      = [math]::Round($volume.Capacity / 1KB)
    $freeKB      = [math]::Round($volume.FreeSpace / 1KB)
    $usedKB      = $sizeKB - $freeKB
    $percentFree = if ($sizeKB -ne 0) { [math]::Round(($freeKB / $sizeKB) * 100, 2) } else { 0 }
    $percentUsed = 100 - $percentFree
    $driveType   = Get-DriveTypeName $volume.DriveType
    $isMountPoint   = if ($volume.DriveLetter) { 0 } else { 1 }

    # Escape single quotes in SQL strings
    $mountPathSql = $mountPath -replace "''", "''''"
    $labelSql     = $label -replace "''", "''''"
    $driveTypeSql = $driveType -replace "''", "''''"

    # Build SQL Insert
    $insertCmd = $sqlConnection.CreateCommand()
    $insertCmd.CommandText = @"
INSERT INTO $tableName (
    EventTimeUTC,
    EventTimeLocal,
    DriveLetterOrMountPath,
    Label,
    SizeKB,
    FreeSpaceKB,
    UsedSpaceKB,
    PercentFree,
    PercentUsed,
    DriveType,
    IsMountPoint
) VALUES (
    ''$eventTimeUTC'',
    ''$eventTimeLocal'',
    ''$mountPathSql'',
    ''$labelSql'',
    $sizeKB,
    $freeKB,
    $usedKB,
    $percentFree,
    $percentUsed,
    ''$driveTypeSql'',
    $isMountPoint
);
"@

    # Execute Insert
    $insertCmd.ExecuteNonQuery() | Out-Null
}

# Cleanup
$sqlConnection.Close()', 
		@database_name=N'master', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode2 <> 0) GOTO QuitWithRollback2
EXEC @ReturnCode2 = msdb.dbo.sp_update_job @job_id = @jobId2, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode2 <> 0) GOTO QuitWithRollback2
EXEC @ReturnCode2 = msdb.dbo.sp_add_jobserver @job_id = @jobId2, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode2 <> 0) GOTO QuitWithRollback2
COMMIT TRANSACTION
GOTO EndSave2
QuitWithRollback2:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave2:

------------------------------------------------------------------------------------------------------------------------------
-- Update the new job to replace [localhost] with the actual SQL servername
-- The job step is named the same in either case
------------------------------------------------------------------------------------------------------------------------------

DECLARE @jobName SYSNAME = N'SQLPulse - External Actions';
DECLARE @stepName SYSNAME = N'Module - Disk - CollectInformation';
DECLARE @serverName NVARCHAR(128);
DECLARE @stepCommand NVARCHAR(MAX);
DECLARE @stepId INT;

-- Get the actual server name
SELECT @serverName = CAST(SERVERPROPERTY('ServerName') AS NVARCHAR(128));

-- Get the job ID and step ID
SELECT 
    @jobId2 = job_id
FROM msdb.dbo.sysjobs
WHERE name = @jobName;

SELECT 
    @stepId = step_id,
    @stepCommand = command
FROM msdb.dbo.sysjobsteps
WHERE job_id = @jobId2
  AND step_name = @stepName;

-- Replace "localhost" with actual server name
SET @stepCommand = REPLACE(@stepCommand, '"localhost"', '"' + @serverName + '"');

-- Update the job step with the new command
EXEC msdb.dbo.sp_update_jobstep
    @job_id = @jobId2,
    @step_id = @stepId,
    @command = @stepCommand;



