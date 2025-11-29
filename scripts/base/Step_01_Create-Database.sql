/* ****************************************************************************************************

Source: SQL Pulse: Create Database SQLPulse
Build: 1.0
Build Date: 2025-11-29

The purpose of this script is to create the primary database for SQL Pulse, named SQLPulse.

It will throw a shiny red text warning if the database already exists, and will not make any changes
to the existing database.

It's no frills and uses the default paths to create the database and log files.

Note: If the default database paths have not been modified, this may end up with the database files
on something like C:, if the installation was done by accepting the default values in the 
wizard - this is extremely common, so a future feature might be to check the path(s) in 
use by the largest database and locate the SQLPulse files there instead, but at this time
I am not trying to be creative.

The script does specify grwoth in 128MB increments. 

NOTE 2: Both VB Code and SSMS will provide visual cues that the THROW command is in error, but it is not.

**************************************************************************************************** */

USE [master]
GO

IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = N'SQLPulse')
    BEGIN

        CREATE DATABASE SQLPulse;
       
        ALTER DATABASE [SQLPulse] MODIFY FILE ( NAME = N'SQLPulse', SIZE = 262144KB , FILEGROWTH = 131072KB );
        
        ALTER DATABASE [SQLPulse] MODIFY FILE ( NAME = N'SQLPulse_log', SIZE = 262144KB , FILEGROWTH = 131072KB );
   
   END

ELSE    

        BEGIN
            THROW 51000, '**WARNING** Database [SQLPulse] already exists. No changes made.', 1;
        END

