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


SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO



CREATE PROC [dbo].[DBAChecklist_Backups]
	@HTML varchar(max) OUT,
	@FullBkpWarningDays int,
	@DiffBkpWarningDays int,
	@TranBkpWarningHours int

AS
SET NOCOUNT ON

declare @Server varchar(40)
set @server = CONVERT(varchar(35), SERVERPROPERTY('machinename'))+ COALESCE('\'+ CONVERT(varchar(35), SERVERPROPERTY('instancename')),'')

DECLARE @backuplog TABLE(
	DBServer sysname,
	DBName sysname,
	LastFullBackup datetime,
	LastDiffBackup datetime,
	LastTranBackup datetime,
	DiffDays int,
	FullDays int,
	TranHours int
)

INSERT INTO @backuplog
SELECT fullrec.server_name [DBServer],
	 fullrec.database_name, 
	 fullrec.backup_finish_date LastFullBackup,
	 diffrec.backup_finish_date LastDiffBackup,
	 tranrec.backup_finish_date LastTranBackup,
	 datediff(dd,diffrec.backup_finish_date,getdate()) DiffDays,
	 datediff(dd,fullrec.backup_finish_date,getdate()) FullDays,
	 datediff(hh,tranrec.backup_finish_date,getdate()) TranHours
FROM msdb..backupset as fullrec
left outer join msdb..backupset as tranrec 
	on tranrec.database_name = fullrec.database_name
			and tranrec.server_name = fullrec.server_name
			and tranrec.type = 'L'
			and tranrec.backup_finish_date =
			  ((select max(backup_finish_date) 
				  from msdb..backupset b2 
				 where b2.database_name = fullrec.database_name
				   and b2.server_name = fullrec.server_name 
				   and b2.type = 'L'))
left outer join msdb..backupset as diffrec
	on diffrec.database_name = fullrec.database_name
		and diffrec.server_name = fullrec.server_name
		and diffrec.type = 'I'
		and diffrec.backup_finish_date =
		  ((select max(backup_finish_date) 
			  from msdb..backupset b2 
			where b2.database_name = fullrec.database_name 
			   and b2.server_name = fullrec.server_name 
			   and b2.type = 'I'))
where fullrec.type = 'D' -- full backups only
	and fullrec.backup_finish_date = 
	   (select max(backup_finish_date) 
		  from msdb..backupset b2 
		 where b2.database_name = fullrec.database_name 
		   and b2.server_name = fullrec.server_name 
		   and b2.type = 'D')
	and fullrec.database_name in (select name from master..sysdatabases) 
	and fullrec.database_name <> 'tempdb'
Union all
-- never backed up
select @server
		,name 
		,null
		,NULL
		,NULL 
		,NULL
		,NULL
		,NULL
from sys.databases as record
where not exists (select * from msdb..backupset where record.name = database_name and server_name = @server)
and name <> 'tempdb'
and source_database_id is null --exclude snapshots

SET @HTML = '<h2>Backups</h2>
			<table>
			<tr>
			<th>DB Server</th>
			<th>DB Name</th>
			<th>Last Full Backup</th>
			<th>Last Tran Backup</th>
			<th>Full Days</th>
			<th>Tran Hours</th>
			<th>Recovery Model</th>
			</tr>' 
			+(SELECT DBServer td,
					DBName td,
					CAST(CASE WHEN FullDays IS NULL THEN '<div class="Critical">None/Unknown</div>'
						WHEN FullDays > @FullBkpWarningDays THEN '<div class="Warning">' + LEFT(CONVERT(varchar,LastFullBackup,113),17) + '</div>'
						ELSE '<div class="Healthy">' + LEFT(CONVERT(varchar,LastFullBackup,113),17) + '</div>' END as XML) td,
					--CAST(CASE WHEN DiffDays IS NULL THEN '<div class="Critical">None/Unknown</div>'
					--	WHEN DiffDays > @DiffBkpWarningDays THEN '<div class="Warning">' + LEFT(CONVERT(varchar,LastDiffBackup,113),17) + '</div>'
					--	ELSE  '<div class="Healthy">' + LEFT(CONVERT(varchar,LastDiffBackup,113),17) + '</div>' END as XML) td,
					CAST(CASE WHEN TranHours IS NULL THEN  COALESCE(LEFT(NULLIF(recovery_model_desc,'SIMPLE'),0) + '<div class="Critical">None/Unknown</div>','N/A')
						WHEN TranHours > @TranBkpWarningHours THEN '<div class="Warning">' + LEFT(CONVERT(varchar,LastTranBackup,113),17) + '</div>'
						ELSE  '<div class="Healthy">' + LEFT(CONVERT(varchar,LastTranBackup,113),17) + '</div>' END as XML) td,
					FullDays td,
					--DiffDays td,
					TranHours td,
					recovery_model_desc td
			FROM @backuplog bl
			LEFT JOIN sys.databases sdb on bl.DBName = sdb.name COLLATE SQL_Latin1_General_CP1_CI_AS AND bl.DBServer = @Server
			WHERE DBServer = @@SERVERNAME
			ORDER BY LastFullBackup,LastDiffBackup,LastTranBackup,DBName
			FOR XML RAW('tr'),ELEMENTS XSINIL
			)
			+ '</table>'



GO


CREATE PROC [dbo].[DBAChecklist_DBChanges]
	@HTML varchar(max) out
AS

SET @HTML = '<h2>DB Changes</h2>
			<table>
			<tr>
			<th>DB Name</th>
			<th>Login Name</th>
			<th>Object Type</th>
			<th>Object Name</th>
			</tr>' 			
 + (SELECT   DISTINCT
         DDLEventXML.value('(//DatabaseName)[1]', 'nvarchar(30)') td,
         DDLEventXML.value('(//LoginName)[1]', 'nvarchar(25)') td,
         DDLEventXML.value('(//ObjectType)[1]', 'nvarchar(25)') td,
         DDLEventXML.value('concat((//SchemaName)[1], ".", (//ObjectName)[1])', 'nvarchar(50)') td
FROM     DBAdmin.dbo.DDLEventLog WITH(NOLOCK)
WHERE    DDLEventXML.value('(//DatabaseName)[1]', 'nvarchar(40)') NOT LIKE 'DBGhost%'
AND      DDLEventXML.value('(//LoginName)[1]', 'nvarchar(30)') <> 'NT AUTHORITY\NETWORK SERVICE'
AND      DDLEventXML.value('(//LoginName)[1]', 'nvarchar(30)') <> 'SEATWAVEPEER1\SQLAGTSVC'
AND      DDLEventXML.value('(//EventType)[1]', 'nvarchar(20)') NOT LIKE '%STATISTICS%'
AND      DDLEventXML.value('(//EventType)[1]', 'nvarchar(20)') NOT LIKE '%USER%'
AND      DDLEventXML.value('(//DatabaseName)[1]', 'nvarchar(30)') <> 'DBAdmin'
AND      CONVERT(CHAR(10), DDLEventXML.value('(//PostTime)[1]', 'datetime'), 121) = CONVERT(CHAR(10), GETDATE(), 121)
ORDER BY 1, 2, 3, 4

FOR XML RAW('tr'),ELEMENTS XSINIL
			)
			+ '</table>'
IF @HTML IS NULL
BEGIN
		SET @HTML = '<h2>DB Changes</h2>
					<span class="Healthy">No Changes Made</span><br/>'
END


GO


CREATE PROC [dbo].[DBAChecklist_DBFiles]
	@IncludeDBs varchar(max)=NULL,
	@ExcludeDBs varchar(max)='master,model,msdb',
	@WarningThresholdPCT int=90,
	@CriticalThresholdPCT int=95,
	@HTML varchar(max) output

AS

CREATE TABLE #FileStats(
	[db] sysname not null,
	[name] [sysname] not null,
	[file_group] [sysname] null,
	[physical_name] [nvarchar](260) NOT NULL,
	[type_desc] [nvarchar](60) NOT NULL,
	[size] [varchar](33) NOT NULL,
	[space_used] [varchar](33)  NULL,
	[free_space] [varchar](33)  NULL,
	[pct_used] [float]  NULL,
	[max_size] [varchar](33) NOT NULL,
	[growth] [varchar](33) NOT NULL
) 
DECLARE @IncludeXML XML
DECLARE @ExcludeXML XML
DECLARE @DB sysname

IF @IncludeDBs = ''
BEGIN
	SET @HTML = ''
	DROP TABLE #FileStats
	RETURN
END

SELECT @IncludeXML = '<a>' + REPLACE(@IncludeDBs,',','</a><a>') + '</a>'
SELECT @ExcludeXML = '<a>' + REPLACE(@ExcludeDBs,',','</a><a>') + '</a>'

DECLARE cDBs CURSOR FOR
			SELECT name FROM sys.databases
			WHERE (name IN(SELECT n.value('.','sysname')
						FROM @IncludeXML.nodes('/a') T(n))
						OR @IncludeXML IS NULL)
				AND (name NOT IN(SELECT n.value('.','sysname')
						FROM @ExcludeXML.nodes('/a') T(n))
						OR @ExcludeXML IS NULL)
			AND source_database_id IS NULL
			AND state = 0 --ONLINE
			ORDER BY name
			
OPEN cDBs
FETCH NEXT FROM cDBs INTO @DB
WHILE @@FETCH_STATUS = 0
BEGIN
	DECLARE @SQL nvarchar(max)
	SET @SQL =		 N'USE ' + QUOTENAME(@DB) + ';
					INSERT INTO #FileStats(db,name,file_group,physical_name,type_desc,size,space_used,free_space,[pct_used],max_size,growth)
					select DB_NAME() db,
					f.name,
					fg.name as file_group,
					f.physical_name,
					f.type_desc,
					CASE WHEN (f.size/128) < 1024 THEN CAST(f.size/128 as varchar) + '' MB'' 
						ELSE CAST(CAST(ROUND(f.size/(128*1024.0),1) as float) as varchar) + '' GB'' 
						END as size,
					CASE WHEN FILEPROPERTY(f.name,''spaceused'')/128 < 1024 THEN CAST(FILEPROPERTY(f.name,''spaceused'')/128 as varchar) + '' MB''
						ELSE CAST(CAST(ROUND(FILEPROPERTY(f.name,''spaceused'')/(128*1024.0),1) as float) as varchar) + '' GB'' 
						END space_used,
					CASE WHEN (f.size - FILEPROPERTY(f.name,''spaceused''))/128 < 1024 THEN CAST((f.size - FILEPROPERTY(f.name,''spaceused''))/128 as varchar) + '' MB''
						ELSE CAST(CAST(ROUND((f.size - FILEPROPERTY(f.name,''spaceused''))/(128*1024.0),1) as float) as varchar) + '' GB''
						END free_space,
					ROUND((FILEPROPERTY(f.name,''spaceused''))/CAST(size as float)*100,2) as [pct_used],
					CASE WHEN f.max_size =-1 THEN ''unlimited'' 
						WHEN f.max_size/128 < 1024 THEN CAST(f.max_size/128 as varchar) + '' MB'' 
						ELSE CAST(f.max_size/(128*1024) as varchar) + '' GB''
						END as max_size,
					CASE WHEN f.is_percent_growth=1 THEN CAST(f.growth as varchar) + ''%''
						WHEN f.growth = 0 THEN ''none''
						WHEN f.growth/128 < 1024 THEN CAST(f.growth/128 as varchar) + '' MB'' 
						ELSE CAST(CAST(ROUND(f.growth/(128*1024.0),1) as float) as varchar) + '' GB''
						END growth
					from sys.database_files f
					LEFT JOIN sys.filegroups fg on f.data_space_id = fg.data_space_id
					where f.type_desc <> ''FULLTEXT'''
	exec sp_executesql @SQL	
					
	FETCH NEXT FROM cDBs INTO @DB
END
CLOSE cDBs
DEALLOCATE cDBs

SELECT @HTML = '<h2>Database Files</h2><table>' + 
		(SELECT 'Database' th,
		'Name' th,
		'File Group' th,
		'File Path' th,
		'Type' th,
		'Size' th,
		'Used' th,
		'Free' th,
		'Used %' th,
		'Max Size' th,
		'Growth' th
		FOR XML RAW('tr'),ELEMENTS ) +		
		(SELECT db td,
					name td,
					file_group td,
					physical_name td,
					type_desc td,
					size td,
					space_used td,
					free_space td,
					CAST(CASE WHEN pct_used > @CriticalThresholdPCT 
						THEN '<div class="Critical" align="right">' + CAST(pct_used as varchar) + '</div>'
						WHEN pct_used > @WarningThresholdPCT  
						THEN '<div class="Warning" align="right">' + CAST(pct_used as varchar) + '</div>'
						ELSE '<div class="Healthy" align="right">' + CAST(pct_used as varchar) + '</div>'
						END as XML) td,
					max_size td,
					CAST(CASE WHEN growth='none' THEN '<div class="Warning">' + growth + '</div>'
					ELSE growth END as XML) td
				FROM #FileStats
				ORDER BY db,type_desc DESC,file_group,name
				FOR XML RAW('tr'),ELEMENTS XSINIL) + '</table>'
				
DROP TABLE #FileStats



GO


CREATE PROC [dbo].[DBAChecklist_DiskDrives]
	@PCTFreeWarningThreshold int,
	@PCTFreeCriticalThreshold int,
	@HTML varchar(max) out
AS

WITH DriveInfo AS (
	SELECT distinct vs.volume_mount_point AS Drive,
		vs.total_bytes/1073741824 AS Size,
		vs.available_bytes/1073741824 AS Free,
		CAST(CAST(vs.available_bytes AS FLOAT)/ CAST(vs.total_bytes AS FLOAT) AS DECIMAL(18,3)) * 100 AS PercentFree
		FROM sys.master_files AS mf
		CROSS APPLY sys.dm_os_volume_stats(mf.database_id, mf.file_id) AS vs		
)
SELECT @HTML = 
	'<h2>Disk Drives</h2>
	<table>' +
	(SELECT 'Drive' th,
			'Size' th,
			'Free' th,
			'Free %' th
	FOR XML RAW('tr'),ELEMENTS) 
	+
	(SELECT drive td,
			Size td,
			Free td,
			CAST(CASE WHEN PercentFree < @PCTFreeCriticalThreshold THEN '<div class="Critical">' + CAST(PercentFree as varchar) + '</div>'
			WHEN PercentFree < @PCTFreeWarningThreshold THEN '<div class="Warning">' + CAST(PercentFree as varchar) + '</div>'
			ELSE '<div class="Healthy">' + CAST(PercentFree as varchar) + '</div>' END as XML) td
	FROM DriveInfo 
	FOR XML RAW('tr'),ELEMENTS XSINIL)
	+ '</table>'

SET ANSI_NULLS ON



GO


CREATE PROC [dbo].[DBAChecklist_ErrorLog]
	@NumDays int,
	@HTML varchar(max) out 
AS

SET NOCOUNT ON
CREATE TABLE #ErrorLog(
	LogDate datetime,
	ErrorSource nvarchar(max),
	ErrorMessage nvarchar(max)
)

CREATE TABLE #ErrorLogs(
	ID INT primary key not null,
	LogDate DateTime NOT NULL,
	LogFileSize bigint
)
DECLARE @MinDate datetime
SET @MinDate = CONVERT(datetime,CONVERT(varchar,DATEADD(d,-@NumDays,GetDate()),112),112)

--Get a list of available error logs
INSERT INTO #ErrorLogs(ID,LogDate,LogFileSize)
EXEC master.dbo.xp_enumerrorlogs

DECLARE @ErrorLogID int

DECLARE cErrorLogs CURSOR FOR
	SELECT ID
	FROM #ErrorLogs
	WHERE LogDate >= @MinDate

OPEN cErrorLogs
FETCH NEXT FROM cErrorLogs INTO @ErrorLogID
-- Read applicable error logs into the #errorlog table
WHILE @@FETCH_STATUS = 0
BEGIN
	INSERT INTO #ErrorLog(LogDate,ErrorSource,ErrorMessage)
	exec sp_readerrorlog @ErrorLogID
	FETCH NEXT FROM cErrorLogs INTO @ErrorLogID
END

CLOSE cErrorLogs
DEALLOCATE cErrorLogs

SET @HTML = '<h2>SQL Error Log</h2>
<table><tr><th>Log Date</th><th>Source</th><th>Message</th></tr>' + 
(SELECT CONVERT(varchar,LogDate,120) td,
	CAST('<div><![CDATA[' + ErrorSource + N']]></div>' as XML) td,
	CAST('<div' + 
		CASE WHEN (ErrorMessage LIKE '%error%' OR ErrorMessage LIKE '%exception%' 
					OR ErrorMessage LIKE '%stack dump%' OR ErrorMessage LIKE '%fail%') 
				AND ErrorMessage NOT LIKE '%DBCC%' THEN ' Class="Critical"' 
		WHEN ErrorMessage LIKE '%warning%' THEN ' Class="Warning"'
		ELSE '' END 
		+ '><![CDATA[' + ErrorMessage + N']]></div>' as XML) td
FROM #ErrorLog
WHERE LogDate >= @MinDate
/*	Remove any error log records that we are not interested in
	ammend the where clause as appropriate
*/
AND ErrorMessage NOT LIKE '%This is an informational message%'
AND ErrorMessage NOT LIKE 'Authentication mode is%'
AND ErrorMessage NOT LIKE 'System Manufacturer%'
AND ErrorMessage NOT LIKE 'All rights reserved.'
AND ErrorMessage NOT LIKE 'Server Process ID is%'
AND ErrorMessage NOT LIKE 'Starting up database%'
AND ErrorMessage NOT LIKE 'Registry startup parameters%'
AND ErrorMessage NOT LIKE 'Server is listening on%'
AND ErrorMessage NOT LIKE 'Server local connection provider is ready to accept connection on%'
AND ErrorMessage NOT LIKE 'Logging SQL Server messages in file%'
AND ErrorMessage <> 'Clearing tempdb database.'
AND ErrorMessage <> 'Using locked pages for buffer pool.'
AND ErrorMessage <> 'Service Broker manager has started.'
ORDER BY LogDate DESC
FOR XML RAW('tr'),ELEMENTS XSINIL)
+ '</table>'

IF @HTML IS NULL
BEGIN
		SET @HTML = '<h2>SQL Error Log</h2>
					<span class="Healthy">No Errors Found</span><br/>'
END

DROP TABLE #ErrorLog
DROP TABLE #ErrorLogs


GO


CREATE PROC [dbo].[DBAChecklist_FailedJobs]
	@NumDays int,
	@HTML varchar(max) out
AS

DECLARE @FromDate char(8)
DECLARE @SucceededCount int
SET @FromDate = CONVERT(char(8),dateadd (day,-@NumDays, getdate()), 112)

IF EXISTS(	
	SELECT *
	FROM msdb..sysjobhistory jh
	JOIN msdb..sysjobs j ON jh.job_id = j.job_id
	WHERE jh.run_status IN(0,3) -- Failed/Cancelled
		AND jh.step_id <> 0
		AND	DATEDIFF(hh, CONVERT(varchar(10), run_date), GETDATE()) < @NumDays)
BEGIN
SET @HTML = '<h2>Failed Jobs in the last ' + CAST(@NumDays as varchar) + ' hours</h2>
	<table>
	<tr>
	<th>Date</th>
	<th>Job Name</th>
	<th>Job Status</th>
	<th>Step ID</th>
	<th>Step Name</th>
	<th>Message</th>
	<th>Run Duration</th>
	</tr>'
	+
	(SELECT CONVERT(datetime,CAST(jh.run_date AS char(8)) + ' ' + STUFF(STUFF(RIGHT('000000' + CONVERT(VARCHAR,jh.run_time),6),5,0,':'),3,0,':'),101) AS td,
		j.name AS td,
		CAST(CASE jh.run_status WHEN 0 THEN '<div class="Critical">Failed</div>'
			WHEN 3 THEN '<div class="Warning">Cancelled</div>'
			ELSE NULL END as XML) as td,
		jh.step_id as td,
		jh.step_name as td,
		jh.message as td,
				RIGHT('00' +CAST(run_duration/10000 as varchar),2) + ':' +
				RIGHT('00' + CAST(run_duration/100%100 as varchar),2) + ':' +
				RIGHT('00' + CAST(run_duration%100 as varchar),2) as td
	FROM	msdb..sysjobhistory jh
	JOIN	msdb..sysjobs j
		ON jh.job_id = j.job_id
	WHERE	jh.run_status IN(0,3) -- Failed/Cancelled
		AND jh.step_id <> 0
		AND	DATEDIFF(hh, CONVERT(varchar(10), run_date), GETDATE()) < @NumDays
	ORDER BY CONVERT(datetime,CAST(jh.run_date AS char(8)) + ' ' + STUFF(STUFF(RIGHT('000000' + CONVERT(VARCHAR,jh.run_time),6),5,0,':'),3,0,':'),101) DESC
	FOR XML RAW('tr'),ELEMENTS XSINIL
	)
	+ '</table><br/>'
END
ELSE
BEGIN
	SET @HTML = '<h2>Failed Jobs in the last ' + CAST(@NumDays as varchar) + ' hours</h2>
				<span class="Healthy">No failed jobs</span><br/>'	
END


GO


CREATE PROC [dbo].[DBAChecklist_IndexLog]
	@HTML varchar(max) output

AS


IF object_id('dbo.CommandLog', 'U') is null
    RETURN
ELSE
    	
		SELECT @HTML = '<h2>Index Report</h2><table>' + 
			(SELECT 'Database' th,
			'Object Name' th,
			--'Object Type' th,
			'Index Name' th,
			'Index Type' th,
			'Page Count' th,
			'Fragmention' th,
			'Alter Index Type' th,
			'Start Time' th,
			'End Time' th,
			'Error Message' th
			FOR XML RAW('tr'),ELEMENTS ) +		
			(SELECT DatabaseName td,
						--SchemaName td,
						ObjectName td,
						--CAST(CASE WHEN ObjectType = 'U' THEN 'USER_TABLE' WHEN ObjectType = 'V' THEN 'VIEW' END AS XML) td,
						IndexName td,
						CAST(CASE WHEN IndexType = 1 THEN 'CLUSTERED' WHEN IndexType = 2 THEN 'NONCLUSTERED' WHEN IndexType = 3 THEN 'XML' WHEN IndexType = 4 THEN 'SPATIAL' END AS XML)td,
						--PartitionNumber td,
						ExtendedInfo.value('(ExtendedInfo/PageCount)[1]','int') td,
						ExtendedInfo.value('(ExtendedInfo/Fragmentation)[1]','decimal(5,2)') td,
						--CommandType td,
						CAST(CASE WHEN Command LIKE '%REBUILD%' THEN 'REBUILD' WHEN command LIKE '%REORGANIZE%' THEN 'Reorganise' END AS XML) td,
						StartTime td,
						EndTime td,
						ErrorMessage td
					FROM dbo.CommandLog
					WHERE CommandType = 'ALTER_INDEX'
					AND commandlog.StartTime >= DATEADD(day, -1, GETDATE())
					ORDER BY StartTime ASC
					FOR XML RAW('tr'),ELEMENTS XSINIL) + '</table>'

RETURN


GO


CREATE PROC [dbo].[DBAChecklist_JobStats]
	@NumDays int,
	@HTML nvarchar(max) out

SET ANSI_WARNINGS OFF
DECLARE @FromDate char(8)
SET @FromDate = CONVERT(char(16), (select dateadd (HOUR,(-1*@NumDays), getdate())), 120);

WITH nextRun as (
	SELECT js.job_id, 
		MAX(CONVERT(datetime,CONVERT(CHAR(8), NULLIF(next_run_date,0), 112) 
			+ ' ' 
			+ STUFF(STUFF(RIGHT('000000' 
			+ CONVERT(VARCHAR(8), next_run_time), 6), 5, 0, ':'), 3, 0, ':') )
			) as next_run_time
	FROM msdb..sysjobschedules js
	GROUP BY js.job_id
),
lastRun as (
	SELECT jh.job_id,CONVERT(datetime,CONVERT(CHAR(8), run_date, 112) 
		+ ' ' 
		+ STUFF(STUFF(RIGHT('000000' 
		+ CONVERT(VARCHAR(8), run_time), 6), 5, 0, ':'), 3, 0, ':') ) as last_run_time,
		run_status as last_run_status,
		CAST(message as nvarchar(max)) as last_result,
		ROW_NUMBER() OVER(PARTITION BY job_id ORDER BY run_date DESC,run_time DESC) rnum
	FROM msdb..sysjobhistory jh
	WHERE run_status IN(0,1,3) --Succeeded/Failed/Cancelled
)
,JobStats AS (
	select name,
			MAX(enabled) enabled,
			SUM(CASE WHEN run_status = 1 THEN 1 ELSE 0 END) as SucceededCount,
			SUM(CASE WHEN run_status = 0 THEN 1 ELSE 0 END) as FailedCount,
			SUM(CASE WHEN run_status = 3 THEN 1 ELSE 0 END) as CancelledCount,
			MAX(last_run_time) last_run_time,
			MAX(next_run_time) next_run_time,
			MAX(last_run_status) last_run_status,
			COALESCE(MAX(last_result),'Unknown') last_result
	from msdb..sysjobs j
	LEFT JOIN msdb..sysjobhistory jh ON j.job_id = jh.job_id AND DATEDIFF(hh, CONVERT(varchar(10), run_date), GETDATE()) > @NumDays and jh.step_id = 0
	LEFT JOIN nextrun ON j.job_id = nextrun.job_id
	LEFT JOIN lastRun ON j.job_id = lastRun.job_id AND rnum=1
	WHERE j.name like 'DBA%'
	GROUP BY name
)
SELECT @HTML =N'<h2>Agent Job Stats in the last ' + CAST(@NumDays as varchar) + N' hours</h2>
	<table>' +
	(SELECT 'Name' th,
	'Enabled' th,
	'Succeeded' th,
	'Failed' th,
	'Cancelled' th,
	'Last Run Time' th,
	'Next Run Time' th,
	'Last Result' th
	FOR XML RAW('tr'),ELEMENTS) 
	+ (SELECT name td,
			CAST(CASE WHEN enabled = 1 THEN N'<div class="Healthy">Yes</div>'
					ELSE N'<div class="Warning">No</div>' END as XML) td,
			CAST(CASE WHEN SucceededCount = 0 THEN  N'<div class="Warning">'
					ELSE N'<div>' END
					+ CAST(SucceededCount as varchar) + '</div>' as XML) td,
			CAST(CASE WHEN FailedCount >0 THEN  N'<div class="Critical">'
					ELSE N'<div class="Healthy">' END
					+ CAST(FailedCount as varchar) + N'</div>' as XML) td,
			CAST(CASE WHEN CancelledCount >0 THEN  N'<div class="Critical">'
					ELSE N'<div class="Healthy">' END
					+ CAST(CancelledCount as varchar) + N'</div>' as XML) td,
			LEFT(CONVERT(varchar,last_run_time,13),17) td,
			LEFT(CONVERT(varchar,next_run_time,13),17) td,
			CAST(CASE WHEN last_run_status = 1 THEN N'<span class="Healthy"><![CDATA[' + last_result + N']]></span>' 
					ELSE N'<span class="Critical"><![CDATA[' + last_result + N']]></span>' END  AS XML)  td 
		FROM JobStats
		ORDER BY last_run_time DESC
		FOR XML RAW('tr'),ELEMENTS XSINIL
	) + N'</table>'
IF @HTML IS NULL
BEGIN 
	SET @HTML = '<h2>Agent Job Stats in the last ' + CAST(@NumDays as varchar) + ' hours</h2>
				<span class="Healthy">No job stats to report</span><br/>'	
END

GO

