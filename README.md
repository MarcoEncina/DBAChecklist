##Introduction

DBA Checklist is a set of SQL Stored Procedures I have built based around automating a daily check of SQL servers. It is not a comprehensive monitoring solution. However, it is a basic set of checks designed to give you relevant information on each server at a glance.

At its core, this checklist reports on the following:

- Backups
- SQL Server jobs
- Database files: Free space in the physical files
- SQL Server error log

In addition, if you use Ola Hallengren's SQL [maintenance script][2], it will report on the index updates done in the last 24 hours.

Like most DBAs, I started doing these checks on a manaual basis.  It works to begin with, but then you get distracted or forget to check the servers every day.  Automating this process means you always get the data to your inbox, and being proactive means you can fix problems before the users notice.

##Installation Instructions

Create a database for DBA related tasks if one doesn't already exist.


- Install DBA Checks stored procedures from [GitHub][1]
- Make sure Database Mail is configured.  This is needed for the email to be sent :-)
- Create a SQL Server Agent Job to run the dbo.DBAChecklist stored procedure.

##Running the report

The DBA Checks report is run by executing the dbo.DBAChecklist stored procedure.  This stored procedure takes a number of parameters, but only one is required:

```sql
exec dbo.DBAChecklist @recipients='test@test.com'
```

The code below shows a call to the DBAChecks stored procedure with all parameters specified:

```sql
EXEC dbo.DBAChecklist @AgentJobsNumDays=3,
@FileStatsIncludedDatabases=NULL, 
@FileStatsExcludedDatabases=NULL, 
@FileStatsPctUsedWarning=90, 
@FileStatsPctUsedCritical=95, 
@DiffWarningThresholdDays=3, 
@FullWarningThresholdDays=7, 
@TranWarningThresholdHours=4, 
@FreeDiskSpacePercentWarningThreshold=15, 
@FreeDiskSpacePercentCriticalThreshold=10, 
@UptimeCritical=1440 ,
@UptimeWarning=2880, 
@ErrorLogDays=3,
@Recipients='test@test.com',
@MailProfile=NULL
```



##Stored Procedure & Parameter Explanations

The list of Stored Procedures:

- dbo.DBAChecklist: This Proc. Main Proc that brings all data together and emails it out.
- dbo.DBAChecklist_FailedJobs: Lists all failed jobs in the timeframe set by @AgentJobsNumDays
- dbo.DBAChecklist_JobStats: Lists All jobs and status data including last runtime and result
- dbo.DBAChecklist_DBFiles: Lists All DB files, filegroup, Location, Size, Free & Used Space and Growth settings
- dbo.DBAChecklist_DiskDrives: Shows all SQL drives and space information
- dbo.DBAChecklist_Backups: Lists Latest backup information, including times for Databases  
- dbo.DBAChecklist_DBChanges 						
- dbo.DBAChecklist_ErrorLog: Lists out all Error log entries which meet the criteria and that were logged within the @ErrorLogDays parameters
- dbo.DBAChecklist_IndexLog: Uses Ola Hallengren's [maintenance script][2] to report back which indexes were re-organised and rebuilt.  If you dont use the index maintenance part of the Ola''s script then comment this call out. 

A full explanation of these parameters:

- @AgentJobsNumDays: Number of days to report failed jobs
- @IncludedDatabases: Comma seperated list of databases to get filestats for. NULL=All, '' = None
- @ExcludedDatabases: Comma seperated list of databases to get filestats for. NULL=No Exclusions
- @DBStatsPctUsedWarning: Warn if free space in a database file is less than this threshold (Just for database specified in @FileStatsDatabases). Shows up as Yellow
- @DBStatsPctUsedCritical: Warn if free space in a database file is less than this threshold (Just for database specified in @FileStatsDatabases). Shows up as Red
- @FullBkpWarningDays: Backup warning if no full backup for "x" days 
- @DiffBkpWarningDays: Backup warning if no diff backup for "x" days
- @TranBkpWarningHours: Backup warning if no tran backup for "x" hours 
- @FreeDiskSpacePctWarning: Warn if free space is less than this threshold. Shows up as Yellow 
- @FreeDiskSpacePctCritical: Warn if free space is less than this threshold. Shows up as Red  
- @Uptimewarning: Warn if system uptime (in minutes) is less than this value. Use minutes 1440 = 24 hours.  Shows up as Yellow
- @UptimeCritical: Critical if system uptime is less than this value. Use minutes 1440 = 24 hours. Shows up as Red 
- @ErrorLogDays: Number of days to report error log



[1]: https://github.com/mealies/DBAChecklist       	"GitHub"
[2]: http://ola.hallengren.com  					"maintenance script"