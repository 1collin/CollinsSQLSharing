WITH NormalizedCIS AS
(
	SELECT
		  avg_user_impact
		, improvement_measure
		, [database_id]
		,REPLACE(
			create_index_statement,
			SUBSTRING(create_index_statement, 
					  charindex('missing_index_',create_index_statement), 
					  charindex(' ',create_index_statement,
					  charindex('missing_index_',create_index_statement))-charindex('missing_index_',create_index_statement)
					  ),
			'<MissIdx> '
				) AS create_index_statement
		,unique_compiles
		,user_seeks
		,last_user_seek
	FROM
		[dbo].[tbl_MissingIndexes]
	WHERE avg_user_impact > 90 or user_seeks > 10000 or unique_compiles > 1000
)
SELECT 
	  MAX(avg_user_impact) avg_user_impact
	, MAX(improvement_measure) improvement_measure
	, database_id
	, create_index_statement
	, MAX(unique_compiles) unique_compiles
	, MAX(user_seeks) user_seeks
	, MAX(last_user_seek) last_user_seek
FROM NormalizedCIS
GROUP BY database_id, create_index_statement
ORDER BY avg_user_impact DESC
