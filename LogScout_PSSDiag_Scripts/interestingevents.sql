WITH Groupie AS
(
SELECT	ie.EventID, te.name, 
	CASE WHEN tsv.subclass_name IS NULL AND ie.EventID = 58 THEN 
		CASE WHEN LEFT(ie.TextData, 21) = 'Loading and updating:' OR LEFT(ie.TextData, 8) = 'Updated:' THEN 'Auto Update'
			WHEN LEFT(ie.TextData, 8) = 'Created:' OR CHARINDEX('Creating', ie.TextData, 1) > 0 THEN 'Auto Create'
			WHEN LEFT(ie.TextData, 27) = 'Failed to obtain stats lock'	THEN 'Failed to obtain stats lock'
			ELSE 'N/A'
		END	
		ELSE tsv.subclass_name
	END [Subclass]
	, COUNT(1) [#Occurrences] 
	FROM	[ReadTrace].[tblInterestingEvents] ie
		JOIN	sys.trace_events te ON te.trace_event_id = ie.EventID 
		LEFT JOIN	sys.trace_subclass_values tsv ON tsv.trace_event_id = ie.EventID AND tsv.subclass_value = ie.EventSubclass
	WHERE ie.TextData NOT LIKE 'Loading without updating%'
		OR ie.TextData IS NULL
	GROUP BY	ie.EventID, te.name, tsv.subclass_name, ie.TextData
)
SELECT EventID, name, Subclass, SUM([#Occurrences]) [#Occurrences]
FROM Groupie
GROUP BY EventID, name, Subclass
ORDER BY	[#Occurrences] DESC


--Filter by HashID
SELECT te.name
	, tsv.subclass_name
	, b.*
	, ie.TextData
FROM ReadTrace.tblInterestingEvents ie
	JOIN ReadTrace.tblBatches b ON ie.Session = b.Session
		AND ie.ConnId = b.ConnId
		AND ie.DBID = b.DBID
		AND ie.EndTime <= b.EndTime
		AND ie.EndTime > b.StartTime
		AND ie.StartTime >= b.StartTime
	JOIN	sys.trace_events te ON te.trace_event_id = ie.EventID 
	LEFT JOIN	sys.trace_subclass_values tsv ON tsv.trace_event_id = ie.EventID AND tsv.subclass_value = ie.EventSubclass
WHERE b.HashID = -7185144618805289206
