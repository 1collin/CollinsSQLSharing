DECLARE 
	  @Database SYSNAME = 'StackOverflow2013'
	, @DBID SMALLINT = 0;

SELECT TOP(1) @DBID = database_id
FROM dbo.tbl_SysDatabases
WHERE name = @Database;

IF @DBID <> 0
BEGIN

	WITH Slower AS
	(
		SELECT 
			  HashID
			, AVG(Duration/1000.0) [AvgDur]
			, AVG(CPU) [AvgCPU]
			, AVG(Reads) [AvgReads]
			, AVG(Writes) [AvgWrites]
			, COUNT(1) [CountExecutions]
		FROM ReadTrace.tblBatches b
		WHERE DBID = @DBID
		GROUP BY HashID
	), BaseLine AS
	(
		SELECT 
			  HashID
			, AVG(Duration/1000.0) [AvgDur]
			, AVG(CPU) [AvgCPU]
			, AVG(Reads) [AvgReads]
			, AVG(Writes) [AvgWrites]
			, COUNT(1) [CountExecutions]
		FROM [PerfScenario1_Baseline].ReadTrace.tblBatches
		WHERE DBID = @DBID 
		GROUP BY HashID
	)
	SELECT 
		  COALESCE(s.HashID, b.HashID) [HashID]
		, CAST(s.AvgDur-b.AvgDur AS DECIMAL(18,2)) [ΔAvgDuration_Millisec]
		, CAST(b.AvgDur AS DECIMAL(18,2)) [BLAvgDuration_Millisec]
		, s.AvgCPU-b.AvgCPU [ΔAvgCPU]
		, b.AvgCPU [BLAvgCPU]
		, s.AvgReads-b.AvgReads [ΔAvgReads]
		, b.AvgReads [BLAvgReads]
		, s.AvgWrites-b.AvgWrites [ΔAvgWrites]
		, b.AvgWrites [BLAvgWrites]
		, s.CountExecutions [#Execs2ndCapture]
		, b.CountExecutions [#ExecsBLCapture]
	FROM Slower s
		FULL OUTER JOIN Baseline b ON s.HashID = b.HashID
	ORDER BY [ΔAvgDuration_Millisec] DESC
END
