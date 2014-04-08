USE [master]
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

