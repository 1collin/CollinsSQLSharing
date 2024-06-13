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



------------


--Compare waits for specific HashIDs
DECLARE @UTC_Offset INT = -7;

WITH Snaps AS
(
	SELECT 
		  MAX(r.runtime) [Lastsnap]
		, b.HashID
		, r.session_id
		, r.wait_type
		, MAX(r.wait_duration_ms) [wait_ms]
	FROM ReadTrace.tblBatches b
		JOIN dbo.tbl_REQUESTS r ON b.Session = r.session_id
			AND r.runtime <= DATEADD(HOUR, @UTC_Offset, b.EndTime)
			AND r.runtime >= DATEADD(HOUR, @UTC_Offset, b.StartTime)
	WHERE HashID IN (-7758464401401233043, 3262107551579857174, -618862393263134308, -9048367324748729896, -6355130179974594400)
		AND wait_type NOT IN ('CXCONSUMER', 'WAITFOR')
	GROUP BY 
		  b.HashID
		, r.session_id
		, r.request_start_time
		, r.wait_type
), BaselineSnaps AS
(
	SELECT 
		  MAX(r.runtime) [Lastsnap]
		, b.HashID
		, r.session_id
		, r.wait_type
		, MAX(r.wait_duration_ms) [wait_ms]
	FROM [PerfScenario1_Baseline].ReadTrace.tblBatches b
		JOIN [PerfScenario1_Baseline].dbo.tbl_REQUESTS r ON b.Session = r.session_id
			AND r.runtime <= DATEADD(HOUR, @UTC_Offset, b.EndTime)
			AND r.runtime >= DATEADD(HOUR, @UTC_Offset, b.StartTime)
	WHERE HashID IN (-7758464401401233043, 3262107551579857174, -618862393263134308, -9048367324748729896, -6355130179974594400)
		AND wait_type NOT IN ('CXCONSUMER', 'WAITFOR')
	GROUP BY 
		  b.HashID
		, r.session_id
		, r.request_start_time
		, r.wait_type
), Summary AS
(
	SELECT s.HashID, s.wait_type, SUM(s.wait_ms) [wait_ms]
	FROM Snaps s
	GROUP BY s.HashID, s.wait_type
), BaselineSummary AS
(
	SELECT s.HashID, s.wait_type, SUM(s.wait_ms) [wait_ms]
	FROM BaselineSnaps s
	GROUP BY s.HashID, s.wait_type
)
SELECT 
	  COALESCE(s.HashID, b.HashID) [HashID]
	, COALESCE(s.wait_type, b.wait_type) [wait_type]
	, ISNULL(s.wait_ms, 0)-ISNULL(b.wait_ms, 0) [ΔSampledWaitDurationMs]
	, s.wait_ms [SlowerWaitDurationMs]
	, b.wait_ms [BLWaitDurationMs]
FROM Summary s
	FULL OUTER JOIN BaselineSummary b ON s.HashID = b.HashID
		AND s.wait_type = b.wait_type
ORDER BY [ΔSampledWaitDurationMs] DESC
