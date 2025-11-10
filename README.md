# SQLPulse
TL;DR: SQLPulse is a lightweight, free, self-hosted monitoring framework for Microsoft SQL Server and Azure SQL Managed Instance. It’s built for admins and DBAs who need visibility without expensive tools, using only native SQL features to collect key performance data, generate readable reports, and maintain long-term archives.

## What this software is not

It's not a replacement for commercial software. It's designed to be "good enough" to get you by until it's not needed. This could be because it's a lab box, a temp server, or - like me in the story below - you have to have some way to justify the budget on a commercial solution. That said, it's all internally documented and runs as simply as I could think of to make it accessible to the widest audience possible. 

Constructive criticism is welcome. If you think it could be better, tell me how — even if your feedback is sharp ("I hate your guts and would like nothing better than to see you step on Legos barefoot"). Every suggestion helps improve it for others. 

## Verbose
I first became a DBA because the old one left just as I was merged in with the main infrastructure team. The outgoing DBA gave me a server list, one page of hand-written notes, and a folder with about 2 dozen .sql files. There were about 30 SQL instances and the only tools I had were SSMS and any scripts I might be able to find online.

Over the next few years, as the company’s IT consolidation picked up steam, the server scope began to rise dramatically, with new installations quickly eclipsing the existing servers. However, the tools available to me did not change, and since everything was working fine as far as the various business units were concerned, management felt the situation was good enough. Then, the company went all-in on SharePoint. It was part of the first wave of SQL servers large and important enough to warrant its own cluster, yet  despite being the least business-critical installation, it was solely responsible for the obtaining of my first dedicated SQL monitoring tool: Spotlight on SQL Server Enterprise.

Until that time, the basic performance metric was: "The box is delivering everything we need by the time we need it." That was good for the business units that were running data analysis, reports from the mainframe, back-ends for interactive financial apps, etc., but SharePoint had something that none of the other use cases did: direct user visibility. And the users were complaining loudly enough to make it clear the system there was a problem. Unfortunately, I didn't have an answer; the best I could come up with was that SQL was deadlocking under load.

 This is the point where an experienced DBA might say "You could have done [x]" or "Just look at [y]” and probably be right. However, I was not an experienced DBA. I was a fair network engineer. I was a very good server administrator. But I got the SQL job based solely on using it as a back end for a web application I'd written almost 5 years prior. Besides, being the DBA was not my only job; I was still doing my share of other admin work in the domain, IIS, and Exchange with the rest of the team. 

I installed the trial version of Spotlight and within 24 hours I had my answer: the deadlocks were caused by insufficient RAM. I swiped enough sticks from a lab box to double SQL memory, and both the deadlocks and user complaints disappeared literally overnight. That led me to my first business case, which was accepted by management and within 2 months I had my monitoring software (getting the box to run it on is a story for another day). 
 I went on to become a database consultant, and I’ve met a lot of other accidental DBAs who just can’t get proper monitoring software, from smaller companies that just can’t afford it to gargantuan companies that can’t justify enough licenses fees for non-critical systems. SQLPulse is my response to those scenarios: a basic, no-frills, single-instance monitoring solution that can run directly on the server itself. 
SQLPulse has three overarching goals:
 
1.	Easy installation - use it as-is for "good enough" results, or follow the clear and SHORT instructions on customizing the framework to fit around your business cycle
2.	Reports that are tech AND manager friendly. The data includes basic recommendations and remediations that can be implemented or used to justify the budget for commercial monitoring software
3.	Historical archives - the reports run monthly and are archived for 5 years by default. This can give you a fast view of where the server has been and where it's going for future planning
It’s my sincerest hope that this benefits the greater SQL community. 
Happy monitoring!


