/* ****************************************************************************************************

Source: SQL Pulse Core Installation: Database Installation
Build: 1.3
Build Date: 2026-03-08

The purpose of this script is to prepare the create the primary database for SQL Pulse. By default, this
is named SQLPulse. If you would like the project to be installed into another database, just change
the variable below. All objects will be installed under the schema name [Pulse], so it will be easy
to identify them later.

It's no frills and uses the default paths to create the database and log files.

Note: If the default database paths have not been modified, this may end up with the database files
on something like C:, if the installation was done by accepting the default values in the 
wizard - this is extremely common, so a future feature might be to check the path(s) in 
use by the largest database and locate the SQLPulse files there instead, but at this time
I am not trying to be creative.

NOTE 2: Both VB Code and SSMS may provide visual cues that the THROW command is in error, but it is not.

Note 3: In the release install scripts, the @InstallDatabase variable will be used in several places to update
various objects. 

This script performs the following activities:

   1) Declare and set the variables to be used
   2) Evaluate the @InstallDatabase variable and create the database if it does not already exist
   3) Create the [Pulse] schema in the installation database

**************************************************************************************************** */

-- 1) Declare and set the variables to be used

    DECLARE @InstallDatabase sysname = N'SQLPulse'
    DECLARE @sql NVARCHAR(MAX);


-- 2) Evaluate the @InstallDatabase variable and create the database if it does not already exist

    USE [master];
    
    IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = @InstallDatabase)
    BEGIN
        SET @sql = 'CREATE DATABASE ' + QUOTENAME(@InstallDatabase) + ';';
        EXEC(@sql);

        SET @sql = 
            'ALTER DATABASE ' + QUOTENAME(@InstallDatabase) +
            ' MODIFY FILE ( NAME = N''' + @InstallDatabase + ''', SIZE = 262144KB, FILEGROWTH = 131072KB );';
        EXEC(@sql);

        SET @sql = 
            'ALTER DATABASE ' + QUOTENAME(@InstallDatabase) +
            ' MODIFY FILE ( NAME = N''' + @InstallDatabase + '_log'', SIZE = 262144KB, FILEGROWTH = 131072KB );';
        EXEC(@sql);
    END
    ELSE
    BEGIN
        THROW 51000, '**WARNING** Database [' + @InstallDatabase + '] already exists. No changes made.', 1;
    END;


-- 3) Create the [Pulse] schema in the installation database

    -- Only proceed if the database exists
    IF EXISTS (SELECT 1 FROM sys.databases WHERE name = @InstallDatabase)
    BEGIN
        -- Switch to the installation database
        SET @sql = 'USE ' + QUOTENAME(@InstallDatabase) + ';';
        EXEC(@sql);

        -- Create schema only if it does not already exist
        IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = @SchemaName)
        BEGIN
            SET @sql = 'CREATE SCHEMA ' + QUOTENAME(@SchemaName) + ';';
            EXEC(@sql);
        END;
    END
    ELSE
    BEGIN
        -- Raise a clear error if the database is missing
        THROW 51001, 'The installation database specified in @InstallDatabase does not exist. Schema creation skipped.', 1;
    END;
