V1 of this module only gathers blocking statistics (by DB object) for analysis in health checks and not for alerting 

Alerting should be added in later, but will require either:
    a. A complete rewrite of the stored procedure gathering and table storing data
    b. A second sproc and/or table to store periodic information of blocking data for comparison in the alert interval

    Probably favor B so data retention can be limited to just the monitoring period involved,
    This keeping historical reporting data separate from alerting data (due to the need for comparison)
    
    

-- BELOW THIS LINE ARE VARIOUS QUERIES FOR GETTING BASIC BLOCKING INFORMATION
-- *******************************************************************************************************


-- Pull basic blocking information if no monitoring tool is available
-- this is instance-configuration-specific - see the url

-- URL: https://social.msdn.microsoft.com/Forums/sqlserver/en-US/f9d0e4af-3e00-4114-b86a-06ead36d2400/how-to-find-history-of-blocking?forum=sqlgetstarted

select top 10 * 
from sys.dm_os_wait_stats  
order by wait_time_ms desc 

-- BETTER QUERY
-- Still not great, but gives blocking wait time per object per database
-- Secondary source: https://www.sqlservercentral.com/blogs/cached-blocking-history-with-sys-dm_db_index_operational_stats
-- These were both published 2012-03-15 by two different authors and the 'articles' are word-for-word, so they probably got it from someone/where else
-- My Google-Fu failed to return anywhere else this query is, so 

--- URL: https://www.sqlserver-dba.com/2012/03/cached-blocking-history-with-sysdm_db_index_operational_stats.html

select db_name(database_id) DB,
QUOTENAME(OBJECT_SCHEMA_NAME(object_id, database_id))
+ N'.'
+ QUOTENAME(OBJECT_NAME(object_id, database_id)) ObjDetails,
row_lock_wait_in_ms + page_lock_wait_in_ms Block_Wait_Time_in_ms
from sys.dm_db_index_operational_stats(NULL,NULL,NULL,NULL)
order by Block_Wait_Time_in_ms desc,ObjDetails desc


-- This is a third option, which is a modification of the above query:
-- url: https://dba.stackexchange.com/questions/185735/dm-db-index-operational-stats-showing-more-blocking-than-extended-event-report
-- This link is from about September 2017, so it's fair to say that the original of query #2 was a) not in English, and b) probably in/for sql 2005 or 2008

Select db_name(database_id) DB, 
   object_name(object_id) Obj, 
   row_lock_count +page_lock_count No_Of_Locks, 
   row_lock_wait_count +page_lock_wait_count No_Of_Blocks, 
   row_lock_wait_in_ms +page_lock_wait_in_ms Block_Wait_Time_in_ms, 
   index_id
From sys.dm_db_index_operational_stats(NULL,NULL,NULL,NULL) 
Order by Block_Wait_Time_in_ms desc


-- This query will return blocking information happening at the time of execution
-- Live blocking report: who is blocking whom right now

SELECT
    r.session_id AS BlockedSessionID,
    s.login_name AS BlockedLogin,
    s.host_name AS BlockedHost,
    r.status AS BlockedStatus,
    r.wait_type,
    r.wait_time / 1000.0 AS WaitTimeSeconds,
    r.wait_resource,
    r.blocking_session_id AS BlockingSessionID,
    bs.login_name AS BlockingLogin,
    bs.host_name AS BlockingHost,
    DB_NAME(r.database_id) AS DatabaseName,
    SUBSTRING(t.text, (r.statement_start_offset / 2) + 1,
        ((CASE r.statement_end_offset
          WHEN -1 THEN DATALENGTH(t.text)
          ELSE r.statement_end_offset
          END - r.statement_start_offset) / 2) + 1) AS BlockedStatement,
    bt.text AS BlockingStatement
FROM sys.dm_exec_requests AS r
INNER JOIN sys.dm_exec_sessions AS s ON r.session_id = s.session_id
LEFT JOIN sys.dm_exec_sessions AS bs ON r.blocking_session_id = bs.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) AS t
OUTER APPLY sys.dm_exec_sql_text(bs.most_recent_sql_handle) AS bt
WHERE r.blocking_session_id <> 0
ORDER BY r.wait_time DESC;


/* **************************************************************************************************************** */

Using the above, periodic checks for blocking could be done without having to leverage [sp_configure 'blocked process threshold']


-- Create Table 

USE [SQLPulse]
GO

IF OBJECT_ID('dbo.BlockingHistory', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.BlockingHistory
    (
        CaptureTime        DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
        DatabaseName       SYSNAME NULL,
        BlockedSessionID   INT NOT NULL,
        BlockingSessionID  INT NOT NULL,
        BlockedLogin       NVARCHAR(128) NULL,
        BlockingLogin      NVARCHAR(128) NULL,
        BlockedHost        NVARCHAR(128) NULL,
        BlockingHost       NVARCHAR(128) NULL,
        WaitType           NVARCHAR(60) NULL,
        WaitTimeSeconds    DECIMAL(10,2) NULL,
        WaitResource       NVARCHAR(256) NULL,
        BlockedStatement   NVARCHAR(MAX) NULL,
        BlockingStatement  NVARCHAR(MAX) NULL
    );
END
GO

-- Insert data

INSERT INTO dbo.BlockingHistory
(
    DatabaseName,
    BlockedSessionID,
    BlockingSessionID,
    BlockedLogin,
    BlockingLogin,
    BlockedHost,
    BlockingHost,
    WaitType,
    WaitTimeSeconds,
    WaitResource,
    BlockedStatement,
    BlockingStatement
)
SELECT
    DB_NAME(r.database_id) AS DatabaseName,
    r.session_id AS BlockedSessionID,
    r.blocking_session_id AS BlockingSessionID,
    s.login_name AS BlockedLogin,
    bs.login_name AS BlockingLogin,
    s.host_name AS BlockedHost,
    bs.host_name AS BlockingHost,
    r.wait_type,
    r.wait_time / 1000.0 AS WaitTimeSeconds,
    r.wait_resource,
    SUBSTRING(t.text, (r.statement_start_offset / 2) + 1,
        ((CASE r.statement_end_offset
          WHEN -1 THEN DATALENGTH(t.text)
          ELSE r.statement_end_offset END - r.statement_start_offset) / 2) + 1) AS BlockedStatement,
    bt.text AS BlockingStatement
FROM sys.dm_exec_requests AS r
INNER JOIN sys.dm_exec_sessions AS s ON r.session_id = s.session_id
LEFT JOIN sys.dm_exec_sessions AS bs ON r.blocking_session_id = bs.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) AS t
OUTER APPLY sys.dm_exec_sql_text(bs.most_recent_sql_handle) AS bt
WHERE r.blocking_session_id <> 0;


/* **************************************************************************************************************** */

That aside, using [sp_configure 'blocked process threshold'], you could detect and write items into XML

-- Enable blocked process detection
EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;
EXEC sp_configure 'blocked process threshold (s)', 10;  -- e.g., 10 seconds
RECONFIGURE;
GO

-- Create an Extended Events session to capture the reports
CREATE EVENT SESSION [BlockedProcessCapture]
ON SERVER
ADD EVENT sqlserver.blocked_process_report
ADD TARGET package0.event_file (
    SET filename = N'C:\SQLLogs\BlockedProcess.xel', max_file_size = 25, max_rollover_files = 5
)
WITH (STARTUP_STATE = ON);
GO

-- Start the session
ALTER EVENT SESSION [BlockedProcessCapture] ON SERVER STATE = START;

-- Get data out of the XML
-- NOTE: you'll need some mechanism to clear older XML or track when this info is pulled and modify the query to only pull since that time. 
-- Ultimately you'll HAVE to have an XML cleanup or rollover or something, as after a while a lot of blockign could make searching all the files for a subset would kill the server

SELECT
    event_data.value('(event/@timestamp)[1]', 'DATETIME2') AS EventTime,
    event_data.value('(event/data[@name="database_name"]/value)[1]', 'SYSNAME') AS DatabaseName,
    event_data.value('(event/data[@name="duration"]/value)[1]', 'INT')/1000 AS BlockSeconds,
    event_data.value('(event/data[@name="blocked_process"]/value/blocked-process-report/blocking-process/process/@spid)[1]', 'INT') AS BlockingSessionID,
    event_data.value('(event/data[@name="blocked_process"]/value/blocked-process-report/blocked-process/process/@spid)[1]', 'INT') AS BlockedSessionID,
    event_data
FROM sys.fn_xe_file_target_read_file('C:\SQLLogs\BlockedProcess*.xel', NULL, NULL, NULL)
CROSS APPLY (SELECT CAST(event_data AS XML)) AS tab(event_data);
