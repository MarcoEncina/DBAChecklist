USE [master]
GO


CREATE PROC [dbo].[DBAChecklist]
	@AgentJobsNumDays int=24,
	@IncludedDatabases varchar(4000)=NULL, 
	@ExcludedDatabases varchar(4000)=NULL, 
	@DBStatsPctUsedWarning int=90, 
	@DBStatsPctUsedCritical int=95,
	@FullBkpWarningDays int=1,  
	@DiffBkpWarningDays int=3, 
	@TranBkpWarningHours int=1, 
	@FreeDiskSpacePctWarning int=15, 
	@FreeDiskSpacePctCritical int=10, 
	@UptimeCritical int = 1440, 
	@UptimeWarning int = 2880, 
	@ErrorLogDays int = 1,
	@Recipients nvarchar(2000),
	@MailProfile sysname=NULL

AS

SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;



/*
	dbo.DBAChecklist v2 - 08 Apr 2014
    
	Changes in v2 - 08 Apr 2014
	 - Improved CSS to make it more readable.  Everything is now a CSS class.
	
	Changes in v1 - 20 March 2014
	 - Tidied up code, added Help file and Change list and proper documentation

	Stored Procedure explanations:

	dbo.DBAChecklist               		This Proc. Main Proc that brings all data together and emails it out 					
	dbo.DBAChecklist_FailedJobs 			Lists all failed jobs in the timeframe set by @AgentJobsNumDays
	dbo.DBAChecklist_JobStats				Lists All jobs and status data including last runtime and result
	dbo.DBAChecklist_DBFiles				Lists All DB files, filegroup, Location, Size, Free & Used Space and Growth settings
	dbo.DBAChecklist_DiskDrives 			Shows all SQL drives and space information
	dbo.DBAChecklist_Backups 				Lists Latest backup information, including times for Databases  
	dbo.DBAChecklist_DBChanges 						
	dbo.DBAChecklist_ErrorLog 				Lists out all Error log entries which meet the criteria and that were logged within the @ErrorLogDays parameters
	dbo.DBAChecklist_IndexLog 				ses Ola Hallengren''s [http://ola.hallengren.com] maintenance script to report back which indexes were re-organised and rebuilt.  If you dont use the index maintenance part of the Ola''s script then comment this call out. 

	Parameter explanations:

	@AgentJobsNumDays					24=Number of days to report failed jobs
	@IncludedDatabases 		 			Comma seperated list of databases to get filestats for. NULL=All, '' = None
	@ExcludedDatabases 					Comma seperated list of databases to get filestats for. NULL=No Exclusions
	@DBStatsPctUsedWarning				90=Warn if free space in a database file is less than this threshold (Just for database specified in @FileStatsDatabases). Shows up as Yellow
	@DBStatsPctUsedCritical				95=Warn if free space in a database file is less than this threshold (Just for database specified in @FileStatsDatabases). Shows up as Red
	@FullBkpWarningDays					1=Backup warning if no full backup for "x" days 
	@DiffBkpWarningDays 				3=Backup warning if no diff backup for "x" days
	@TranBkpWarningHours				1=Backup warning if no tran backup for "x" hours 
	@FreeDiskSpacePctWarning			15=Warn if free space is less than this threshold. Shows up as Yellow 
	@FreeDiskSpacePctCritical			10=Warn if free space is less than this threshold. Shows up as Red  
	@Uptimewarning 						2880=Warn if system uptime (in minutes) is less than this value. Use minutes 1440 = 24 hours.  Shows up as Yellow
	@UptimeCritical						1440=Critical if system uptime is less than this value. Use minutes 1440 = 24 hours. Shows up as Red 
	@ErrorLogDays						1=Number of days to report error log

	*/

DECLARE @AgentJobsHTML varchar(max)
DECLARE @AgentJobStatsHTML varchar(max)
DECLARE @FileStatsHTML varchar(max)
DECLARE @DisksHTML varchar(max)
DECLARE @BackupsHTML varchar(max)
DECLARE @DBChangesHTML varchar(max)
DECLARE @ErrorLogHTML varchar(max)
DECLARE @IndexLogHTML varchar(max)
DECLARE @HTML varchar(max)
DECLARE @Uptime varchar(max)
DECLARE @server varchar(50)

Select @server = 
CASE 
	When  @@SERVERNAME = 'P2456363\DEV' Then 'SWTORDEVDB01\DEV'
	When  @@SERVERNAME = 'P2456363\QA' Then 'SWTORDEVDB01\QA'
	When  @@SERVERNAME = 'P2456363\COMPARE' Then 'SWTORDEVDB01\COMPARE'		
	When  @@SERVERNAME = 'P2456363\VAULT' Then 'SWTORDEVDB01\VAULT'
	When  @@SERVERNAME = 'P2456352' Then 'SWTORLVDBN01'
	When  @@SERVERNAME = 'P2456360' Then 'SWTORLVREP01'		
	When  @@SERVERNAME = 'P2456360\IDERA' Then 'SWTORLVREP01\IDERA'
	When  @@SERVERNAME = 'P2456361' Then 'SWTORLVSUN01'
	When  @@SERVERNAME = 'P2445993\DEV' Then 'SWMIADRDEV01\DEV'
	When  @@SERVERNAME = 'P2445993\QA' Then 'SWMIADRDEV01\QA'
	When  @@SERVERNAME = 'P2445993\COMPARE' Then 'SWMIADRDEV01\COMPARE'
	When  @@SERVERNAME = 'P2445993\VAULT' Then 'SWMIADRDEV01\VAULT'
	When  @@SERVERNAME = 'P2456375\IDERA' Then 'SWMIADRREP01\IDERA'
	When  @@SERVERNAME = 'P2456375' Then 'SWMIADRREP01'
	When  @@SERVERNAME = 'P2445995' Then 'SWMIADRSQL01'
	When  @@SERVERNAME = 'P2456376' Then 'SWMIADRSUN01'
	When  @@SERVERNAME = 'MSSQLSERVER' Then 'SWTORLVDBC01'
ELSE  @@SERVERNAME
END

SELECT @Uptime = 
	CASE WHEN DATEDIFF(mi,create_date,GetDate()) < @UptimeCritical THEN '<span class="Critical">'
	WHEN DATEDIFF(mi,create_date,GetDate()) < @Uptimewarning THEN '<span class="Warning">'
	ELSE '<span class="Healthy">' END + 
	-- get system uptime
	COALESCE(NULLIF(CAST((DATEDIFF(mi,create_date,GetDate())/1440 ) as varchar),'0') + ' day(s), ','')
	+ COALESCE(NULLIF(CAST(((DATEDIFF(mi,create_date,GetDate())%1440)/60) as varchar),'0') + ' hour(s), ','')
	+ CAST((DATEDIFF(mi,create_date,GetDate())%60) as varchar) + 'min'
	--
	+ '</span>'
FROM sys.databases 
WHERE NAME='tempdb'

exec dbo.DBAChecklist_FailedJobs 
	@NumDays=@AgentJobsNumDays,
	@HTML=@AgentJobsHTML out


exec dbo.DBAChecklist_JobStats 
	@NumDays=@AgentJobsNumDays,
	@HTML=@AgentJobStatsHTML out

exec dbo.DBAChecklist_DBFiles 
	@IncludeDBs=@IncludedDatabases,
	@ExcludeDBs=@ExcludedDatabases,
	@WarningThresholdPCT=@DBStatsPctUsedWarning,
	@CriticalThresholdPCT=@DBStatsPctUsedCritical,
	@HTML=@FileStatsHTML out

exec dbo.DBAChecklist_DiskDrives 
	@PCTFreeWarningThreshold=@FreeDiskSpacePctWarning,
	@PCTFreeCriticalThreshold=@FreeDiskSpacePctCritical,
	@HTML=@DisksHTML out

exec dbo.DBAChecklist_Backups 
	@DiffBkpWarningDays=@DiffBkpWarningDays,
	@FullBkpWarningDays=@FullBkpWarningDays,
	@TranBkpWarningHours=@FullBkpWarningDays,
	@HTML=@BackupsHTML OUT

--exec dbo.DBAChecklist_DBChanges 
--	@HTML=@DBChangesHTML OUT

exec dbo.DBAChecklist_ErrorLog 
	@NumDays=@ErrorLogDays,
	@HTML=@ErrorLogHTML OUT

exec dbo.DBAChecklist_IndexLog 
	@HTML=@IndexLogHTML OUT

SET @HTML = 
'<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN">
<html>
<head>
<style type="text/css">
.DBAChecklist {
	color:#000000;
	font:11px tahoma,arial,sans-serif;
	margin:0px;
	padding:0px;
}
.DBAChecklist table {
font:11px tahoma,arial,sans-serif;
}
.DBAChecklist th {
color:#FFFFFF;
font:bold 11px tahoma,arial,sans-serif;
background-color:#BB2325;
padding-left:5px;
padding-right:5px;
}
.DBAChecklist tr:nth-child(odd) { 
background-color:#EEE; 
}
.DBAChecklist td {
color:#000000;
font:11px tahoma,arial,sans-serif;
border:1px solid #DCDCDC;
border-collapse:collapse;
padding: 5px 10px;
}
.DBAChecklist .Warning {
background-color:#FFFF00; 
color:#2E2E2E;
}
.DBAChecklist .Critical {
background-color:#FF0000;
color:#FFFFFF;
}
.DBAChecklist .Healthy {
background-color:#458B00;
color:#FFFFFF;
}
.DBAChecklist h1 {
color:#FFFFFF;
font:bold 16pt arial,sans-serif;
background-color:#6C6F70;
text-align:center;
}
.DBAChecklist h2 {
color:#BB2325;
font:bold 14pt arial,sans-serif;
}
.DBAChecklist h3 {
color:#204c7d;
font:bold 12pt arial,sans-serif;
}


</style>
</head>
<body class="DBAChecklist" >
<h1>DBA Daily Checklist Report for ' + @server + ' - ' + convert(varchar(25), getdate(), 120) + '</h1>
	<h2>General Health</h2>
	<b>System Uptime (SQL Server): ' + @Uptime + '</b><br/>
	<b>Version: </b>' + CAST(SERVERPROPERTY('productversion') as nvarchar(100)) + ' ' + CAST(SERVERPROPERTY ('productlevel') as nvarchar(100)) + ' ' + CAST(SERVERPROPERTY ('edition') as nvarchar(100)) 
+ COALESCE(@DisksHTML,'<div class="Critical">Error collecting Disk Info</div>')
+ COALESCE(@FileStatsHTML,'<div class="Critical">Error collecting DB Stats Info</div>')
+ COALESCE(@BackupsHTML,'<div class="Critical">Error collecting Backup Info</div>')
+ COALESCE(@AgentJobsHTML,'<div class="Critical">Error collecting Jobs Info</div>')
+ COALESCE(@DBChangesHTML,'<div class="Critical">Error collecting DB Changes</div>')
+ COALESCE(@AgentJobStatsHTML,'<div class="Critical">Error collecting  Jobs Stats</div>')
+ COALESCE(@ErrorLogHTML,'<div class="Critical">Error collecting Error Log Details</div>')
+ COALESCE(@IndexLogHTML,'<div class="Critical">Error collecting Index Log Details</div>')

+ '</body></html>'

declare @subject varchar(50)
set @subject = 'Daily Checklist Report (' + @server + ')'


EXEC msdb.dbo.sp_send_dbmail
	@query_result_header = 0,
	@query_no_truncate = 1,
	@query_result_width=32767,
	@recipients =@Recipients,
	@body = @HTML,
	@body_format ='HTML',
	@subject = @subject,
	@profile_name = @MailProfile


GO

