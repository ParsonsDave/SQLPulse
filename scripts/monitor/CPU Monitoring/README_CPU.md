The default job for this operation is called [SQLPulse - GetCPUUtilization]
    • The job runs every 3 hours by default. This can be modified to any value of 4 hours or less [the constraint is how much history SQL keeps, which you cannot change]
    • The job only has one step: run the stored procedure [SQLPulse].[dbo].[GetCPUUtilization]

-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

The data gathering is done by the stored procedure [dbo].[GetCPUUtilization]:

    1) Get the last server restart (EVERY sproc does this when it runs)
    2) Put the CPU utilization values for the past 4 hours of data from sys.dm_os_ring_buffers (which returns the utilization values for each minute) into a temp table
    3) Put all non-duplicate values into the table [dbo].[tblCPUUtilization]

This is all extremely straightforward - it is simply a large table that contains CPU counters. The actual columns are:

    • ID (int, primary key)
    • EventTime (datetime) ; this is exact time the measurement is recorded for
    • SqlService (int) ; the numeric value of the SQL service CPU utilization
    • IdleProcess (int) ; the numeric value of the idle process utilization
    • NonSqlProcess; the numeric value of CPU utilization of all non-sql threads

These are all for mathematical manipulation. All columns except ID can take NULLs.

NOTE: It is possible for the table to be missing values. This can occur because something was offline long enough for the data to not have been recorded. This is the reason the default run time of the job is 3 hours and not 4 - the test VM being off or restarted caused gaps in the data.

To-Do for version 1:

    1) Change the table name to get rid of the 'tbl' prefix; this is to help the SQL sort algorithms work less; this will also require the sproc to be updated
    2) Decide which calculations will be part of the monthly health check; possible candidates are:
        a. Average CPU utilization
        b. Average of above-average use
        c. Top 10% utilization
        d. Determine at what % utilization that non-SQL processes are a problem

To-Do for Version 2:
    1) Find a way to calculate the work day of the server - the period where the most processing is being done. This would allow far better recommendations for the server specs
    2) Determine if the server is a VM; if so
        a. Pull the Ready stat to see if the host is under a significant load
    
    
