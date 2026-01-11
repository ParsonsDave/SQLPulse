USE [SQLPulse];
GO

CREATE PROCEDURE [dbo].[Module_Disk_CollectInformation]
AS
BEGIN
    SET NOCOUNT ON;

    /*
        This stored procedure triggers the SQL Agent job responsible for
        collecting disk information via PowerShell.

        It is designed to be called by the metadata-driven ModuleActions
        execution engine as an External action.

        Better documentation needed
    */

    BEGIN TRY
        EXEC msdb.dbo.sp_start_job 
            @job_name = N'SQLPulse - Get Disk Information',
            @step_name = N'DiskInformation';   -- optional but recommended
    END TRY
    BEGIN CATCH
        -- Bubble the error up so ModuleActions logging can capture it
        DECLARE @Err nvarchar(4000) = ERROR_MESSAGE();
        RAISERROR(@Err, 16, 1);
    END CATCH;
END
GO