

 ![image](https://github.com/1collin/CollinsSQLSharing/assets/151403673/afe2c5af-f450-4b59-a72f-809225bedb18)


![image](https://github.com/1collin/CollinsSQLSharing/assets/151403673/e19cc6d0-c279-4fb2-ab5f-469a7c8f18a5)

 
```Text
************* Preparing the environment for Debugger Extensions Gallery repositories **************
   ExtensionRepository : Implicit
   UseExperimentalFeatureForNugetShare : true
   AllowNugetExeUpdate : true
   NonInteractiveNuget : true
   AllowNugetMSCredentialProviderInstall : true
   AllowParallelInitializationOfLocalRepositories : true

   EnableRedirectToV8JsProvider : false

   -- Configuring repositories
      ----> Repository : LocalInstalled, Enabled: true
      ----> Repository : UserExtensions, Enabled: true

>>>>>>>>>>>>> Preparing the environment for Debugger Extensions Gallery repositories completed, duration 0.000 seconds

************* Waiting for Debugger Extensions Gallery to Initialize **************

>>>>>>>>>>>>> Waiting for Debugger Extensions Gallery to Initialize completed, duration 0.031 seconds
   ----> Repository : UserExtensions, Enabled: true, Packages count: 0
   ----> Repository : LocalInstalled, Enabled: true, Packages count: 41

Microsoft (R) Windows Debugger Version 10.0.27553.1004 AMD64
Copyright (c) Microsoft Corporation. All rights reserved.


Loading Dump File [C:\Program Files\Microsoft SQL Server\MSSQL15.SQL2019\MSSQL\Log\SQLDump0005.mdmp]
Comment: 'Stack Trace'
Comment: 'Non-yielding Scheduler'
Comment: '<Identity><Element key="BranchName" val="sql2019_rtm_qfe-cu25"/><Element key="OfficialBuild" val="true"/><Element key="BuildFlavor" val="Release (GoldenBits)"/><Element key="QBuildGuid" val="3f1db23d-d659-6a78-e366-b3186ac817c3"/><Element key="QBuildSyncChangeset" val="ae8322e7aba0dcea71a6da235b07c0d28012d7e5"/></Identity>'
User Mini Dump File: Only registers, stack and portions of memory are available


************* Path validation summary **************
Response                         Time (ms)     Location
Deferred                                       srv*
Deferred                                       srv*C:\Tools\Debuggers\Symbols*https://msdl.microsoft.com/download/symbols
Symbol search path is: srv*;srv*C:\Tools\Debuggers\Symbols*https://msdl.microsoft.com/download/symbols
Executable search path is: 
Windows 10 Version 14393 MP (14 procs) Free x64
Product: Server, suite: TerminalServer DataCenter SingleUserTS
Edition build lab: 10.0.14393.6343 (rs1_release.230913-1727)
Debug session time: Tue Oct  3 08:48:33.000 2023 (UTC - 7:00)
System Uptime: 0 days 3:10:37.798
Process Uptime: 0 days 3:09:59.000
................................................................
................................................................
................................................................
..........................
Loading unloaded module list
....................
This dump file has an exception of interest stored in it.
The stored exception information can be accessed via .ecxr.
(d60.ef8): Unknown exception - code 00000000 (first/second chance not available)
For analysis of this file, run !analyze -v
----------------------------------------------------------------------------
The user dump currently examined is a minidump. Consequently, only a subset
of sos.dll functionality will be available. If needed, attaching to the live
process or debugging a full dump will allow access to sos.dll's full feature
set.
To create a full user dump use the command: .dump /ma <filename>
----------------------------------------------------------------------------
*** WARNING: Unable to verify timestamp for sqlservr.exe
ntdll!NtWaitForSingleObject+0x14:
00007ffa`4ab95d14 c3              ret
```

Notice that as soon as you open the user-mode process memory dump, there is useful contextual information printed. This may include but is not limited to a comment indicating what triggered the memory dump, the symbol path in use, Windows build and edition, the number of CPUs on the machine, the time at which the memory dump generated with UTC offset, and the amount of time both Windows and the process have been up.

Notice also that there’s the default srv*; before the symbol path I set. This means that symbols won’t be cached where I said, but instead in the default location (probably C:\ProgramData\Dbg\sym). If you’re cool with that, no problem. I like having symbols put in other places so I’m going to change that:

 ```Text
************* Path validation summary **************
Response                         Time (ms)     Location
Deferred                                       srv*C:\Tools\Debuggers\Symbols*https://msdl.microsoft.com/download/symbols

That’s better.
Since it’s often of interest, I’ll then check the SQL Server version:
0:090> lmvm sqlservr
Browse full module list
start             end                 module name
00007ff7`2d150000 00007ff7`2d1ef000   sqlservr   (pdb symbols)          c:\tools\debuggers\symbols\sqlservr.pdb\307419EC4ECA42E291D95A2C2076C3872\sqlservr.pdb
    Loaded symbol image file: sqlservr.exe
    Mapped memory image file: C:\Program Files\Microsoft SQL Server\MSSQL15.SQL2019\MSSQL\Binn\sqlservr.exe
    Image path: C:\Program Files\Microsoft SQL Server\MSSQL15.SQL2019\MSSQL\Binn\sqlservr.exe
    Image name: sqlservr.exe
    Browse all global symbols  functions  data
    Timestamp:        Tue Jan 30 18:21:13 2024 (65B9AE99)
    CheckSum:         0009FC5C
    ImageSize:        0009F000
    File version:     2019.150.4355.3
    Product version:  15.0.4355.3
    File flags:       0 (Mask 3F)
    File OS:          40004 NT Win32
    File type:        0.0 Unknown
    File date:        00000000.00000000
    Translations:     0409.04b0
    Information from resource tables:
        CompanyName:      Microsoft Corporation
        ProductName:      Microsoft SQL Server
        InternalName:     SQLSERVR
        OriginalFilename: SQLSERVR.EXE
        ProductVersion:   15.0.4355.3
        FileVersion:      2019.0150.4355.03 ((sql2019_rtm_qfe-cu25).240130-2314)
        FileDescription:  SQL Server Windows NT - 64 Bit
        LegalCopyright:   Microsoft. All rights reserved.
        LegalTrademarks:  Microsoft SQL Server is a registered trademark of Microsoft Corporation.
        Comments:         SQL
```
Once the memory dump is loaded, I like to execute !uniqstack.  This will show all of the thread callstacks, with common stacks grouped together. Not only does it give an idea of what SQL Server was busy doing (or not doing) at the time of memory dump generation, but it also triggers load of most symbols 😊. That means after this command completes, most others will be very fast since they won’t need to wait for symbol load. The output is very large, so I’m going to omit that here.

I’ll then look for the thread which triggered the memory dump. In this case I can see it’s this:

```Text
. 35  Id: c88.10d4 Suspend: 0 Teb: 00000098`19865000 Unfrozen
      Start: sqldk!SchedulerManager::ThreadEntryPoint (00007ffe`e81c97d0)
      Priority: 1  Priority class: 32  Affinity: 3c00
 # Child-SP          RetAddr               Call Site
00 00000098`1f1db858 00007ffe`f49b6d1f     ntdll!NtWaitForSingleObject+0x14
01 00000098`1f1db860 00007ff7`2d17bdae     KERNELBASE!WaitForSingleObjectEx+0x8f
02 00000098`1f1db900 00007ff7`2d17ba83     sqlservr!CDmpDump::InvokeSqlDumper+0x28e
03 00000098`1f1dbaa0 00007ff7`2d17b784     sqlservr!CDmpDump::DumpInternal+0x1b3
04 00000098`1f1dbb50 00007ffe`e2752273     sqlservr!CDmpDump::Dump+0x24
05 00000098`1f1dbb90 00007ffe`e33f6d95     sqllang!SQLDumperLibraryInvoke+0x1f3
06 00000098`1f1dbbd0 00007ffe`e33f7c86     sqllang!SQLLangDumperLibraryInvoke+0x185
07 00000098`1f1dbc90 00007ffe`e33c2832     sqllang!CImageHelper::DoMiniDump+0x756
08 00000098`1f1dbeb0 00007ff7`2d153eb5     sqllang!stackTrace+0xa42
09 00000098`1f1dd8d0 00007ffe`e8247e70     sqlservr!SQL_SOSNonYieldSchedulerCallback+0x465
0a 00000098`1f1fdb70 00007ffe`e821e50b     sqldk!SOS_OS::ExecuteNonYieldSchedulerCallbacks+0xe0
0b 00000098`1f1fde20 00007ffe`e81b44af     sqldk!SOS_Scheduler::ExecuteNonYieldSchedulerCallbacks+0x1ab
0c 00000098`1f1fe000 00007ffe`e81b3a42     sqldk!SchedulerMonitor::CheckScheduler+0x25e
0d 00000098`1f1fe1a0 00007ffe`e81b2ea2     sqldk!SchedulerMonitor::CheckSchedulers+0x1ea
0e 00000098`1f1feb10 00007ffe`e82b5f29     sqldk!SchedulerMonitor::Run+0xc2
0f 00000098`1f1fec10 00007ffe`e81aaa33     sqldk!SchedulerMonitor::EntryPoint+0x9
10 00000098`1f1fec40 00007ffe`e81aa6af     sqldk!SOS_Task::Param::Execute+0x232
11 00000098`1f1ff240 00007ffe`e81aa26e     sqldk!SOS_Scheduler::RunTask+0xbf
12 00000098`1f1ff2b0 00007ffe`e81c9bf2     sqldk!SOS_Scheduler::ProcessTasks+0x39d
13 00000098`1f1ff3d0 00007ffe`e81c949f     sqldk!SchedulerManager::WorkerEntryPoint+0x2a1
14 00000098`1f1ff4a0 00007ffe`e81c9a28     sqldk!SystemThreadDispatcher::ProcessWorker+0x42a
15 00000098`1f1ff7a0 00007ffe`f75d84d4     sqldk!SchedulerManager::ThreadEntryPoint+0x404
16 00000098`1f1ff890 00007ffe`f7cf1791     kernel32!BaseThreadInitThunk+0x14
17 00000098`1f1ff8c0 00000000`00000000     ntdll!RtlUserThreadStart+0x21
```
Then I’ll switch to the context of that thread.

```diff
0:090> ~35s
ntdll!NtWaitForSingleObject+0x14:
00007ffe`f7d45ea4 c3              ret
0:035> kL
 # Child-SP          RetAddr               Call Site
00 00000098`1f1db858 00007ffe`f49b6d1f     ntdll!NtWaitForSingleObject+0x14
01 00000098`1f1db860 00007ff7`2d17bdae     KERNELBASE!WaitForSingleObjectEx+0x8f
02 00000098`1f1db900 00007ff7`2d17ba83     sqlservr!CDmpDump::InvokeSqlDumper+0x28e
03 00000098`1f1dbaa0 00007ff7`2d17b784     sqlservr!CDmpDump::DumpInternal+0x1b3
04 00000098`1f1dbb50 00007ffe`e2752273     sqlservr!CDmpDump::Dump+0x24
05 00000098`1f1dbb90 00007ffe`e33f6d95     sqllang!SQLDumperLibraryInvoke+0x1f3
06 00000098`1f1dbbd0 00007ffe`e33f7c86     sqllang!SQLLangDumperLibraryInvoke+0x185
07 00000098`1f1dbc90 00007ffe`e33c2832     sqllang!CImageHelper::DoMiniDump+0x756
08 00000098`1f1dbeb0 00007ff7`2d153eb5     sqllang!stackTrace+0xa42
09 00000098`1f1dd8d0 00007ffe`e8247e70     sqlservr!SQL_SOSNonYieldSchedulerCallback+0x465
0a 00000098`1f1fdb70 00007ffe`e821e50b     sqldk!SOS_OS::ExecuteNonYieldSchedulerCallbacks+0xe0
0b 00000098`1f1fde20 00007ffe`e81b44af     sqldk!SOS_Scheduler::ExecuteNonYieldSchedulerCallbacks+0x1ab
0c 00000098`1f1fe000 00007ffe`e81b3a42     sqldk!SchedulerMonitor::CheckScheduler+0x25e
0d 00000098`1f1fe1a0 00007ffe`e81b2ea2     sqldk!SchedulerMonitor::CheckSchedulers+0x1ea
0e 00000098`1f1feb10 00007ffe`e82b5f29     sqldk!SchedulerMonitor::Run+0xc2
0f 00000098`1f1fec10 00007ffe`e81aaa33     sqldk!SchedulerMonitor::EntryPoint+0x9
10 00000098`1f1fec40 00007ffe`e81aa6af     sqldk!SOS_Task::Param::Execute+0x232
11 00000098`1f1ff240 00007ffe`e81aa26e     sqldk!SOS_Scheduler::RunTask+0xbf
12 00000098`1f1ff2b0 00007ffe`e81c9bf2     sqldk!SOS_Scheduler::ProcessTasks+0x39d
13 00000098`1f1ff3d0 00007ffe`e81c949f     sqldk!SchedulerManager::WorkerEntryPoint+0x2a1
14 00000098`1f1ff4a0 00007ffe`e81c9a28     sqldk!SystemThreadDispatcher::ProcessWorker+0x42a
15 00000098`1f1ff7a0 00007ffe`f75d84d4     sqldk!SchedulerManager::ThreadEntryPoint+0x404
16 00000098`1f1ff890 00007ffe`f7cf1791     kernel32!BaseThreadInitThunk+0x14
17 00000098`1f1ff8c0 00000000`00000000     ntdll!RtlUserThreadStart+0x21
```

Since this is a non-yield, I know that I need to find the non-yield thread information and see what is up with that thread. This is where the SQL Server ERRORLOG makes it easy:

```Log
2024-06-06 06:37:03.59 Server      Process 0:0:0 (0x1b54) Worker 0x0000021718116160 appears to be non-yielding on Scheduler 12. Thread creation time: 13362143230293. Approx Thread CPU Used: kernel 0 ms, user 0 ms. Process Utilization 0%. System Idle 96%. Interval: 70314 ms.
```

```Text
0:035> ~~[0x1b54]s
ntdll!RtlUnwindEx+0x467:
00007ffe`f7cd5447 4803ca          add     rcx,rdx
0:090> kL
 # Child-SP          RetAddr               Call Site
00 00000098`264758c0 00007ffe`ea23f5ae     ntdll!RtlUnwindEx+0x467
01 00000098`26475fa0 00007ffe`ea232bf5     VCRUNTIME140!__FrameHandler3::UnwindNestedFrames+0xee
02 00000098`26476090 00007ffe`ea23300d     VCRUNTIME140!CatchIt<__FrameHandler3>+0xb9
03 00000098`26476130 00007ffe`ea234024     VCRUNTIME140!FindHandler<__FrameHandler3>+0x329
04 00000098`264762a0 00007ffe`ea23fa21     VCRUNTIME140!__InternalCxxFrameHandler<__FrameHandler3>+0x208
05 00000098`26476300 00007ffe`e23fe20c     VCRUNTIME140!__CxxFrameHandler3+0x71
06 00000098`26476350 00007ffe`f7d4a8bd     sqllang!_GSHandlerCheck_EH+0x64
07 00000098`26476380 00007ffe`f7cd49d3     ntdll!RtlpExecuteHandlerForException+0xd
08 00000098`264763b0 00007ffe`f7cd66e9     ntdll!RtlDispatchException+0x373
09 00000098`26476ab0 00007ffe`f49b6ea8     ntdll!RtlRaiseException+0x2d9
0a 00000098`26477290 00007ffe`ea236480     KERNELBASE!RaiseException+0x68
0b 00000098`26477370 00007ffe`e81c4af3     VCRUNTIME140!_CxxThrowException+0x90
0c 00000098`264773d0 00007ffe`e81c4829     sqldk!TurnUnwindAndThrowImpl+0x40f
0d 00000098`264777f0 00007ffe`e81c4b5e     sqldk!SOS_OS::TurnUnwindAndThrow+0x9
0e 00000098`26477820 00007ffe`e3bd930d     sqldk!ExceptionPassOn+0x4a
0f 00000098`26477870 00007ffe`ea231030     sqllang!`CXStmtAssignBase::XretExecute'::`1'::catch$2+0x3d
10 00000098`264778d0 00007ffe`ea234608     VCRUNTIME140!_CallSettingFrame+0x20
11 00000098`26477900 00007ffe`f7d49f03     VCRUNTIME140!__FrameHandler3::CxxCallCatchBlock+0xe8
12 00000098`264779b0 00007ffe`e23d861b     ntdll!RcConsolidateFrames+0x3
13 00000098`2647c3b0 00007ffe`e23bb2a2     sqllang!CXStmtAssignBase::XretExecute+0x2f3
14 00000098`2647c490 00007ffe`e23bacdc     sqllang!CMsqlExecContext::ExecuteStmts<1,1>+0x8fb
15 00000098`2647d030 00007ffe`e23ba1a5     sqllang!CMsqlExecContext::FExecute+0x946
16 00000098`2647e010 00007ffe`e23c5465     sqllang!CSQLSource::Execute+0xbc3
17 00000098`2647e310 00007ffe`e23c30a6     sqllang!process_request+0xdf3
18 00000098`2647ea60 00007ffe`e23c31c3     sqllang!process_commands_internal+0x4b7
19 00000098`2647eb90 00007ffe`e81aaa33     sqllang!process_messages+0x193
1a 00000098`2647ed50 00007ffe`e81aa6af     sqldk!SOS_Task::Param::Execute+0x232
1b 00000098`2647f350 00007ffe`e81aa26e     sqldk!SOS_Scheduler::RunTask+0xbf
1c 00000098`2647f3c0 00007ffe`e81c9bf2     sqldk!SOS_Scheduler::ProcessTasks+0x39d
1d 00000098`2647f4e0 00007ffe`e81c949f     sqldk!SchedulerManager::WorkerEntryPoint+0x2a1
1e 00000098`2647f5b0 00007ffe`e81c9a28     sqldk!SystemThreadDispatcher::ProcessWorker+0x42a
1f 00000098`2647f8b0 00007ffe`f75d84d4     sqldk!SchedulerManager::ThreadEntryPoint+0x404
20 00000098`2647f9a0 00007ffe`f7cf1791     kernel32!BaseThreadInitThunk+0x14
21 00000098`2647f9d0 00000000`00000000     ntdll!RtlUserThreadStart+0x21
```

This thread was executing an adhoc batch (as opposed to RPC), and the statement being executed was performing variable assignment when it encountered an exception.

That’s as far as I’m going to take it here – I know that the exception was caused by me pausing the thread with Process Explorer 😊 (notice that there is 0 user mode and 0 kernel mode time).
