USE [master]
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

