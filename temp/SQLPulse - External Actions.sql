USE [msdb]
GO

/****** Object:  Job [SQLPulse - External Actions]    Script Date: 2/24/2026 9:41:10 PM ******/
BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
/****** Object:  JobCategory [[Uncategorized (Local)]]]    Script Date: 2/24/2026 9:41:10 PM ******/
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'[Uncategorized (Local)]' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'[Uncategorized (Local)]'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'SQLPulse - External Actions', 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'No description available.', 
		@category_name=N'[Uncategorized (Local)]', 
		@owner_login_name=N'sa', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [Module - Disk - CollectInformation]    Script Date: 2/24/2026 9:41:10 PM ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Module - Disk - CollectInformation', 
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
$serverName   = "SQLPULSEDEV01"
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
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:

GO

