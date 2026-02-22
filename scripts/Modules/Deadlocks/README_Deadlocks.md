v1.x for SQL Pulse

Deadlock monitoring in this version of Pulse is a tracked metric, not a diagnostic tool. As a consultant, I actually see very few environments where deadlocks are causing a user-visible issue, whether a server is deadlocking dozens of times per day or just once per quarter. This seems to be largely down to application code, with most vendors just willing to accept deadlock spam and opting instead to code procedures for recovery/retry rather than rewriting their process to not deadlock in the first place.

If deadlocks ARE causing issues for users or an application, it's likely that it will build enough political capital for either a proper monitoring solution or a consultant engagement for evaluation. This is exactly my own experience when I first became a DBA and had no monitoring tools and was the exact impetus that led to me being able to get a professional monitoring system for the SQL environment.

From this perspective, tracking deadlock frequency and associated times should give enough information to be useful in a monthly health report. It should be menitoned elsewhere, but among the specific goals for this project is the ability to run as-is without requiring elevated permissions, special accounts, or adding anything not provided by the tool code itself, including and *especially* hardware resources. If you, the end user, are having issues directly caused by deadlocking, Pulse can help once it has enough data for proper reporting, it is not an immidiate diagnostic tool. If you have an active performance problem, I cannot recommend strongly enough that you get a professional engagement started, whether that's an existing application vendor or you find an external partner. 

In any case, in order to minimize what Pulse needs to do with your server, deadlock tracking in this version is an incrementing counter based around data found in sys.dm_os_performance_counters; essentially, keep track of the counter, the difference between the current and previous values, and the data dates. This is focused on the reporting side of pulse via being able to track the changes in deadlock frequency over time, but it can still be used for alerting based on either flat number over time or bursts in a configured time frame. 

Unlike other data collection areas, I don't have any firm plans for expanding deadlocking. If feedback suggests more would benefit the community, it will require Pulse to make additional configuration to the SQL instance just to monitor, let alone for any sort of detailed reporting and/or diagnostics - and, more importantly, it will require more overhead processing and disk space for the extended events.

!! BONUS NOTE FOR ME !!!

There is currently no cleanup process for the data in the table [Deadlocks_Counter] ; this will need to be addressed during the reporting process at the very least
