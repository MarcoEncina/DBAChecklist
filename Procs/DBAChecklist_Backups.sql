USE [master]
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

