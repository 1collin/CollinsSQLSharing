
/*PSSDiag Environment info collection
* This script should produce copy/paste-able results when output directed
* to text or to grid. It collects information about the SQL Server, OS,
* and machine including names, versions, and some configuration info.
* 
* Author: cbenkler
* Created 2015
* Last Modified: 
*
*     Oct 2023 - added UTC offset to Machine Info section
*     Oct 2023 - delineated between PerfStats and XE trace times in header
*     Sept. 2023 - added Always On config section
*/
DECLARE @tbl_IMPORTEDFILES_Exists bit;
DECLARE @tbl_PowerPlan_Exists bit;
DECLARE @tbl_REQUESTS_Exists bit;
DECLARE @tbl_ServerProperties_Exists bit;
DECLARE @tbl_StartupParameters_Exists bit;
DECLARE @tbl_SPCONFIGURE_Exists bit;
DECLARE @tbl_Sys_Configurations_Exists bit;
DECLARE @tbl_XPMSVER_Exists bit;
DECLARE @tbl_SCRIPT_ENVIRONMENT_DETAILS_Exists bit;
DECLARE @tbl_hadr_ag_replica_states_Exists bit;
DECLARE @tbl_hadr_ag_database_replica_states_Exists bit;
DECLARE @tbl_server_times_Exists bit;
DECLARE @rt_tblBatches_Exists bit;
SET @tbl_IMPORTEDFILES_Exists = (SELECT CASE WHEN (SELECT OBJECT_ID('[dbo].[tbl_IMPORTEDFILES]')) IS NOT NULL THEN 1 ELSE 0 END);
SET @tbl_PowerPlan_Exists = (SELECT CASE WHEN (SELECT OBJECT_ID('[dbo].[tbl_PowerPlan]')) IS NOT NULL THEN 1 ELSE 0 END);
SET @tbl_REQUESTS_Exists = (SELECT CASE WHEN (SELECT OBJECT_ID('[dbo].[tbl_REQUESTS]')) IS NOT NULL THEN 1 ELSE 0 END);
SET @tbl_ServerProperties_Exists = (SELECT CASE WHEN (SELECT OBJECT_ID('[dbo].[tbl_ServerProperties]')) IS NOT NULL THEN 1 ELSE 0 END);
SET @tbl_StartupParameters_Exists = (SELECT CASE WHEN (SELECT OBJECT_ID('[dbo].[tbl_StartupParameters]')) IS NOT NULL THEN 1 ELSE 0 END);
SET @tbl_SPCONFIGURE_Exists = (SELECT CASE WHEN (SELECT OBJECT_ID('[dbo].[tbl_SPCONFIGURE]')) IS NOT NULL THEN 1 ELSE 0 END);
SET @tbl_Sys_Configurations_Exists = (SELECT CASE WHEN (SELECT OBJECT_ID('[dbo].[tbl_Sys_Configurations]')) IS NOT NULL THEN 1 ELSE 0 END);
SET @tbl_XPMSVER_Exists = (SELECT CASE WHEN (SELECT OBJECT_ID('[dbo].[tbl_XPMSVER]')) IS NOT NULL THEN 1 ELSE 0 END);
SET @tbl_SCRIPT_ENVIRONMENT_DETAILS_Exists = (SELECT CASE WHEN (SELECT OBJECT_ID('[dbo].[tbl_SCRIPT_ENVIRONMENT_DETAILS]')) IS NOT NULL THEN 1 ELSE 0 END);
SET @tbl_hadr_ag_replica_states_Exists = (SELECT CASE WHEN (SELECT OBJECT_ID('[dbo].[tbl_hadr_ag_replica_states]')) IS NOT NULL THEN 1 ELSE 0 END);
SET @tbl_hadr_ag_database_replica_states_Exists = (SELECT CASE WHEN (SELECT OBJECT_ID('[dbo].[tbl_hadr_ag_database_replica_states]')) IS NOT NULL THEN 1 ELSE 0 END);
SET @tbl_server_times_Exists = (SELECT CASE WHEN (SELECT OBJECT_ID('[dbo].[tbl_server_times]')) IS NOT NULL THEN 1 ELSE 0 END);
SET @rt_tblBatches_Exists = (SELECT CASE WHEN (SELECT OBJECT_ID('[ReadTrace].[tblBatches]')) IS NOT NULL THEN 1 ELSE 0 END);
DECLARE @selectString NVARCHAR(MAX);
SET @selectString = '
              SELECT ''---------------------------------------------''
              UNION ALL 
              SELECT ''PSSDIAG ANALYSIS:''
              UNION ALL 
              SELECT ''---------------------------------------------'''
IF @tbl_IMPORTEDFILES_Exists = 1
BEGIN
       SET @selectString = @selectString + '
              UNION ALL
              SELECT input_file_name
              FROM [dbo].[tbl_IMPORTEDFILES]
              '
END
IF @tbl_REQUESTS_Exists = 1
BEGIN
       SET @selectString = @selectString + '
              UNION ALL
              SELECT ''''
              UNION ALL
              SELECT ''Perfstats duration: approximately '' + CAST(DATEDIFF(minute, MIN(runtime), MAX(runtime)) as nvarchar) + '' minutes''
              FROM [dbo].[tbl_REQUESTS]
              UNION ALL
              SELECT ''     Approximate start time: '' + CAST(MIN(runtime) as nvarchar(19))
              FROM [dbo].[tbl_REQUESTS]
              UNION ALL
              SELECT ''     Approximate end time: '' + CAST(MAX(runtime) as nvarchar(19))
              FROM [dbo].[tbl_REQUESTS]
       '
END
IF @rt_tblBatches_Exists = 1
BEGIN
    SET @selectString = @selectString + '
        UNION ALL
        SELECT ''''
        UNION ALL
        SELECT ''XE trace duration: approximately '' + CAST(CAST(DATEDIFF(SECOND, MIN(EndTime), MAX(EndTime))/60.0 AS DECIMAL(18,2)) AS NVARCHAR) + '' minutes''
        FROM [ReadTrace].[tblBatches]
        UNION ALL
        SELECT ''     First XE timestamp: '' + CONVERT(NVARCHAR, MIN(EndTime), 121)
        FROM [ReadTrace].[tblBatches]
        UNION ALL
        SELECT ''     Last XE timestamp: '' + CONVERT(NVARCHAR, MAX(EndTime), 121)
        FROM [ReadTrace].[tblBatches]
    '
END
IF (@tbl_ServerProperties_Exists = 1 OR @tbl_SCRIPT_ENVIRONMENT_DETAILS_Exists = 1)
BEGIN
        SET @selectString = @selectString + '
              UNION ALL
              SELECT ''====================================================================================''
              UNION ALL 
              SELECT ''''
              UNION ALL
              SELECT ''SQL Server Info:''
              UNION ALL
              SELECT ''---------------------------------------''
              UNION ALL
              SELECT ''Server name: '' + *_PROPERTY_VALUE_COLUMN_* 
              FROM *_ENVIRONMENT_INFORMATION_TABLE_* 
              WHERE *_PROPERTY_NAME_COLUMN_* = ''SQLServerName'' OR *_PROPERTY_NAME_COLUMN_* = ''SQL Server Name''
              UNION ALL
              SELECT ''Build: '' + *_PROPERTY_VALUE_COLUMN_* 
              FROM  *_ENVIRONMENT_INFORMATION_TABLE_* 
              WHERE *_PROPERTY_NAME_COLUMN_* = ''ProductVersion'' OR *_PROPERTY_NAME_COLUMN_* = ''SQL Version (SP)''
              UNION ALL
              SELECT ''Edition: '' + *_PROPERTY_VALUE_COLUMN_* 
              FROM  *_ENVIRONMENT_INFORMATION_TABLE_* 
              WHERE *_PROPERTY_NAME_COLUMN_* = ''Edition''
              UNION ALL
              SELECT ''Last SQL Server restart: '' + *_PROPERTY_VALUE_COLUMN_*
              FROM  *_ENVIRONMENT_INFORMATION_TABLE_* 
              WHERE *_PROPERTY_NAME_COLUMN_* = ''sqlserver_start_time''
              UNION ALL
              SELECT ''''
              UNION ALL
              SELECT ''Machine Info:''
              UNION ALL
              SELECT ''---------------------------------------''
       '
END
IF @tbl_XPMSVER_Exists = 1
BEGIN
       SET @selectString = @selectString + '
              UNION ALL
              SELECT ''Windows: '' + Character_Value 
              FROM [dbo].[tbl_XPMSVER]
              WHERE Name = ''WindowsVersion''
       '
END 
IF  (@tbl_ServerProperties_Exists = 1 OR @tbl_SCRIPT_ENVIRONMENT_DETAILS_Exists = 1)
BEGIN
       SET @selectString = @selectString + '
              UNION ALL
              SELECT ''Machine Name: '' + *_PROPERTY_VALUE_COLUMN_*
              FROM *_ENVIRONMENT_INFORMATION_TABLE_*
              WHERE *_PROPERTY_NAME_COLUMN_* = ''ComputerNamePhysicalNetBIOS'' OR *_PROPERTY_NAME_COLUMN_* = ''Machine Name''
       '
END
IF  @tbl_PowerPlan_Exists = 1
BEGIN
       SET @selectString = @selectString + '
              UNION ALL
              SELECT ''Power Plan: '' + ActivePlanName
              FROM [dbo].[tbl_PowerPlan]
       '
END
IF  @tbl_ServerProperties_Exists = 1
BEGIN
       SET @selectString = @selectString + '
              UNION ALL
              SELECT ''Logical CPU Count: '' + PropertyValue
              FROM [dbo].[tbl_ServerProperties]
              WHERE PropertyName = ''cpu_count''
              UNION ALL
              SELECT ''NUMA nodes: '' + PropertyValue
              FROM [dbo].[tbl_ServerProperties]
              WHERE PropertyName = ''number of visible numa nodes''
              '
END
IF @tbl_XPMSVER_Exists = 1
BEGIN
       SET @selectString = @selectString + '
              UNION ALL
              SELECT ''RAM Installed: '' + SUBSTRING(Character_Value, 1, (CHARINDEX(''('',Character_Value)-1)) + ''MB''
              FROM [dbo].[tbl_XPMSVER]
              WHERE Name = ''PhysicalMemory''
              UNION ALL
              SELECT ''''
       '
END 
IF  @tbl_ServerProperties_Exists = 1
BEGIN
       SET @selectString = @selectString + '
              UNION ALL
              SELECT ''Last Reboot: '' + PropertyValue
              FROM [dbo].[tbl_ServerProperties]
              WHERE PropertyName = ''machine start time''
       '
END 
IF  @tbl_server_times_Exists = 1
BEGIN
       SET @selectString = @selectString + '
              UNION ALL
              SELECT TOP(1) ''UTC Offset:'' + CAST(DATEDIFF(HOUR, utc_time, server_time) AS VARCHAR)
              FROM dbo.tbl_server_times
              UNION ALL
              SELECT ''''
       '
END
ELSE BEGIN
    SET @selectString = @selectString + '
              UNION ALL
              SELECT ''''
        '
END
IF  @tbl_StartupParameters_Exists = 1
BEGIN
       SET @selectString = @selectString + '
              UNION ALL
              SELECT ''Startup Parameters:''
              UNION ALL
              SELECT ''------------------------------------------------''
              UNION ALL
              SELECT ArgsValue
              FROM [dbo].[tbl_StartupParameters]
              WHERE ArgsValue like ''-T%'' or ArgsValue like ''-Y%''
              UNION ALL
              SELECT ''''
       '
END
IF  (@tbl_Sys_Configurations_Exists = 1 OR @tbl_SPCONFIGURE_Exists = 1)
BEGIN
       SET @selectString = @selectString + '
              UNION ALL
              SELECT ''Configuration values commonly of interest:''
              UNION ALL
              SELECT ''---------------------------------------------------------------------''
              UNION ALL
              SELECT (name + '': '' + CAST(*_SP_CONFIG_VALUE_COLUMN_* as nvarchar))
              FROM *_SQL_CONFIGURATION_TABLE_*
              WHERE name in (''affinity mask'', ''cost threshold for parallelism'', ''max degree of parallelism'',  ''max server memory (MB)'', ''max worker threads'', ''min memory per query (KB)'', ''min server memory (MB)'', ''network packet size (B)'', ''optimize for ad hoc workloads'')
       '
END
IF @tbl_ServerProperties_Exists = 1 
BEGIN
    SET @selectString = REPLACE(@selectString, '*_ENVIRONMENT_INFORMATION_TABLE_*','[dbo].[tbl_ServerProperties]');
    SET @selectString = REPLACE(@selectString, '*_PROPERTY_NAME_COLUMN_*','PropertyName');
    SET @selectString = REPLACE(@selectString, '*_PROPERTY_VALUE_COLUMN_*','PropertyValue');
END
ELSE IF @tbl_SCRIPT_ENVIRONMENT_DETAILS_Exists = 1
BEGIN
    SET @selectString = REPLACE(@selectString, '*_ENVIRONMENT_INFORMATION_TABLE_*','[dbo].[tbl_SCRIPT_ENVIRONMENT_DETAILS]');
    SET @selectString = REPLACE(@selectString, '*_PROPERTY_NAME_COLUMN_*','Name');
    SET @selectString = REPLACE(@selectString, '*_PROPERTY_VALUE_COLUMN_*','Value');
END
IF @tbl_Sys_Configurations_Exists = 1 
BEGIN
    SET @selectString = REPLACE(@selectString, '*_SQL_CONFIGURATION_TABLE_*','[dbo].[tbl_Sys_Configurations]');
    SET @selectString = REPLACE(@selectString, '*_SP_CONFIG_VALUE_COLUMN_*','value_in_use');
END
ELSE IF @tbl_SPCONFIGURE_Exists = 1
BEGIN
    SET @selectString = REPLACE(@selectString, '*_SQL_CONFIGURATION_TABLE_*','[dbo].[tbl_SPCONFIGURE]');
    SET @selectString = REPLACE(@selectString, '*_SP_CONFIG_VALUE_COLUMN_*','run_value');
END
IF @tbl_hadr_ag_replica_states_Exists = 1 
BEGIN
    IF EXISTS (SELECT TOP(1) 1 FROM dbo.tbl_hadr_ag_replica_states)
    BEGIN
        SELECT group_name
        INTO #AGs
        FROM dbo.tbl_hadr_ag_replica_states
        DECLARE @cur_ag NVARCHAR(128)
        SELECT TOP(1) @cur_ag = group_name
        FROM #AGs
        ORDER BY group_name
        IF @cur_ag IS NOT NULL
        BEGIN
            SET @selectString = @selectString + '
              UNION ALL
              SELECT ''''
              UNION ALL
              SELECT ''''
              UNION ALL
              SELECT ''Always On Configuration:''
              UNION ALL
              SELECT ''===============================''
              '
        END
        WHILE @cur_ag IS NOT NULL
        BEGIN
            SET @selectString = @selectString + '
              UNION ALL
              SELECT ''''
              UNION ALL
              SELECT ''----------------------------------''
              UNION ALL
              SELECT (''AG: '' + '' ' + @cur_ag + ''')
              UNION ALL
              SELECT ''----------------------------------''
              UNION ALL
              SELECT (''Role: '' + CAST(role_desc as nvarchar))
              FROM dbo.tbl_hadr_ag_replica_states
              WHERE is_local = 1 AND group_name = ''' + @cur_ag + '''
              '
            IF @tbl_hadr_ag_database_replica_states_Exists = 1
            BEGIN
            SET @selectString = @selectString + '
                UNION ALL
                SELECT (''Member Databases: '' + CAST((SELECT STRING_AGG(''['' + database_name + '']'', '', '') 
                    FROM (SELECT DISTINCT database_name
                        FROM dbo.tbl_hadr_ag_database_replica_states) [i]) AS NVARCHAR(4000)))'
            END
            SET @selectString = @selectString + '        
              UNION ALL 
              SELECT (''Availability Mode'' + '': '' + CAST(availability_mode_desc as nvarchar))
              FROM dbo.tbl_hadr_ag_replica_states
              WHERE is_local = 1 AND group_name = ''' + @cur_ag + '''
              UNION ALL 
              SELECT (''Failover Mode'' + '': '' + CAST(failover_mode_desc as nvarchar))
              FROM dbo.tbl_hadr_ag_replica_states
              WHERE is_local = 1 AND group_name = ''' + @cur_ag + '''
              UNION ALL 
              SELECT (''Session Timeout (sec)'' + '': '' + CAST(session_timeout as nvarchar))
              FROM dbo.tbl_hadr_ag_replica_states
              WHERE is_local = 1 AND group_name = ''' + @cur_ag + '''
              UNION ALL 
              SELECT (''Sync Health'' + '': '' + CAST(synchronization_health_desc as nvarchar))
              FROM dbo.tbl_hadr_ag_replica_states
              WHERE is_local = 1 AND group_name = ''' + @cur_ag + '''
              UNION ALL 
              SELECT (''Seeding Mode'' + '': '' + CAST(seeding_mode_desc as nvarchar))
              FROM dbo.tbl_hadr_ag_replica_states
              WHERE is_local = 1 AND group_name = ''' + @cur_ag + '''
              UNION ALL 
              SELECT (''Connections Allowed When Primary'' + '': '' + CAST(primary_role_allow_connections_desc as nvarchar))
              FROM dbo.tbl_hadr_ag_replica_states
              WHERE is_local = 1 AND group_name = ''' + @cur_ag + '''
              UNION ALL 
              SELECT (''Connections Allowed When Secondary'' + '': '' + CAST(secondary_role_allow_connections_desc as nvarchar))
              FROM dbo.tbl_hadr_ag_replica_states
              WHERE is_local = 1 AND group_name = ''' + @cur_ag + '''
              UNION ALL 
              SELECT (''Replica ID'' + '': '' + CAST(replica_id as nvarchar))
              FROM dbo.tbl_hadr_ag_replica_states
              WHERE is_local = 1 AND group_name = ''' + @cur_ag + '''
              UNION ALL 
              SELECT (''group_id'' + '': '' + CAST(group_id as nvarchar))
              FROM dbo.tbl_hadr_ag_replica_states
              WHERE is_local = 1 AND group_name = ''' + @cur_ag + '''
            '
            DELETE FROM #AGs
            WHERE group_name = @cur_ag
            SET @cur_ag = NULL
            SELECT TOP(1) @cur_ag = group_name
            FROM #AGs
            ORDER BY group_name
        END
    END
END
DROP TABLE IF EXISTS #AGs
--SELECT @selectString
exec sp_executesql @selectString
