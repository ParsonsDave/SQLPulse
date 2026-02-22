-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

NOTE - The below is incomplete. It is a copy of the CPU readme and is a placeholder

The data gathering is done by the stored procedure [dbo].[Module_WAITS_CollectData]:

    1) Get the last server restart (EVERY sproc does this when it runs)
    2) Put the CPU utilization values for the past 4 hours of data from sys.dm_os_ring_buffers (which returns the utilization values for each minute) into a temp table
    3) Put all non-duplicate values into the table [dbo].[CPU_Data]

This is all extremely straightforward - it is simply a large table that contains CPU counters. The actual columns are:

    • ID (int, primary key)
    • EventTime (datetime) ; this is exact time the measurement is recorded for
    • SqlService (int) ; the numeric value of the SQL service CPU utilization
    • IdleProcess (int) ; the numeric value of the idle process utilization
    • NonSqlProcess; the numeric value of CPU utilization of all non-sql threads

These are all for mathematical manipulation. All columns except ID can take NULLs.

NOTE: It is possible for the table to be missing values. This can occur because something was offline long enough for the data to not have been recorded. 

To-Do for newer versions and/or reporting:

    1) Change the table name to get rid of the 'tbl' prefix; this is to help the SQL sort algorithms work less; this will also require the sproc to be updated
    2) Decide which calculations will be part of the monthly health check; possible candidates are:
        a. Average CPU utilization
        b. Average of above-average use
        c. Top 10% utilization
        d. Determine at what % utilization that non-SQL processes are a problem
    3) Find a way to calculate the work day of the server - the period where the most processing is being done. This would allow far better recommendations for the server specs
    4) Determine if the server is a VM; if so
        a. Pull the Ready stat to see if the host is under a significant load
    
    
