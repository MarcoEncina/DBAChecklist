USE [master]
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

