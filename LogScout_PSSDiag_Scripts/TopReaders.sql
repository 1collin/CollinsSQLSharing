WITH TopReaders AS(
SELECT top 20 HashID, dbid, SUM(Reads) [Reads]
FROM ReadTrace.tblBatches
GROUP BY HashID, DBID
)
SELECT r.HashID, r.DBID [database_id], t.TextData, r.Reads
FROM TopReaders r
	CROSS APPLY (SELECT TOP(1) TextData FROM ReadTrace.tblBatches b WHERE b.HashID = r.HashID AND TextData IS NOT NULL) t
ORDER by Reads DESC
