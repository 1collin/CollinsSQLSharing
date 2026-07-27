$SourceDir = "C:\Temp\MyData\system_health_XeLogs";
# $WindowStartUTC = [datetime]::ParseExact('2024-05-06 16:30:00', 'yyyy-MM-dd HH:mm:ss', $null);
# $WindowEndUTC = [datetime]::ParseExact('2024-05-06 19:30:00', 'yyyy-MM-dd HH:mm:ss', $null);

# $wt = (Get-ChildItem $SourceDir).LastWriteTimeUtc | Where-Object {$_ -gt $WindowEndUTC} | Measure-Object -Minimum | Select-Object
# $FileNames = ((Get-ChildItem $SourceDir) | Where-Object {$_.LastWriteTimeUtc -ge $WindowStartUTC -and $_.LastWriteTimeUtc -le $wt.Minimum}).FullName

$FileNames = (Get-ChildItem -LiteralPath $SourceDir).FullName
   # @("C:\Temp\CXData\DataFiles\system_health_0_133821415102520000.xel");
$SqlSrv = "192.168.0.101\SQL2022";
$Db = "DB_Name_Here";
$Schema = "syshealth"; 



# ConvertTo-Bool was taken from https://powershellfaqs.com/convert-string-to-boolean-in-powershell/
Function ConvertTo-Bool {
    [CmdletBinding()]
    param(
        [Parameter(Position=0, Mandatory=$true)]
        [string]$Value
    )

    switch -regex ($Value.Trim().ToLower()) {
        '^(1|true|yes|on)$' { return $true }
        '^(0|false|no|off)$' { return $false }
        default { throw "Invalid input: '$Value'. Please use 1/0, true/false, yes/no, or on/off." }
    }
}

#Let's create datatables to hold data until populating into SQL Server
$Tables = [System.Collections.Generic.List[System.Data.DataTable]]::new()

#IO Subsystem has 2 distinct sections: Summary Stats and Pending Requests
$IOStatsTable = New-Object system.Data.DataTable 'IOSubsystemStats';
$IOCol = New-Object system.Data.DataColumn timestamp,([datetime]); $IOStatsTable.columns.add($IOCol);
$IOCol = New-Object system.Data.DataColumn ioLatchTimeouts,([int]); $IOStatsTable.columns.add($IOCol);
$IOCol = New-Object system.Data.DataColumn intervalLongIos,([int]); $IOStatsTable.columns.add($IOCol);
$IOCol = New-Object system.Data.DataColumn totalLongIos,([long]); $IOStatsTable.columns.add($IOCol);

$Tables.Add($IOStatsTable);

$IOPendingReqsTable = New-Object system.Data.DataTable 'IOSubsystemPendingRequests';
$IOCol = New-Object system.Data.DataColumn timestamp,([datetime]); $IOPendingReqsTable.columns.add($IOCol);
$IOCol = New-Object system.Data.DataColumn duration,([long]); $IOPendingReqsTable.columns.add($IOCol);
$IOCol = New-Object system.Data.DataColumn filePath,([string]); $IOPendingReqsTable.columns.add($IOCol);
$IOCol = New-Object system.Data.DataColumn offset,([long]); $IOPendingReqsTable.columns.add($IOCol);
$IOCol = New-Object system.Data.DataColumn handle,([string]); $IOPendingReqsTable.columns.add($IOCol);

$Tables.Add($IOPendingReqsTable);

#Query Processing has 4 distinct sections: Summary Stats, Waits, CPU-intesive Requests and Blocking Chain. Each needs own table.
$QPStatsTable = New-Object system.Data.DataTable 'QueryProcessingStats';
$QPCol = New-Object system.Data.DataColumn timestamp,([datetime]); $QPStatsTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn maxWorkers,([int]); $QPStatsTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn workersCreated,([int]); $QPStatsTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn tasksCompletedWithinInterval,([int]); $QPStatsTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn pendingTasks,([int]); $QPStatsTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn oldestPendingTaskWaitingTime,([int]); $QPStatsTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn hasUnresolvableDeadlockOccurred,([bool]); $QPStatsTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn hasDeadlockedSchedulersOccurred,([int]); $QPStatsTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn trackingNonYieldingScheduler,([string]); $QPStatsTable.columns.add($QPCol);

$Tables.Add($QPStatsTable);

$QPCpuIntReqsTable = New-Object system.Data.DataTable 'QueryProcessingCpuIntensiveRequests';
$QPCol = New-Object system.Data.DataColumn timestamp,([datetime]); $QPCpuIntReqsTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn sessionId,([int]); $QPCpuIntReqsTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn requestId,([int]); $QPCpuIntReqsTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn command,([string]); $QPCpuIntReqsTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn taskAddress,([string]); $QPCpuIntReqsTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn cpuUtilization,([int]); $QPCpuIntReqsTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn cpuTimeMs,([int]); $QPCpuIntReqsTable.columns.add($QPCol);

$Tables.Add($QPCpuIntReqsTable);

$QPWaitsTable = New-Object system.Data.DataTable 'QueryProcessingWaits';
$QPCol = New-Object system.Data.DataColumn timestamp,([datetime]); $QPWaitsTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn isPreemptive,([bool]); $QPWaitsTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn waitType,([string]); $QPWaitsTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn waits,([long]); $QPWaitsTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn averageWaitTime,([int]); $QPWaitsTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn maxWaitTime,([long]); $QPWaitsTable.columns.add($QPCol);

$Tables.Add($QPWaitsTable);

#QP Blocked Process report section
$QPBlockingTable = New-Object system.Data.DataTable 'QueryProcessingBlocking';

$QPCol = New-Object system.Data.DataColumn timestamp,([datetime]); $QPBlockingTable.columns.add($QPCol);

$QPCol = New-Object system.Data.DataColumn blockedassociatedObjectId,([long]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockedclientapp,([string]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockedclientoption1,([long]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockedclientoption2,([long]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockedcurrentdb,([int]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockedcurrentdbname,([string]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockedecid,([int]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockedexecutionStack,([string]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockedfileid,([int]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockedhobtid,([long]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockedhostname,([string]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockedhostpid,([int]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockedid,([string]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockedindexname,([string]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockedinputbuf,([string]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockedisolationlevel,([string]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockedkpid,([int]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockedlastattention,([datetime]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockedlastbatchcompleted,([datetime]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockedlastbatchstarted,([datetime]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockedlasttranstarted,([datetime]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockedlockMode,([string]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockedlockTimeout,([long]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockedloginname,([string]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockedlogused,([long]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockedobjectname,([string]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockedobjid,([int]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockedownerId,([long]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockedpageid,([long]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockedpriority,([int]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockedprocess,([long]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockedprocname,([long]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockedqueryhash,([long]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockedqueryplanhash,([long]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockedrequestType,([long]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockedsbid,([int]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockedschedulerid,([int]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockedspid,([int]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockedsqlhandle,([long]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockedstatus,([string]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockedstmtend,([long]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockedstmtstart,([long]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockedtaskpriority,([int]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockedtrancount,([int]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockedtransactionID,([long]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockedtransactionname,([string]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockedwaitresource,([string]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockedwaittime,([long]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockedWaitType,([long]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockedxactid,([long]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockedXDES,([string]); $QPBlockingTable.columns.add($QPCol);

$QPCol = New-Object system.Data.DataColumn blockerassociatedObjectId,([long]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockerclientapp,([string]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockerclientoption1,([long]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockerclientoption2,([long]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockercurrentdb,([int]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockercurrentdbname,([string]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockerecid,([int]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockerexecutionStack,([string]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockerfileid,([int]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockerhobtid,([long]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockerhostname,([string]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockerhostpid,([int]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockerid,([string]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockerindexname,([string]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockerinputbuf,([string]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockerisolationlevel,([string]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockerkpid,([int]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockerlastattention,([datetime]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockerlastbatchcompleted,([datetime]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockerlastbatchstarted,([datetime]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockerlasttranstarted,([datetime]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockerlockMode,([string]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockerlockTimeout,([long]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockerloginname,([string]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockerlogused,([long]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockerobjectname,([string]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockerobjid,([int]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockerownerId,([long]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockerpageid,([long]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockerpriority,([int]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockerprocess,([long]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockerprocname,([long]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockerqueryhash,([long]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockerqueryplanhash,([long]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockerrequestType,([long]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockersbid,([int]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockerschedulerid,([int]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockerspid,([int]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockersqlhandle,([long]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockerstatus,([string]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockerstmtend,([long]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockerstmtstart,([long]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockertaskpriority,([int]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockertrancount,([int]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockertransactionID,([long]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockertransactionname,([string]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockerwaitresource,([string]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockerwaittime,([long]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockerWaitType,([long]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockerxactid,([long]); $QPBlockingTable.columns.add($QPCol);
$QPCol = New-Object system.Data.DataColumn blockerXDES,([string]); $QPBlockingTable.columns.add($QPCol);

$Tables.Add($QPBlockingTable);

#Resource has 2 distinct sections: Summary Stats and Memory Report
$ResStatsTable = New-Object system.Data.DataTable 'ResourceStats';
$ResCol = New-Object system.Data.DataColumn timestamp,([datetime]); $ResStatsTable.columns.add($ResCol);
$ResCol = New-Object system.Data.DataColumn lastNotification,([string]); $ResStatsTable.columns.add($ResCol);
$ResCol = New-Object system.Data.DataColumn outOfMemoryExceptions,([int]); $ResStatsTable.columns.add($ResCol);
$ResCol = New-Object system.Data.DataColumn isAnyPoolOutOfMemory,([bool]); $ResStatsTable.columns.add($ResCol);
$ResCol = New-Object system.Data.DataColumn processOutOfMemoryPeriod,([long]); $ResStatsTable.columns.add($ResCol);

$Tables.Add($ResStatsTable);

$ResMemReportTable = New-Object system.Data.DataTable 'ResourceMemoryReport';
$ResCol = New-Object system.Data.DataColumn timestamp,([datetime]); $ResMemReportTable.columns.add($ResCol);
$ResCol = New-Object system.Data.DataColumn AvailablePhysicalMemory,([long]); $ResMemReportTable.columns.add($ResCol);
$ResCol = New-Object system.Data.DataColumn AvailableVirtualMemory,([long]); $ResMemReportTable.columns.add($ResCol);
$ResCol = New-Object system.Data.DataColumn AvailablePagingFile,([long]); $ResMemReportTable.columns.add($ResCol);
$ResCol = New-Object system.Data.DataColumn WorkingSet,([long]); $ResMemReportTable.columns.add($ResCol);
$ResCol = New-Object system.Data.DataColumn PercentofCommittedMemoryinWS,([int]); $ResMemReportTable.columns.add($ResCol);
$ResCol = New-Object system.Data.DataColumn PageFaults,([long]); $ResMemReportTable.columns.add($ResCol);
$ResCol = New-Object system.Data.DataColumn Systemphysicalmemoryhigh,([bool]); $ResMemReportTable.columns.add($ResCol);
$ResCol = New-Object system.Data.DataColumn Systemphysicalmemorylow,([bool]); $ResMemReportTable.columns.add($ResCol);
$ResCol = New-Object system.Data.DataColumn Processphysicalmemorylow,([bool]); $ResMemReportTable.columns.add($ResCol);
$ResCol = New-Object system.Data.DataColumn Processvirtualmemorylow,([bool]); $ResMemReportTable.columns.add($ResCol);
$ResCol = New-Object system.Data.DataColumn VMReserved,([long]); $ResMemReportTable.columns.add($ResCol);
$ResCol = New-Object system.Data.DataColumn VMCommitted,([long]); $ResMemReportTable.columns.add($ResCol);
$ResCol = New-Object system.Data.DataColumn LockedPagesAllocated,([long]); $ResMemReportTable.columns.add($ResCol);
$ResCol = New-Object system.Data.DataColumn LargePagesAllocated,([long]); $ResMemReportTable.columns.add($ResCol);
$ResCol = New-Object system.Data.DataColumn EmergencyMemory,([long]); $ResMemReportTable.columns.add($ResCol);
$ResCol = New-Object system.Data.DataColumn EmergencyMemoryinUse,([long]); $ResMemReportTable.columns.add($ResCol);
$ResCol = New-Object system.Data.DataColumn TargetCommitted,([long]); $ResMemReportTable.columns.add($ResCol);
$ResCol = New-Object system.Data.DataColumn CurrentCommitted,([long]); $ResMemReportTable.columns.add($ResCol);
$ResCol = New-Object system.Data.DataColumn PagesAllocated,([long]); $ResMemReportTable.columns.add($ResCol);
$ResCol = New-Object system.Data.DataColumn PagesReserved,([long]); $ResMemReportTable.columns.add($ResCol);
$ResCol = New-Object system.Data.DataColumn PagesFree,([long]); $ResMemReportTable.columns.add($ResCol);
$ResCol = New-Object system.Data.DataColumn PagesInUse,([long]); $ResMemReportTable.columns.add($ResCol);
$ResCol = New-Object system.Data.DataColumn PageAllocPotential,([long]); $ResMemReportTable.columns.add($ResCol);
$ResCol = New-Object system.Data.DataColumn NUMAGrowthPhase,([int]); $ResMemReportTable.columns.add($ResCol);
$ResCol = New-Object system.Data.DataColumn LastOOMFactor,([int]); $ResMemReportTable.columns.add($ResCol);
$ResCol = New-Object system.Data.DataColumn LastOSError,([long]); $ResMemReportTable.columns.add($ResCol);

$Tables.Add($ResMemReportTable);


#Single section in the system component
$SysTable = New-Object system.Data.DataTable 'System';
$SysCol = New-Object system.Data.DataColumn timestamp,([datetime]); $SysTable.columns.add($SysCol);
$SysCol = New-Object system.Data.DataColumn spinlockBackoffs,([long]); $SysTable.columns.add($SysCol);
$SysCol = New-Object system.Data.DataColumn sickSpinlockType,([string]); $SysTable.columns.add($SysCol);
$SysCol = New-Object system.Data.DataColumn sickSpinlockTypeAfterAv,([string]); $SysTable.columns.add($SysCol);
$SysCol = New-Object system.Data.DataColumn latchWarnings,([long]); $SysTable.columns.add($SysCol);
$SysCol = New-Object system.Data.DataColumn isAccessViolationOccurred,([bool]); $SysTable.columns.add($SysCol);
$SysCol = New-Object system.Data.DataColumn writeAccessViolationCount,([int]); $SysTable.columns.add($SysCol);
$SysCol = New-Object system.Data.DataColumn totalDumpRequests,([int]); $SysTable.columns.add($SysCol);
$SysCol = New-Object system.Data.DataColumn intervalDumpRequests,([int]); $SysTable.columns.add($SysCol);
$SysCol = New-Object system.Data.DataColumn nonYieldingTasksReported,([int]); $SysTable.columns.add($SysCol);
$SysCol = New-Object system.Data.DataColumn pageFaults,([long]); $SysTable.columns.add($SysCol);
$SysCol = New-Object system.Data.DataColumn systemCpuUtilization,([int]); $SysTable.columns.add($SysCol);
$SysCol = New-Object system.Data.DataColumn sqlCpuUtilization,([int]); $SysTable.columns.add($SysCol);
$SysCol = New-Object system.Data.DataColumn BadPagesDetected,([int]); $SysTable.columns.add($SysCol);
$SysCol = New-Object system.Data.DataColumn BadPagesFixed,([int]); $SysTable.columns.add($SysCol);
$SysCol = New-Object system.Data.DataColumn LastBadPageAddress,([string]); $SysTable.columns.add($SysCol);

$Tables.Add($SysTable);

$WaitTable = New-Object system.Data.DataTable 'WaitInfo';
$WaitCol = New-Object system.Data.DataColumn timestamp,([datetime]); $WaitTable.columns.add($WaitCol);
$WaitCol = New-Object system.Data.DataColumn wait_type,([string]); $WaitTable.columns.add($WaitCol);
$WaitCol = New-Object system.Data.DataColumn duration,([long]); $WaitTable.columns.add($WaitCol);
$WaitCol = New-Object system.Data.DataColumn signal_duration,([long]); $WaitTable.columns.add($WaitCol);
$WaitCol = New-Object system.Data.DataColumn wait_resource,([string]); $WaitTable.columns.add($WaitCol);
$WaitCol = New-Object system.Data.DataColumn session_id,([int]); $WaitTable.columns.add($WaitCol);
$WaitCol = New-Object system.Data.DataColumn opcode,([string]); $WaitTable.columns.add($WaitCol);
$WaitCol = New-Object system.Data.DataColumn callstack_rva,([string]); $WaitTable.columns.add($WaitCol);

$Tables.Add($WaitTable);

foreach($xelfile in $FileNames)
{
    Write-Progress -Activity "Reading in file" -CurrentOperation $xelfile
    $XEFile = Read-SqlXEvent -FileName $xelfile `
    | Where-Object {($_.Name -eq "sp_server_diagnostics_component_result") -or ($_.Name -eq "component_health_result") -or ($_.Name -eq "wait_info")} 

    Write-Progress -Activity "Reading in file" -CurrentOperation $xelfile -PercentComplete 100 -Completed
    $IOCount = 0; $QPCount = 0; $ResCount = 0; $SysCount = 0; $WaitCount = 0; $OthCount = 0;

     $entryCount = $XEFile.Count;

     if ($entryCount -lt 1)
        {$entryCount = 1;}

    "Reading in $xelfile complete" | Write-Host 

    "Total entries in file: $entryCount" | Write-Host

    $ctr = 0;
   

    foreach($entry in $XEFile)
    {
        if($ctr % 100 -eq 0)
        {
            Write-Progress -Activity "Processing Entries" -PercentComplete (100*($ctr/$entryCount)) -Status "$([math]::round(100*($ctr/$entryCount),2)) Percent Complete ($ctr/$entryCount)"
        }

        $ctr++;

        $entryTimestampUTC = $entry.Timestamp.ToUniversalTime().DateTime;
        if($entry.Name -eq "wait_info")
        {
            $waitRow = $WaitTable.NewRow();
            $waitRow.timestamp = $entryTimestampUTC;
            $waitRow.wait_type = $entry.Fields["wait_type"];
            $waitRow.duration = $entry.Fields["duration"];
            $waitRow.signal_duration = $entry.Fields["signal_duration"];
            $waitRow.wait_resource = $entry.Fields["wait_resource"];
            $waitRow.session_id = $entry.Actions["session_id"];
            $waitRow.opcode = $entry.Fields["opcode"];
            $waitRow.callstack_rva = $entry.Actions["callstack_rva"] ?? [System.DBNull]::Value;
            $WaitTable.Rows.Add($waitRow);

            $WaitCount++;
        }
        #elseif($entry.Name -ne "wait_info"){continue}
        else 
        {
            $xml = [xml]$entry.Fields["data"];
            

            switch($entry.Fields["component"].ToUpper())
            {
                'IO_SUBSYSTEM'
                {
                    $IOCount++;          

                    $statRow = $IOStatsTable.NewRow();
                    $statRow.timestamp = $entryTimestampUTC;
                    $statRow.ioLatchTimeouts = $xml.ioSubsystem.ioLatchTimeouts ?? [System.DBNull]::Value;
                    $statRow.intervalLongIos = $xml.ioSubsystem.intervalLongIos ?? [System.DBNull]::Value;
                    $statRow.totalLongIos = $xml.ioSubsystem.totalLongIos ?? [System.DBNull]::Value;
                    $IOStatsTable.Rows.Add($statRow);

                    foreach($pendingReq in $xml.ioSubsystem.longestPendingRequests.pendingRequest)
                    {
                        $reqRow = $IOPendingReqsTable.NewRow();
                        $reqRow.timestamp = $entryTimestampUTC;
                        $reqRow.duration = $pendingReq.duration ?? [System.DBNull]::Value;
                        $reqRow.filePath = $pendingReq.filePath ?? [System.DBNull]::Value;
                        $reqRow.offset = $pendingReq.offset ?? [System.DBNull]::Value;
                        $reqRow.handle = $pendingReq.handle ?? [System.DBNull]::Value;
                        $IOPendingReqsTable.Rows.Add($reqRow);
                    }

                }
                'QUERY_PROCESSING'
                {
                    $QPCount++;
                
                    # Summary Stats
                    $statRow = $QPStatsTable.NewRow();
                    $statRow.timestamp = $entryTimestampUTC;
                    $statRow.maxWorkers = $xml.queryProcessing.Attributes["maxWorkers"].Value ?? [System.DBNull]::Value;
                    $statRow.workersCreated = $xml.queryProcessing.Attributes["workersCreated"].Value ?? [System.DBNull]::Value;
                    $statRow.tasksCompletedWithinInterval = $xml.queryProcessing.Attributes["tasksCompletedWithinInterval"].Value ?? [System.DBNull]::Value;
                    $statRow.pendingTasks = $xml.queryProcessing.Attributes["pendingTasks"].Value ?? [System.DBNull]::Value;
                    $statRow.oldestPendingTaskWaitingTime = $xml.queryProcessing.Attributes["oldestPendingTaskWaitingTime"].Value ?? [System.DBNull]::Value;
                    $statRow.hasUnresolvableDeadlockOccurred = if($null -eq $xml.hasUnresolvableDeadlockOccurred) {[System.DBNull]::Value} else {(ConvertTo-Bool $xml.hasUnresolvableDeadlockOccurred.ToString().Replace('>','').Replace('<',''))} ;
                    $statRow.hasDeadlockedSchedulersOccurred = $xml.queryProcessing.Attributes["hasDeadlockedSchedulersOccurred"].Value ?? [System.DBNull]::Value;
                    $statRow.trackingNonYieldingScheduler = $xml.queryProcessing.Attributes["trackingNonYieldingScheduler"].Value ?? [System.DBNull]::Value;
                    $QPStatsTable.Rows.Add($statRow);

                    # Waits
                    foreach($waitInfo in $xml.queryProcessing.topWaits.nonPreemptive.byCount.wait)
                    {
                        if($null -ne $waitInfo.waitType -and ($QPWaitsTable.Select("timestamp = '$entryTimestampUTC' AND waitType = '$($waitInfo.waitType)'").Count -eq 0))
                        {
                            $waitRow = $QPWaitsTable.NewRow();
                            $waitRow.timestamp = $entryTimestampUTC;
                            $waitRow.isPreemptive = $false;
                            $waitRow.waitType = $waitInfo.waitType ?? [System.DBNull]::Value;
                            $waitRow.waits = $waitInfo.waits ?? [System.DBNull]::Value;
                            $waitRow.averageWaitTime = $waitInfo.averageWaitTime ?? [System.DBNull]::Value;
                            $waitRow.maxWaitTime = $waitInfo.maxWaitTime ?? [System.DBNull]::Value;
                            $QPWaitsTable.Rows.Add($waitRow);
                        }
                    }
                    foreach($waitInfo in $xml.queryProcessing.topWaits.nonPreemptive.byCount.wait)
                    {
                        if(($null -ne $waitInfo.waitType) -and ($QPWaitsTable.Select("timestamp = '$entryTimestampUTC' AND waitType = '$($waitInfo.waitType)'").Count -eq 0))
                        {
                            $waitRow = $QPWaitsTable.NewRow();
                            $waitRow.timestamp = $entryTimestampUTC;
                            $waitRow.isPreemptive = $false;
                            $waitRow.waitType = $waitInfo.waitType ?? [System.DBNull]::Value;
                            $waitRow.waits = $waitInfo.waits ?? [System.DBNull]::Value;
                            $waitRow.averageWaitTime = $waitInfo.averageWaitTime ?? [System.DBNull]::Value;
                            $waitRow.maxWaitTime = $waitInfo.maxWaitTime ?? [System.DBNull]::Value;
                            $QPWaitsTable.Rows.Add($waitRow);
                        }
                    }
                    foreach($waitInfo in $xml.queryProcessing.topWaits.preemptive.byCount.wait)
                    {
                        if($null -ne $waitInfo.waitType)
                        {
                            $waitRow = $QPWaitsTable.NewRow();
                            $waitRow.timestamp = $entryTimestampUTC;
                            $waitRow.isPreemptive = $true;
                            $waitRow.waitType = $waitInfo.waitType ?? [System.DBNull]::Value;
                            $waitRow.waits = $waitInfo.waits ?? [System.DBNull]::Value;
                            $waitRow.averageWaitTime = $waitInfo.averageWaitTime ?? [System.DBNull]::Value;
                            $waitRow.maxWaitTime = $waitInfo.maxWaitTime ?? [System.DBNull]::Value;
                            $QPWaitsTable.Rows.Add($waitRow);
                        }
                    }
                    foreach($waitInfo in $xml.queryProcessing.topWaits.preemptive.byCount.wait)
                    {
                        if(($null -ne $waitInfo.waitType) -and ($QPWaitsTable.Select("timestamp = '$entryTimestampUTC' AND waitType = '$($waitInfo.waitType)'").Count -eq 0))
                        {
                            $waitRow = $QPWaitsTable.NewRow();
                            $waitRow.timestamp = $entryTimestampUTC;
                            $waitRow.isPreemptive = $true;
                            $waitRow.waitType = $waitInfo.waitType ?? [System.DBNull]::Value;
                            $waitRow.waits = $waitInfo.waits ?? [System.DBNull]::Value;
                            $waitRow.averageWaitTime = $waitInfo.averageWaitTime ?? [System.DBNull]::Value;
                            $waitRow.maxWaitTime = $waitInfo.maxWaitTime ?? [System.DBNull]::Value;
                            $QPWaitsTable.Rows.Add($waitRow);
                        }
                    }

                    # CPU-intensive Requests
                    foreach($cpuRequest in $xml.queryProcessing.cpuIntensiveRequests.request)
                    {
                        $cpuRow = $QPCpuIntReqsTable.NewRow();
                        $cpuRow.timestamp = $entryTimestampUTC;
                        $cpuRow.sessionId = $cpuRequest.sessionId ?? [System.DBNull]::Value;
                        $cpuRow.requestId = $cpuRequest.requestId ?? [System.DBNull]::Value;
                        $cpuRow.command = $cpuRequest.command ?? [System.DBNull]::Value;
                        $cpuRow.taskAddress = $cpuRequest.taskAddress ?? [System.DBNull]::Value;
                        $cpuRow.cpuUtilization = $cpuRequest.cpuUtilization ?? [System.DBNull]::Value;
                        $cpuRow.cpuTimeMs = $cpuRequest.cpuTimeMs ?? [System.DBNull]::Value;
                        $QPCpuIntReqsTable.Rows.Add($cpuRow);
                    }

                    # Blocking Chain
                    foreach($blockReport in $xml.queryProcessing.blockingTasks."blocked-process-report")
                    {
                            $blockRow = $QPBlockingTable.NewRow();
                            $blockRow.timestamp = $entryTimestampUTC;

                            $blockedProc = $blockReport."blocked-process".process;
                            $blockingProc = $blockReport."blocking-process".process;

                            # Extract details from blocked process
                            $blockRow.blockedid = $blockedProc.id ?? [System.DBNull]::Value;
                            $blockRow.blockedstatus = $blockedProc.status ?? [System.DBNull]::Value;
                            $blockRow.blockedtaskpriority = $blockedProc.taskpriority ?? [System.DBNull]::Value;
                            $blockRow.blockedlogused = $blockedProc.logused ?? [System.DBNull]::Value;
                            $blockRow.blockedwaitresource = $blockedProc.waitresource ?? [System.DBNull]::Value;
                            $blockRow.blockedwaittime = $blockedProc.waittime ?? [System.DBNull]::Value;
                            $blockRow.blockedownerId = $blockedProc.ownerId ?? [System.DBNull]::Value;
                            $blockRow.blockedtransactionname = $blockedProc.transactionname ?? [System.DBNull]::Value;
                            $blockRow.blockedlasttranstarted = $blockedProc.lasttranstarted ?? [System.DBNull]::Value;
                            $blockRow.blockedXDES = $blockedProc.XDES ?? [System.DBNull]::Value;
                            $blockRow.blockedlockMode = $blockedProc.lockMode ?? [System.DBNull]::Value;
                            $blockRow.blockedschedulerid = $blockedProc.schedulerid ?? [System.DBNull]::Value;
                            $blockRow.blockedkpid = $blockedProc.kpid ?? [System.DBNull]::Value;
                            $blockRow.blockedspid = $blockedProc.spid ?? [System.DBNull]::Value;
                            $blockRow.blockedsbid = $blockedProc.sbid ?? [System.DBNull]::Value;
                            $blockRow.blockedecid = $blockedProc.ecid ?? [System.DBNULL]::Value;
                            $blockRow.blockedclientapp = $blockedProc.clientapp ?? [System.DBNull]::Value;
                            $blockRow.blockedhostname = $blockedProc.hostname ?? [System.DBNull]::Value;
                            $blockRow.blockedhostpid = $blockedProc.hostpid ?? [System.DBNull]::Value;
                            $blockRow.blockedloginname = $blockedProc.loginname ?? [System.DBNull]::Value;
                            $blockRow.blockedisolationlevel = $blockedProc.isolationlevel ?? [System.DBNull]::Value;
                            $blockRow.blockedxactid = $blockedProc.xactid ?? [System.DBNull]::Value;
                            $blockRow.blockedcurrentdb = $blockedProc.currentdb ?? [System.DBNull]::Value;
                            $blockRow.blockedcurrentdbname = $blockedProc.currentdbname ?? [System.DBNull]::Value;
                            $blockRow.blockedinputbuf = $blockedProc.inputbuf ?? [System.DBNull]::Value;
                            $blockRow.blockedexecutionStack = $blockedProc.executionStack ?? [System.DBNull]::Value;

                            # Extract details from blocking process
                            $blockRow.blockerid = $blockingProc.id ?? [System.DBNull]::Value;
                            $blockRow.blockerstatus = $blockingProc.status ?? [System.DBNull]::Value;
                            $blockRow.blockertaskpriority = $blockingProc.taskpriority ?? [System.DBNull]::Value;
                            $blockRow.blockerlogused = $blockingProc.logused ?? [System.DBNull]::Value;
                            $blockRow.blockerwaitresource = $blockingProc.waitresource ?? [System.DBNull]::Value;
                            $blockRow.blockerwaittime = $blockingProc.waittime ?? [System.DBNull]::Value;
                            $blockRow.blockerownerId = $blockingProc.ownerId ?? [System.DBNull]::Value;
                            $blockRow.blockertransactionname = $blockingProc.transactionname ?? [System.DBNull]::Value;
                            $blockRow.blockerlasttranstarted = $blockingProc.lasttranstarted ?? [System.DBNull]::Value;
                            $blockRow.blockerXDES = $blockingProc.XDES ?? [System.DBNull]::Value;
                            $blockRow.blockerlockMode = $blockingProc.lockMode ?? [System.DBNull]::Value;
                            $blockRow.blockerschedulerid = $blockingProc.schedulerid ?? [System.DBNull]::Value;
                            $blockRow.blockerkpid = $blockingProc.kpid ?? [System.DBNull]::Value;
                            $blockRow.blockerspid = $blockingProc.spid ?? [System.DBNull]::Value;
                            $blockRow.blockersbid = $blockingProc.sbid ?? [System.DBNull]::Value;
                            $blockRow.blockerecid = $blockingProc.ecid ?? [System.DBNull]::Value;
                            $blockRow.blockerclientapp = $blockingProc.clientapp ?? [System.DBNull]::Value;
                            $blockRow.blockerhostname = $blockingProc.hostname ?? [System.DBNull]::Value;
                            $blockRow.blockerhostpid = $blockingProc.hostpid ?? [System.DBNull]::Value;
                            $blockRow.blockerloginname = $blockingProc.loginname ?? [System.DBNull]::Value;
                            $blockRow.blockerisolationlevel = $blockingProc.isolationlevel ?? [System.DBNull]::Value;
                            $blockRow.blockerxactid = $blockingProc.xactid ?? [System.DBNull]::Value;
                            $blockRow.blockercurrentdb = $blockingProc.currentdb ?? [System.DBNull]::Value;
                            $blockRow.blockercurrentdbname = $blockingProc.currentdbname ?? [System.DBNull]::Value;
                            $blockRow.blockerinputbuf = $blockingProc.inputbuf ?? [System.DBNull]::Value;
                            $blockRow.blockerexecutionStack = $blockingProc.executionStack ?? [System.DBNull]::Value;

                            $QPBlockingTable.Rows.Add($blockRow);
                    }
                }
                'RESOURCE'
                {
                    $ResCount++;
                
                    $statRow = $ResStatsTable.NewRow();
                    $statRow.timestamp = $entryTimestampUTC;
                    $statRow.lastNotification = $xml.resource.Attributes["lastNotification"].Value ?? [System.DBNull]::Value;
                    $statRow.outOfMemoryExceptions = $xml.resource.Attributes["outOfMemoryExceptions"].Value ?? [System.DBNull]::Value;
                    $statRow.isAnyPoolOutOfMemory = if($null -eq $xml.resource.Attributes["isAnyPoolOutOfMemory"].Value) {[System.DBNull]::Value} else {(ConvertTo-Bool $xml.resource.Attributes["isAnyPoolOutOfMemory"].Value.Replace('>','').Replace('<',''))} ;
                    $statRow.processOutOfMemoryPeriod = $xml.resource.Attributes["processOutOfMemoryPeriod"].Value ?? [System.DBNull]::Value;
                    $ResStatsTable.Rows.Add($statRow);

                    $memRow = $ResMemReportTable.NewRow();
                    $memRow.timestamp = $entryTimestampUTC;

                    foreach($entry in $xml.resource.memoryReport.entry)
                    {
                        $attr = $entry.Attributes["description"].Value;
                        $val = $entry.Attributes["value"].Value ?? [System.DBNull]::Value;
                        switch($attr)
                        {
                            "Available Physical Memory"
                            {
                                $memRow.AvailablePhysicalMemory = $val;
                                break;
                            }
                            "Available Virtual Memory"
                            {
                                $memRow.AvailableVirtualMemory = $val;
                                break;
                            }
                            "Available Paging File"
                            {
                                $memRow.AvailablePagingFile = $val;
                                break;
                            }
                            "Working Set"
                            {
                                $memRow.WorkingSet = $val;
                                break;
                            }
                            "Percent of Committed Memory in WS"
                            {
                                $memRow.PercentofCommittedMemoryinWS = $val;
                                break;  
                            }
                            "Page Faults"
                            {
                                $memRow.PageFaults = $val;
                                break;
                            }
                            "System physical memory high"
                            {
                                $memRow.Systemphysicalmemoryhigh = if([System.DBNull]::Value -eq $val) {$val} else {(ConvertTo-Bool $val)} ;
                                break;
                            }
                            "System physical memory low"
                            {
                                $memRow.Systemphysicalmemorylow = if([System.DBNull]::Value -eq $val) {$val} else {(ConvertTo-Bool $val)} ;
                                break;
                            }
                            "Process physical memory low"
                            {
                                $memRow.Processphysicalmemorylow = if([System.DBNull]::Value -eq $val) {$val} else {(ConvertTo-Bool $val)} ;
                                break;
                            }
                            "Process virtual memory low"
                            {
                                $memRow.Processvirtualmemorylow = if([System.DBNull]::Value -eq $val) {$val} else {(ConvertTo-Bool $val)} ;
                                break;
                            }
                            "VM Reserved"
                            {
                                $memRow.VMReserved = $val;
                                break;
                            }
                            "VM Committed"
                            {
                                $memRow.VMCommitted = $val;
                                break;
                            }
                            "Locked Pages Allocated" 
                            {
                                $memRow.LockedPagesAllocated = $val;
                                break;
                            }
                            "Large Pages Allocated" 
                            {
                                $memRow.LargePagesAllocated = $val;
                                break;
                                
                            } 
                            "Emergency Memory"      
                            {
                                $memRow.EmergencyMemory = $val;
                                break;
                                
                            } 
                            "Emergency Memory In Use"
                            {
                                $memRow.EmergencyMemoryinUse = $val;
                                break;
                                }
                            "Target Committed"       
                            {
                                $memRow.TargetCommitted = $val;
                                break;
                                }
                            "Current Committed"      
                            {
                                $memRow.CurrentCommitted = $val;
                                break;
                                }
                            "Pages Allocated"        
                            {
                                $memRow.PagesAllocated = $val;
                                break;
                                }
                            "Pages Reserved"         
                            {
                                $memRow.PagesReserved = $val;
                                break;
                            }
                            "Pages Free"             
                            {
                                $memRow.PagesFree = $val;
                                break;
                                }
                            "Pages In Use"           
                            {
                                $memRow.PagesInUse = $val;
                                break;
                                }
                            "Page Alloc Potential"   
                            {
                                $memRow.PageAllocPotential = $val;
                                break;
                                }
                            "NUMA Growth Phase"      
                            {
                                $memRow.NUMAGrowthPhase = $val;
                                break;
                                }
                            "Last OOM Factor"        
                            {
                                $memRow.LastOOMFactor = $val;
                                break;
                                }
                            "Last OS Error"          
                            {
                                $memRow.LastOSError = $val;
                                break;
                            }
                            default {}

                        }
                    }

                    
                    $ResMemReportTable.Rows.Add($memRow);
                }
                'SYSTEM'
                {
                    $SysCount++;
                
                    $sysRow = $SysTable.NewRow();
                    $sysRow.Timestamp = $entryTimestampUTC;
                    $sysRow.spinlockBackoffs = $xml.system.Attributes["spinlockBackoffs"].Value ?? [System.DBNull]::Value;
                    $sysRow.sickSpinlockType = $xml.system.Attributes["sickSpinlockType"].Value ?? [System.DBNull]::Value;
                    $sysRow.sickSpinlockTypeAfterAv = $xml.system.Attributes["sickSpinlockTypeAfterAv"].Value ?? [System.DBNull]::Value;
                    $sysRow.latchWarnings = $xml.system.Attributes["latchWarnings"].Value ?? [System.DBNull]::Value;
                    $sysRow.isAccessViolationOccurred = (ConvertTo-Bool $xml.system.Attributes["isAccessViolationOccurred"].Value.ToString().Replace('<','').Replace('>','')) ?? [System.DBNull]::Value;
                    $sysRow.writeAccessViolationCount = $xml.system.Attributes["writeAccessViolationCount"].Value ?? [System.DBNull]::Value;
                    $sysRow.totalDumpRequests = $xml.system.Attributes["totalDumpRequests"].Value ?? [System.DBNull]::Value;
                    $sysRow.intervalDumpRequests = $xml.system.Attributes["intervalDumpRequests"].Value ?? [System.DBNull]::Value;
                    $sysRow.nonYieldingTasksReported = $xml.system.Attributes["nonYieldingTasksReported"].Value ?? [System.DBNull]::Value;
                    $sysRow.pageFaults = $xml.system.Attributes["pageFaults"].Value ?? [System.DBNull]::Value;
                    $sysRow.systemCpuUtilization = $xml.system.Attributes["systemCpuUtilization"].Value ?? [System.DBNull]::Value;
                    $sysRow.sqlCpuUtilization = $xml.system.Attributes["sqlCpuUtilization"].Value ?? [System.DBNull]::Value;
                    $sysRow.BadPagesDetected = $xml.system.Attributes["BadPagesDetected"].Value ?? [System.DBNull]::Value;
                    $sysRow.BadPagesFixed = $xml.system.Attributes["BadPagesFixed"].Value ?? [System.DBNull]::Value;
                    $sysRow.LastBadPageAddress = $xml.system.Attributes["LastBadPageAddress"].Value ?? [System.DBNull]::Value;
                    $SysTable.Rows.Add($sysRow);
                }
                default
                {
                    $OthCount++;
                }
            }
        }
    }

    #Load data into SQL Server after each file complete

    Write-Progress -Activity "Loading data into SQL Server" -CurrentOperation $xelfile
    foreach($table in $Tables)
    {
        Write-Progress -Activity "Loading data into SQL Server" -CurrentOperation $xelfile  -Status $table.TableName -PercentComplete 0
        $table | Write-SqlTableData -ServerInstance $SqlSrv -DatabaseName $Db -SchemaName $Schema -TableName $table.TableName -Force

        $table.Clear();
        Write-Progress -Activity "Loading data into SQL Server" -CurrentOperation $xelfile -Status $table.TableName -PercentComplete 100
    }
    Write-Progress -Activity "Loading data into SQL Server" -CurrentOperation $xelfile -PercentComplete 100 -Completed
}

"QPCount: $QPCount; ResCount: $ResCount; IOCount: $IOCount; SysCount: $SysCount; WaitCount: $WaitCount; WTFCount: $OthCount" | Out-Host

$QPStatsTable | Format-Table | Out-Host
