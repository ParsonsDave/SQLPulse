The disk monitoring in v1 is just querying sys.dm_io_virtual_file_stats and archiving the information; the intent is to group numbers in between reboots and building out some stats:

    • Average read/write during the sample period
    • Highest read/write during sample period

These may also be averaged out over a given month (or whatever overlap in reboot periods covers a given month)

NOTE -- now that I'm thinking about it, when a monthly report is generated, a last set of disk counters should be obtained on the spot (into a temp table, to keep data clean) to ensure more accurate results

!!! Missing in V1 at this time is the disk space monitoring script. !!!

In V2, files with high IO should also be matched with any IO warnings in the SQL logs
Also in v2, examine how mount point files report into sys.dm_io_virtual_file_stats; if it just reports the mounted path, then a lookup against the disk types table needs to be done


Theorycrafting:

Traditionally, read should be <= 10ms and writes should be <=20ms. In my experience, this ideal holds up pretty well even today. However, in practical terms, the counters from sys.dm_io_virtual_file_stats are averaged out and can be seriously skewed by huge latency bursts - to the point where I've seen counters report at 6 SECONDS when sample over a month (specifically, when the server has been continuously up a full calendar month or longer) , even though the busy period was 1-2 hours per night. To get around this, I generally consider values double the ideal (10ms read/20ms write) as functionally acceptable, so long as work is being completed in a timely fashion - this also applies to all-flash storage systems. Roughly speaking, I ballpark latency as such:

1x ideal = 'no significant disk latency'
2x ideal = 'possibly latency, will monitor'
3x ideal = 'minor latency'
4x ideal = 'low latency'
5x ideal = 'significant latency'
6x + = If a client isn't already complaining, then get a perfmon trace going to see when the problem is happening and how long it lasts.

-- NOTES ON HOW TO USE THIS
-- The query results are an aggregate SINCE THE SERVER START and can be seriously skewed by startup processes, ESPECIALLY tempdb creation (tempdb is recreated every time the database engine starts)
-- This means that you need to know how long the server has been up 
-- Further, these numbers should not be absolutes, but relative. Compare them with another available monitoring tool if possible and treat that tool as more reliable
-- IF YOU DO NOT HAVE MONITORING TOOL NUMBERS, then compare the results against other files on the same disk. For example, if 10 databases are on D: and 9 of them show a read latency of "7" and one shows a read latency of "30", then the D: disk does not have a latency issue, but rather the file(s) for that particular database are more heavily used.
-- TempDB in particular can be massively skewed by the file creation and growth at server startup. (it is worth noting twice)