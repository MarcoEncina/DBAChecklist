USE [master]
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

