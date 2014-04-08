USE [master]
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

