V1 of this module gathers data in two ways:

	1) It gets a snapshot of blocked sessions
	2) It calculates the cumulative blocking time, since engine startup, per database

The intention is to combine this with the relevant Wait data gathered by the WAITS module.

Unlike my initial README comments, these data sets are actually in a good position for alerting when that time comes, 
either via crossing a % processor time threshold from the cumulative stats, by individual blockign time from the sessions snapshots,
and/or by the total Wait times in the blocking category, either by type or cumulative time.

It may also be beneficial to have a Snapshots table as the WAITS module does for comparing deltas over time. 
    
    

-- BELOW THIS LINE ARE VARIOUS QUERIES FOR GETTING BASIC BLOCKING INFORMATION
-- *******************************************************************************************************

This data has been removed from here as new queries were developed during the module build.

However, a more comprehensive sessions query should be developed that could be extracted directly from the sproc and run manually
to assist in manual torubleshooting
