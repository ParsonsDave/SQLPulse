USE [SQLPulse]
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO



CREATE PROCEDURE [Pulse].[Module_Core_GetServerProperties]
	
AS

BEGIN

/* *********************************************************************************

Source: SQLPulse: Get Server Properties
Build: 1.0
Build Date: 2026-05-02

NOTE: The below SERVERPROPERTY list is for SQL Server 2025 and was verified 2026-05-02

This sproc (re)creates a global temp table to hold the values of the SERVERPROPERTY function
This is partially for reporting, partially to keep from having to recreate the wheel any time I 
need to get information.

NOTE: The global temp table name is simply ##ServerProperties

It performs the following activities:

   1) Drop the global temp table if it already exists
   2) Create the global temp table 
   3) Parse SERVERPROPERTY and insert the values into the temp table
   4) Insert @@SERVERNAME into the global temp table
   5) SELECT for use if you pull this code out to execute manually

********************************************************************************* */

-- 1) Drop the global temp table if it already exists

	IF OBJECT_ID('tempdb..##ServerProperties') IS NOT NULL
    DROP TABLE #ServerProperties;

-- 2) Create the global temp table 

	CREATE TABLE ##ServerProperties(
		[PropertyName] nvarchar(128) NULL,
		[PropertyValue] nvarchar(128) NULL,
		[Description] nvarchar(255) NULL
		)


-- 3) Parse SERVERPROPERTY and insert the values into the temp table

	INSERT INTO ##ServerProperties (PropertyName, PropertyValue, Description)

		SELECT 
			PropertyName,
			PropertyValue       = CONVERT(nvarchar(128), PropertyValue),
			Description
	FROM (

		VALUES
			('BuildClrVersion'
				, SERVERPROPERTY('BuildClrVersion')
				, 'Version of the Microsoft .NET Framework common language runtime (CLR) that was used while building the instance of SQL Server.'), 
			
			('Collation'
				, SERVERPROPERTY('Collation')
				, 'Name of the default collation for the server.'), 
			
			('CollationID'
				, SERVERPROPERTY('CollationID')
				, 'ID of the SQL Server collation.'), 
			
			('ComparisonStyle'
				, SERVERPROPERTY('ComparisonStyle')
				, 'Windows comparison style of the collation.'), 
			
			('ComputerNamePhysicalNetBIOS'
				, SERVERPROPERTY('ComputerNamePhysicalNetBIOS')
				, 'NetBIOS name of the local computer on which the instance of SQL Server is currently running. [Host Name]'), 
			
			('Edition'
				, SERVERPROPERTY('Edition')
				, 'Installed product edition of the instance of SQL Server.'), 
			
			('EditionID'
				, SERVERPROPERTY('EditionID')
				, 'This is a code that can be used to pull more information on features and limitations.'), 
			
			('EngineEdition'
				, SERVERPROPERTY('EngineEdition')
				, 'Database Engine edition of the instance of SQL Server installed on the server. [The order is not the same as the EditionID, above]'), 
			
			('FilestreamConfiguredLevel'
				, SERVERPROPERTY('FilestreamConfiguredLevel')
				, 'The configured level of FILESTREAM access. 0/Disabled, 1-3/Various Enabled'), 
			
			('FilestreamEffectiveLevel'
				, SERVERPROPERTY('FilestreamEffectiveLevel')
				, 'The effective level of FILESTREAM access. This value can be different than the FilestreamConfiguredLevel if the level has changed and either an instance restart or a computer restart is pending.'), 
			
			('FilestreamShareName'
				, SERVERPROPERTY('FilestreamShareName')
				, 'The name of the share used by FILESTREAM.'), 
			
			('HadrManagerStatus'
				, SERVERPROPERTY('HadrManagerStatus')
				, 'v2012+ ; Indicates whether the Always On availability groups manager has started. 0/Not, 1/Started, 2/Failed'), 
			
			('InstanceDefaultBackupPath'
				, SERVERPROPERTY('InstanceDefaultBackupPath')
				, 'v2019+ ; Name of the default path to the instance backup files.'), 
			
			('InstanceDefaultDataPath'
				, SERVERPROPERTY('InstanceDefaultDataPath')
				, 'v2012+ ; Name of the default path to the instance data files.'), 
			
			('InstanceDefaultLogPath'
				, SERVERPROPERTY('InstanceDefaultLogPath')
				, 'v2012+ ; Name of the default path to the instance log files.'), 
			
			('InstanceName'
				,  SERVERPROPERTY('InstanceName')
				, 'Name of the instance to which the user is connected. Returns NULL if default instance.'), 
			
			('IsAdvancedAnalyticsInstalled'
				, SERVERPROPERTY('IsAdvancedAnalyticsInstalled')
				, 'Returns 1 if the Advanced Analytics feature was installed during setup; 0 if Advanced Analytics was not installed.'), 
			
			('IsBigDataCluster'
				, SERVERPROPERTY('IsBigDataCluster')
				, 'v2019 CU4+; Returns 1 if the instance is SQL Server Big Data Cluster; 0 if not.'), 
			
			('IsClustered'
				, SERVERPROPERTY('IsClustered')
				, 'Server instance is configured in a failover cluster. 0/No, 1/Clustered'), 
			
			('IsExternalAuthenticationOnly'
				, SERVERPROPERTY('IsExternalAuthenticationOnly')
				, 'Azure SQL Only ; Returns whether Microsoft Entra-only authentication is enabled. 0/Disabled, 1/Enabled'), 
			
			('IsExternalGovernanceEnabled'
				, SERVERPROPERTY('IsExternalGovernanceEnabled')
				, 'v2022+ ; Returns whether Microsoft Purview access policies are enabled. 0/Disabled, 1/Enabled'), 
			
			('IsFullTextInstalled'
				, SERVERPROPERTY('IsFullTextInstalled')
				, 'The full-text and semantic indexing components are installed on the current instance of SQL Server. 0/Not Installed, 1/Installed'), 
			
			('IsHadrEnabled'
				, SERVERPROPERTY('IsHadrEnabled')
				, 'v2012+ ; Always On availability groups is enabled on this server instance. 0/Disabled, 1/Enabled'), 
			
			('IsIntegratedSecurityOnly'
				, SERVERPROPERTY('IsIntegratedSecurityOnly')
				, 'Server is in integrated security mode. 0/Mixed, 1/Integrated-Only'), 
			
			('IsLocalDB'
				, SERVERPROPERTY('IsLocalDB')
				, 'v2012+ ; Server is an instance of SQL Server Express LocalDB.'), 
			
			('IsPolyBaseInstalled'
				, SERVERPROPERTY('IsPolyBaseInstalled')
				, 'v2016+ ; Returns whether the server instance has the PolyBase feature installed. 0/No, 1/Yes'), 
			
			('IsServerSuspendedForSnapshotBackup'
				, SERVERPROPERTY('IsServerSuspendedForSnapshotBackup')
				, 'Server is in suspend mode and requires server level thaw. 0/Not Suspended, 1/Suspended'), 
			
			('IsSingleUser'
				, SERVERPROPERTY('IsSingleUser')
				, 'Server is in single-user mode. 0/Multi, 1/Single'), 
			
			('IsTempDbMetadataMemoryOptimized'
				, SERVERPROPERTY('IsTempDbMetadataMemoryOptimized')
				, 'v2019+ ; Returns 1 if tempdb has been enabled to use memory-optimized tables for metadata; 0 if tempdb is using regular, disk-based tables for metadata. '), 
			
			('IsXTPSupported'
				, SERVERPROPERTY('IsXTPSupported')
				, 'v2014+ ; Server supports In-Memory OLTP. 0/No, 1/Yes'), 
			
			('LCID'
				, SERVERPROPERTY('LCID')
				, 'Windows locale identifier (LCID) of the collation.'), 
			
			('LicenseType'
				, SERVERPROPERTY('LicenseType')
				, 'Unused. License information is not preserved or maintained by the SQL Server product. Always returns DISABLED.'), 
			
			('MachineName'
				, SERVERPROPERTY('MachineName')
				, 'Windows computer name on which the server instance is running. For a clustered instance, an instance of SQL Server running on a virtual server on Microsoft Cluster Service, it returns the name of the virtual server.'), 
			('NumLicenses'
				, SERVERPROPERTY('NumLicenses')
				, 'Unused. License information is not preserved or maintained by the SQL Server product. Always returns NULL.'), 
			
			('PathSeparator'
				, SERVERPROPERTY('PathSeparator')
				, 'v2017+ ; Returns \ on Windows and / on Linux'), 
			
			('ProcessID'
				, SERVERPROPERTY('ProcessID')
				, 'Process ID of the SQL Server service. ProcessID is useful in identifying which Sqlservr.exe belongs to this instance.'), 
			
			('ProductBuild'
				, SERVERPROPERTY('ProductBuild')
				, 'v2014+ ; The build number.'), 
			
			('ProductBuildType'
				, SERVERPROPERTY('ProductBuildType')
				, 'v2012+ ; Type of build of the current build. OD = On Demand release a specific customer. GDR = General Distribution Release released through Windows Update.'), 
			
			('ProductLevel'
				, SERVERPROPERTY('ProductLevel')
				, 'Level of the version of the instance of SQL Server. RTM/Original Release, SP(n)/Service Pack Version, CTP(n)/Community Technology Preview version'), 
			
			('ProductMajorVersion'
				, SERVERPROPERTY('ProductMajorVersion')
				, 'v2012+ ; The major version.'), 
			
			('ProductMinorVersion'
				, SERVERPROPERTY('ProductMinorVersion')
				, 'v2012+ ; The minor version.'), 
			
			('ProductUpdateLevel'
				, SERVERPROPERTY('ProductUpdateLevel')
				, 'v2012+ ; Update level of the current build. CU indicates a cumulative update. CU(n)/Cumulative Update or NULL'), 
			
			('ProductUpdateReference'
				, SERVERPROPERTY('ProductUpdateReference')
				, 'v2012+ ; KB article for that release.'), 
			
			('ProductUpdateType'
				, SERVERPROPERTY('ProductUpdateType')
				, 'Azure SQL Only ; Update cadence the instance follows. Corresponds to the Azure SQL Managed Instance update policy. CU/Cumulative Updates, Continuous/Microsoft-Driven'), 
			
			('ProductVersion'
				, SERVERPROPERTY('ProductVersion')
				, 'Version of the instance of SQL Server, in the form of major.minor.build.revision.'), 
			
			('ResourceLastUpdateDateTime'
				, SERVERPROPERTY('ResourceLastUpdateDateTime')
				, 'Returns the date and time that the Resource database was last updated.'), 
			
			('ResourceVersion'
				, SERVERPROPERTY('ResourceVersion')
				, 'Returns the version Resource database.'), 
			
			('ServerName'
				, SERVERPROPERTY('ServerName')
				, 'Both the Windows server and instance information associated with a specified instance of SQL Server. ie: SERVER\INSTANCE'), 
			
			('SqlCharSet'
				, SERVERPROPERTY('SqlCharSet')
				, 'The SQL character set ID from the collation ID.'), 
			
			('SqlCharSetName'
				, SERVERPROPERTY('SqlCharSetName')
				, 'The SQL character set name from the collation.'), 
			
			('SqlSortOrder'
				, SERVERPROPERTY('SqlSortOrder')
				, 'The SQL sort order ID from the collation'), 
			
			('SqlSortOrderName'
				, SERVERPROPERTY('SqlSortOrderName')
				, 'The SQL sort order name from the collation.'), 
			
			('SuspendedDatabaseCount'
				, SERVERPROPERTY('SuspendedDatabaseCount')
				, 'The number of suspended databases on the server.')
			
			)
			
			AS ServerProperties (PropertyName, PropertyValue, Description);
	

-- 4) Insert @@SERVERNAME into the global temp table

	INSERT INTO ##ServerProperties (PropertyName, PropertyValue, Description)
			VALUES
				('InternalSQLName', (SELECT @@SERVERNAME), 'This is the name SQL server has registered internally. If it is different than the OS hostname, this means the server was renamed in the past and SQL was not updated properly.')


-- 5) SELECT for use if you pull this code out to execute manually

	SELECT * FROM ##ServerProperties

END
GO


