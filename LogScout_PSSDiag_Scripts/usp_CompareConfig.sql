
/*
*   Author: cbenkler
*   Created: 8/31/2022
*
*   Last Modified by: cbenkler
*   Last Modification: added database-scoped configurations
*
*   Additional Credits:
*      Gracisas a Mr. Rutzky for the "one-liner" dbg line number idea via https://dba.stackexchange.com/questions/139021/how-to-get-the-current-line-number-from-an-executing-stored-procedure
*
*   Script to compare server and database configuration via multiple Nexus databases
*   Requires two or more Nexus databases which each contain:
*          - dbo.tbl_ServerProperties
*          - dbo.tbl_Sys_Configurations
*          - dbo.tbl_SysDatabases (optional if @CompareDBs = 0)
*
*
*   Examples:
*
*       --Compare results from sqlnexus1 and sqlnexus2 databases.  Skip comparison of databases (so should be very fast).  Show only results for configurations that exist in both
*       EXEC usp_CompareConfig @CompareList = N'sqlnexus1, sqlnexus2', @CompareDBs  = 0, @FilterLevel = 2
*
*       --Compare results from sqlnexus1 and sqlnexus2 databases.  Compare databases (took about a minute in my test with two nexus databases, each having 64 entries in tbl_SysDatabases).  Include only differences
*       EXEC usp_CompareConfig @CompareList = N'sqlnexus1, sqlnexus2', @CompareDBs  = 1, @FilterLevel = 1
*
*       --Full side-by-side from 3 nexus databases including entries that are identical 
*       EXEC usp_CompareConfig @CompareList = N'sqlnexus1, sqlnexus2, sqlnexus3', @CompareDBs  = 1, @FilterLevel = 0
*
*       --Something went wrong.  Be sure to switch results to text to get the most out of this
*       ..., @dbg = 1
*/
CREATE OR ALTER PROCEDURE usp_CompareConfig
(     -- comma-separated list of Nexus database names   which contain data sets to be compared
      -- database names may include spaces so long as they're not leading or trailing as such spaces will be ignored
      @CompareList VARCHAR(4000) = NULL  --May include square brackets or double-quotes
    , @FilterLevel INT = 1 --0: No filter; 1: Show only differences (including NULLs); 2: Show only differences and exclude settings that exist on one but not others
    , @CompareDBs BIT = 1 --Flip to 0 if you don't want to compare database configuration via dbo.tbl_SysDatabases
    , @dbg BIT = 0
) AS BEGIN
    SET NOCOUNT ON;
    DECLARE @ErrorString VARCHAR(2047) = ''
        , @ErrorSev INT = 10
        , @ErrorState INT = 1
        , @ErrorLine NVARCHAR(15) = ''
        , @ErrorLineTmplt NVARCHAR(15) = 'Line: #'
        , @DynamicQuery NVARCHAR(MAX) = ''
    CREATE TABLE #DynCols (name VARCHAR(128))
    --Removes spaces, tabs, square brackets, and double-quotes from items in @CompareList
    SELECT DISTINCT REPLACE(REPLACE(REPLACE(REPLACE(TRIM(value), '  ', ''), '[', ''), ']', ''), '"', '') [name], -1 [ValidityStatus]
    INTO #DBs
    FROM STRING_SPLIT(@CompareList, ',')
    IF @dbg = 1
    BEGIN
        BEGIN TRY;THROW 50000,'',1;END TRY BEGIN CATCH;SET @ErrorLine= REPLACE(@ErrorLineTmplt, '#', CAST(ERROR_LINE() AS NVARCHAR));END CATCH
        RAISERROR (@ErrorLine, 10, 1) WITH NOWAIT
        RAISERROR ('#DBs Content:', 10, 1) WITH NOWAIT  
        SELECT *
        FROM #DBs
    END
    IF((SELECT COUNT(1) FROM #DBs) < 2)
    BEGIN
         SELECT @ErrorString = 'Invalid @CompareList. This must be a comma-separated list of at least two valid database names'
            , @ErrorSev = 16
            , @ErrorState = 1
                     
         GOTO ErrorExit
    END
    ELSE BEGIN
        DECLARE 
              @CurDB SYSNAME =  ''
            , @CurSrv VARCHAR(128) = ''
            , @ColList NVARCHAR(MAX) = ''
            , @PossibleValidDBs INT = 0
            , @AppendDBName BIT = 0
              
        SELECT @PossibleValidDBs = COUNT(1)
        FROM #DBs
        --Loop through DB names and ensure that there are at least two valid
        WHILE EXISTS
        (
            SELECT 1
            FROM #DBs
            WHERE ValidityStatus = -1
        ) BEGIN
            SELECT TOP(1) @CurDB  = name
            FROM #DBs
            WHERE ValidityStatus = -1
            ORDER BY name
            IF NOT EXISTS 
            (
                SELECT 1
                FROM sys.databases
                WHERE name = @CurDB
            ) BEGIN
                SELECT @ErrorString =   'Database "' + @CurDB + '" not found in sys.databases. Will be ignored if comparison can continue.'
                        , @ErrorSev = 10
                        , @ErrorState = 2
                RAISERROR
                (
                    @ErrorString
                    , @ErrorSev 
                    , @ErrorState
                )  WITH NOWAIT
                UPDATE #DBs
                SET ValidityStatus = 0
                WHERE name = @CurDB
                             
                SET @PossibleValidDBs -= 1
            END 
            --TODO --
            -- Add check that each database contains expected tables --
            ELSE BEGIN
                UPDATE #DBs
                SET ValidityStatus = 1
                WHERE name = @CurDB
            END
            IF @PossibleValidDBs < 2
            BEGIN                   
                SELECT @ErrorString = '@CompareList does not contain two or more valid database names. Comparison cannot continue.'
                    , @ErrorSev = 16
                    , @ErrorState = 3
                    
                GOTO ErrorExit
            END         
        END
        --We've got at least two valid DBs,  do compare
        BEGIN
            DROP TABLE IF EXISTS ##usp_CompareConfigValues
            DROP TABLE IF EXISTS ##usp_CompareConfigSrvrs
            DROP TABLE IF EXISTS ##usp_CompareConfigDBs
            DROP TABLE IF EXISTS ##usp_CompareConfigDBList
            DROP TABLE IF EXISTS ##usp_CompareConfigSysDatabasesCols
			DROP TABLE IF EXISTS ##usp_CompareConfigDBScopedConfigs
            CREATE TABLE ##usp_CompareConfigSrvrs(NexusDB VARCHAR(128), Srv VARCHAR(128), Status INT)
            UPDATE #DBs
            SET ValidityStatus = 2
            WHERE ValidityStatus = 1
            
            WHILE EXISTS(SELECT 1 FROM #DBs WHERE ValidityStatus = 2)
            BEGIN
                SELECT TOP(1) @CurDB = name
                FROM #DBs
                WHERE ValidityStatus = 2
                ORDER BY name
                --Provide ability to map the NexusDBs to customer server names
                SELECT @DynamicQuery = '
                    INSERT INTO ##usp_CompareConfigSrvrs(NexusDB, Srv, Status)
                    SELECT DISTINCT ''[' + @CurDB + ']'', PropertyValue, -1
                    FROM [' + @CurDB + '].dbo.tbl_ServerProperties
                    WHERE PropertyName = ''SQLServerName'''
                IF @dbg = 1
                BEGIN
                    BEGIN TRY;THROW 50000,'',1;END TRY BEGIN CATCH;SET @ErrorLine= REPLACE(@ErrorLineTmplt, '#', CAST(ERROR_LINE() AS NVARCHAR));END CATCH
                    RAISERROR (@ErrorLine, 10, 1) WITH NOWAIT
                    RAISERROR (@DynamicQuery, 10, 1) WITH NOWAIT
                END
                --TODO -- Add error handling here
                EXEC(@DynamicQuery)
                UPDATE #DBs SET ValidityStatus = 3
                WHERE name = @CurDB
            END
            IF EXISTS(SELECT 1 FROM ##usp_CompareConfigSrvrs GROUP BY Srv HAVING COUNT(1) > 1)
            BEGIN
                SET @AppendDBName = 1   
            END
            IF @dbg = 1
            BEGIN
                SELECT @ErrorString = '@AppendDBName = ' + CAST(@AppendDBName AS VARCHAR)
                BEGIN TRY;THROW 50000,'',1;END TRY BEGIN CATCH;SET @ErrorLine= REPLACE(@ErrorLineTmplt, '#', CAST(ERROR_LINE() AS NVARCHAR));END CATCH
                RAISERROR (@ErrorLine, 10, 1) WITH NOWAIT
                RAISERROR (@ErrorString, 10, 1) WITH NOWAIT
            END
            --Dynamically build out column list - one for each unique dataset 
            SET @DynamicQuery = 'CREATE TABLE ##usp_CompareConfigValues(ConfigName VARCHAR(128)'
            SET @ColList = 'ConfigName'
            WHILE EXISTS (SELECT 1 FROM ##usp_CompareConfigSrvrs WHERE Status = -1)
            BEGIN
                SELECT TOP(1) @CurSrv = Srv, @CurDB = NexusDB
                FROM ##usp_CompareConfigSrvrs
                WHERE Status = -1
                ORDER BY Srv, NexusDB
                --Detect multiple Nexus databases for the same instance
                IF @AppendDBName = 1
                BEGIN
                    SET @DynamicQuery += ', [' + @CurSrv + '_' + @CurDB + '] VARCHAR(128)'
                    SET @ColList +=  ', ' + @CurSrv + '_' + @CurDB
                END
                ELSE BEGIN
                    SET @DynamicQuery += ', [' + @CurSrv + '] VARCHAR(128)'
                    SET @ColList += ', [' + @CurSrv + ']'
                END
                UPDATE ##usp_CompareConfigSrvrs
                SET Status = 1
                WHERE Srv = @CurSrv
                    AND NexusDB = @CurDB
            END
            SET @DynamicQuery += ')'
            IF @dbg = 1
            BEGIN
                SET @ErrorString = '@ColList: ' + @ColList
                BEGIN TRY;THROW 50000,'',1;END TRY BEGIN CATCH;SET @ErrorLine= REPLACE(@ErrorLineTmplt, '#', CAST(ERROR_LINE() AS NVARCHAR));END CATCH
                RAISERROR(@ErrorLine, 10, 1) WITH NOWAIT
                RAISERROR(@ErrorString, 10, 1) WITH NOWAIT
                RAISERROR(@DynamicQuery, 10, 1) WITH NOWAIT
            END
            
            --TODO Add error checking
            EXEC(@DynamicQuery)
            --Insert the server properties
            SET @DynamicQuery = 'INSERT INTO ##usp_CompareConfigValues(' + @ColList + ')
                SELECT [0].PropertyName~_PLHDR_CLIST_~
                FROM ~_PLHDR_SLIST_~
                WHERE [0].PropertyName NOT IN (
                      ''MajorVersion''
                    , ''MachineName''
                    , ''ServerName''
                    , ''SQLServerName''
                    , ''operating system version build''
                    , ''ProcessID''
                    , ''ProductLevel''
                    )'
            DECLARE @alias INT = 0
            DECLARE @join NVARCHAR(50) = 'INNER JOIN '
            IF @FilterLevel < 2
            BEGIN
                SET @join = 'FULL OUTER JOIN '
            END
            WHILE EXISTS (SELECT 1 FROM ##usp_CompareConfigSrvrs WHERE Status = 1)
            BEGIN
                SELECT TOP(1) @CurDB = NexusDB, @CurSrv = Srv
                FROM ##usp_CompareConfigSrvrs
                WHERE Status = 1
                ORDER BY Srv, NexusDB
                --Add the aliases to be used in joins one at a time in each iteration
                SELECT @DynamicQuery = REPLACE(@DynamicQuery, '~_PLHDR_CLIST_~', (', [' + CAST(@alias AS NVARCHAR) + '].PropertyValue~_PLHDR_CLIST_~'))
                --Don't need join on the first iteration
                IF @alias = 0
                BEGIN
                   SELECT @DynamicQuery = REPLACE(@DynamicQuery, '~_PLHDR_SLIST_~',     (@CurDB + '.dbo.tbl_ServerProperties ' + '[' + CAST(@alias AS NVARCHAR) + ']' +CHAR(13)+CHAR(9)+'~_PLHDR_SLIST_~'))
                END
                ELSE BEGIN
                    SELECT @DynamicQuery = REPLACE(@DynamicQuery, '~_PLHDR_SLIST_~', (@join + @CurDB + '.dbo.tbl_ServerProperties ' + '[' + CAST(@alias AS NVARCHAR) + ']' +CHAR(13)+CHAR(9)+'ON [0].PropertyName = [' + CAST(@alias AS NVARCHAR) + '].PropertyName' +CHAR(13)+'~_PLHDR_SLIST_~'))
                END
                UPDATE ##usp_CompareConfigSrvrs
                SET Status = 2
                WHERE NexusDB = @CurDB
                SET @alias += 1
            END
            --Remove the placeholders
            SELECT @DynamicQuery = REPLACE(REPLACE(@DynamicQuery, '~_PLHDR_CLIST_~', ''), '~_PLHDR_SLIST_~', '')
            
            IF @dbg = 1
            BEGIN
                BEGIN TRY;THROW 50000,'',1;END TRY BEGIN CATCH;SET @ErrorLine= REPLACE(@ErrorLineTmplt, '#', CAST(ERROR_LINE() AS NVARCHAR));END CATCH
                RAISERROR(@ErrorLine, 10, 1) WITH NOWAIT
                RAISERROR(@DynamicQuery, 10, 1) WITH NOWAIT
            END
            --TODO -- Add error handling
            EXEC(@DynamicQuery)
            SET @alias = 0
            SET @DynamicQuery = 'INSERT INTO ##usp_CompareConfigValues(' + @ColList + ')
                SELECT [0].name~_PLHDR_CLIST_~
                FROM ~_PLHDR_SLIST_~'
            
            WHILE EXISTS (SELECT 1 FROM ##usp_CompareConfigSrvrs WHERE Status = 2)
            BEGIN
                SELECT TOP(1) @CurDB = NexusDB, @CurSrv = Srv
                FROM ##usp_CompareConfigSrvrs
                WHERE Status = 2
                ORDER BY Srv, NexusDB
                --Add the aliases to be used in joins one at a time in each iteration
                SELECT @DynamicQuery = REPLACE(@DynamicQuery, '~_PLHDR_CLIST_~', (', [' + CAST(@alias AS NVARCHAR) + '].value_in_use~_PLHDR_CLIST_~'))
                --Don't need join on the first iteration
                IF @alias = 0
                BEGIN
                   SELECT @DynamicQuery = REPLACE(@DynamicQuery, '~_PLHDR_SLIST_~',     (@CurDB + '.dbo.tbl_Sys_Configurations ' + '[' + CAST(@alias AS NVARCHAR) + ']' +CHAR(13)+CHAR(9)+'~_PLHDR_SLIST_~'))
                END
                ELSE BEGIN
                    SELECT @DynamicQuery = REPLACE(@DynamicQuery, '~_PLHDR_SLIST_~', (@join + @CurDB + '.dbo.tbl_Sys_Configurations ' + '[' + CAST(@alias AS NVARCHAR) + ']' +CHAR(13)+CHAR(9)+'ON [0].name = [' + CAST(@alias AS NVARCHAR) + '].name' +CHAR(13)+'~_PLHDR_SLIST_~'))
                END
                UPDATE ##usp_CompareConfigSrvrs
                SET Status = 1
                WHERE NexusDB = @CurDB
                SET @alias += 1
            END
            
            --Remove the placeholders
            SELECT @DynamicQuery = REPLACE(REPLACE(@DynamicQuery, '~_PLHDR_CLIST_~', ''), '~_PLHDR_SLIST_~', '')
            
            IF @dbg = 1
            BEGIN
                BEGIN TRY;THROW 50000,'',1;END TRY BEGIN CATCH;SET @ErrorLine= REPLACE(@ErrorLineTmplt, '#', CAST(ERROR_LINE() AS NVARCHAR));END CATCH
                RAISERROR(@ErrorLine, 10, 1) WITH NOWAIT
                RAISERROR(@DynamicQuery, 10, 1) WITH NOWAIT
            END
            EXEC(@DynamicQuery)

            --Starting point for DB Comparison
            IF @CompareDBs = 1
            BEGIN
				DECLARE @DBScopedConfigsQuery NVARCHAR(MAX) = N'';

                SELECT @DynamicQuery = 'CREATE TABLE ##usp_CompareConfigDBs([Database] VARCHAR(128), ' + REPLACE(@ColList, ',', ' VARCHAR(128),')  + ' VARCHAR(128))'
                IF @dbg = 1
                BEGIN
                    BEGIN TRY;THROW 50000,'',1;END TRY BEGIN CATCH;SET @ErrorLine= REPLACE(@ErrorLineTmplt, '#', CAST(ERROR_LINE() AS NVARCHAR));END CATCH
                    RAISERROR(@ErrorLine, 10, 1) WITH NOWAIT
                    RAISERROR(@DynamicQuery, 10, 1) WITH NOWAIT
                END
                EXEC(@DynamicQuery)
                SET @DynamicQuery = '
                SELECT c.name
                INTO ##usp_CompareConfigSysDatabasesCols
                FROM [].sys.columns c
                    JOIN [].sys.objects o ON o.object_id = c.object_id
                WHERE o.name = ''tbl_SysDatabases''
                    AND c.name NOT IN 
                    (
                          ''name''
                        , ''catalog_collation_type''
                        , ''containment''
                        , ''create_date''
                        , ''database_id''
                        , ''default_language_lcid''
                        , ''delated_durability''
                        , ''log_reuse_wait''
                        , ''log_reuse_wait_desc''
                        , ''page_verify_option''
                        , ''physical_database_name''
                        , ''recovery_model''
                        , ''service_broker_guid''
                        , ''snapshot_isolation_state''
                        , ''state''
                        , ''user_access''
                    )'
                SELECT @DynamicQuery = REPLACE(@DynamicQuery, '[]', (SELECT TOP(1) NexusDB FROM ##usp_CompareConfigSrvrs))
                EXEC(@DynamicQuery)
                IF @dbg = 1
                BEGIN
                    BEGIN TRY;THROW 50000,'',1;END TRY BEGIN CATCH;SET @ErrorLine= REPLACE(@ErrorLineTmplt, '#', CAST(ERROR_LINE() AS NVARCHAR));END CATCH
                    RAISERROR(@ErrorLine, 10, 1) WITH NOWAIT
                    RAISERROR(@DynamicQuery, 10, 1) WITH NOWAIT
                END
                CREATE TABLE ##usp_CompareConfigDBList(name VARCHAR(128), status INT)
                WHILE EXISTS(SELECT 1 FROM ##usp_CompareConfigSrvrs WHERE Status = 1)
                BEGIN
                    SELECT TOP(1) @CurDB = NexusDB
                    FROM ##usp_CompareConfigSrvrs
                    WHERE Status = 1
                    ORDER BY NexusDB
                    SET @DynamicQuery = '
                        INSERT INTO ##usp_CompareConfigDBList(name, status)
                        SELECT DISTINCT name, 0
                        FROM ' + @CurDB + '.dbo.tbl_SysDatabases
                        WHERE name NOT IN
                        (
                            SELECT name
                            FROM ##usp_CompareConfigDBList
                        )'
                    IF @dbg = 1
                    BEGIN
                        BEGIN TRY;THROW 50000,'',1;END TRY BEGIN CATCH;SET @ErrorLine= REPLACE(@ErrorLineTmplt, '#', CAST(ERROR_LINE() AS NVARCHAR));END CATCH
                        RAISERROR(@ErrorLine, 10, 1) WITH NOWAIT
                        RAISERROR(@DynamicQuery, 10, 1) WITH NOWAIT
                        SELECT *
                        FROM ##usp_CompareConfigDBList
                    END
                    EXEC(@DynamicQuery)
                    UPDATE ##usp_CompareConfigSrvrs
                    SET Status = 2
                    WHERE NexusDB = @CurDB
                END
            
                DECLARE @CurCol SYSNAME = ''
                SET @DynamicQuery = 'INSERT INTO ##usp_CompareConfigDBs([Database], ' + @ColList + ')' + CHAR(13)
                        + 'SELECT ~_PLHDR_CLIST_~'
                        + CHAR(13) + 'FROM ~_PLHDR_SLIST_~'

				SET @DBScopedConfigsQuery = 'INSERT INTO ##usp_CompareConfigDBs([Database], ' + @ColList + ')' + CHAR(13)
                        + 'SELECT DISTINCT [0].dbname, [0].name, CAST([0].value AS VARCHAR(64))~_PLHDR_CLIST_~'
                        + CHAR(13) + 'FROM ~_PLHDR_SLIST_~'
                --Populate the data sources first
                --Will come back to populate the column list later
                SET @alias = 0
                WHILE EXISTS(SELECT 1 FROM ##usp_CompareConfigSrvrs WHERE Status = 2)
                BEGIN
                    SELECT TOP(1) @CurDB = NexusDB
                    FROM ##usp_CompareConfigSrvrs
                    WHERE Status = 2
                    ORDER BY Srv, NexusDB
                    --Don't need join on the first iteration
                    IF @alias = 0
                    BEGIN
                       SELECT @DynamicQuery = REPLACE(@DynamicQuery, '~_PLHDR_SLIST_~',     (@CurDB + '.dbo.tbl_SysDatabases ' + '[' + CAST(@alias AS NVARCHAR) + ']' +CHAR(13)+CHAR(9)+'~_PLHDR_SLIST_~'))
					   SELECT @DBScopedConfigsQuery = REPLACE(@DBScopedConfigsQuery, '~_PLHDR_SLIST_~',     (@CurDB + '.dbo.tbl_database_scoped_configurations ' + '[' + CAST(@alias AS NVARCHAR) + ']' +CHAR(13)+CHAR(9)+'~_PLHDR_SLIST_~'))
                    END
                    ELSE BEGIN
                        SELECT @DynamicQuery = REPLACE(@DynamicQuery, '~_PLHDR_SLIST_~', (@join + @CurDB + '.dbo.tbl_SysDatabases ' + '[' + CAST(@alias AS NVARCHAR) + ']' +CHAR(13)+CHAR(9)+'ON [0].name = [' + CAST(@alias AS NVARCHAR) + '].name' +CHAR(13)+'~_PLHDR_SLIST_~'))

						SELECT @DBScopedConfigsQuery = REPLACE(@DBScopedConfigsQuery, '~_PLHDR_CLIST_~', (', CAST([' + CAST(@alias AS NVARCHAR) + '].value AS VARCHAR(64))~_PLHDR_CLIST_~'))
						SELECT @DBScopedConfigsQuery = REPLACE(@DBScopedConfigsQuery, '~_PLHDR_SLIST_~', (@join + @CurDB + '.dbo.tbl_database_scoped_configurations ' + '[' + CAST(@alias AS NVARCHAR) + ']' +CHAR(13)+CHAR(9)+'ON [0].name = [' + CAST(@alias AS NVARCHAR) + '].name AND [0].[dbname] = [' + CAST(@alias AS NVARCHAR) + '].dbname' +CHAR(13)+'~_PLHDR_SLIST_~'))
                    END     
                    SET @alias += 1
                    UPDATE ##usp_CompareConfigSrvrs 
                    SET Status = 4
                    WHERE NexusDB = @CurDB
                END
                IF @dbg = 1
                BEGIN
                    BEGIN TRY;THROW 50000,'',1;END TRY BEGIN CATCH;SET @ErrorLine= REPLACE(@ErrorLineTmplt, '#', CAST(ERROR_LINE() AS NVARCHAR));END CATCH
                    RAISERROR(@ErrorLine, 10, 1) WITH NOWAIT
                    RAISERROR(@DynamicQuery, 10, 1) WITH NOWAIT
					RAISERROR(@DBScopedConfigsQuery, 10, 1) WITH NOWAIT
                END
                --RETAIN @alias in @aliasSS!!
                --Will be used to count
                SET @alias -= 1
                DECLARE 
                      @aliasSS INT = @alias
                    , @DQT NVARCHAR(MAX) = @DynamicQuery
                --For each column in SysDatabases to compare...
                WHILE EXISTS(SELECT 1 FROM ##usp_CompareConfigSysDatabasesCols)
                BEGIN
                    SET @DynamicQuery = @DQT
                            
                    SELECT TOP(1) @CurCol = name
                    FROM ##usp_CompareConfigSysDatabasesCols 
                    ORDER BY name
                    --For each database listed in SysDatabases across all Nexus databases
                    WHILE EXISTS(SELECT 1 FROM ##usp_CompareConfigDBList WHERE Status = 0)
                    BEGIN
                        SELECT TOP(1) @CurDB = name
                        FROM ##usp_CompareConfigDBList
                        WHERE status = 0
                        ORDER BY name
                    
                        SELECT @DynamicQuery = REPLACE(@DynamicQuery, '~_PLHDR_CLIST_~', ('''' + @CurDB + ''', ''' + @CurCol + '''~_PLHDR_CLIST_~'))
                    
                        SET @alias = 0
                        --Add current SysDatabases column from each Nexus database
                        WHILE @alias <= @aliasSS
                        BEGIN
                            SELECT @DynamicQuery = REPLACE(@DynamicQuery, '~_PLHDR_CLIST_~', ', ISNULL([' + CAST(@alias AS VARCHAR) + '].' + @CurCol + ', ''~_WAS_NULL_~'')~_PLHDR_CLIST_~')
                            IF @alias = 0
                            BEGIN
                                SELECT @DynamicQuery = REPLACE(@DynamicQuery, '~_PLHDR_SLIST_~', (' WHERE [0].name = ' + ''''+ @CurDB + '''' + CHAR(13) + '~_PLHDR_SLIST_~'))
                            END
                            ELSE BEGIN
                                SELECT @DynamicQuery = REPLACE(@DynamicQuery, '~_PLHDR_SLIST_~', (CHAR(9) + 'OR [' + CAST(@alias AS NVARCHAR) + '].name = ' + ''''+ @CurDB + '''' + CHAR(13) + '~_PLHDR_SLIST_~'))
                            END
                            SET @alias += 1
                        END
                    
                        --Remove the placeholders
                        SELECT @DynamicQuery = REPLACE(REPLACE(@DynamicQuery, '~_PLHDR_SLIST_~', ''), '~_PLHDR_CLIST_~', '')
                        IF @dbg = 1
                        BEGIN
                            BEGIN TRY;THROW 50000,'',1;END TRY BEGIN CATCH;SET @ErrorLine= REPLACE(@ErrorLineTmplt, '#', CAST(ERROR_LINE() AS NVARCHAR));END CATCH
                            RAISERROR(@ErrorLine, 10, 1) WITH NOWAIT
                            RAISERROR(@DynamicQuery, 10, 1) WITH NOWAIT
                        END
                        EXEC(@DynamicQuery)
                        UPDATE ##usp_CompareConfigDBList
                        SET status = 1
                        WHERE name = @CurDB
                        SET @DynamicQuery = @DQT
                    END
                    DELETE FROM ##usp_CompareConfigSysDatabasesCols 
                    WHERE name = @CurCol
                    UPDATE ##usp_CompareConfigDBList
                    SET status = 0
                    WHERE status = 1
                END
            
				--Remove the placeholders
                SELECT @DBScopedConfigsQuery = REPLACE(REPLACE(@DBScopedConfigsQuery, '~_PLHDR_SLIST_~', ''), '~_PLHDR_CLIST_~', '')
                IF @dbg = 1
                BEGIN
                    BEGIN TRY;THROW 50000,'',1;END TRY BEGIN CATCH;SET @ErrorLine= REPLACE(@ErrorLineTmplt, '#', CAST(ERROR_LINE() AS NVARCHAR));END CATCH
                    RAISERROR(@ErrorLine, 10, 1) WITH NOWAIT
                    RAISERROR(@DBScopedConfigsQuery, 10, 1) WITH NOWAIT
				END
				EXEC(@DBScopedConfigsQuery)
			END
            
            GOTO Success
        END
    END
    BEGIN  ErrorExit:
            RAISERROR( @ErrorString, @ErrorSev, @ErrorState) WITH NOWAIT
            RETURN  -1
    END
    BEGIN Success:
        SELECT value 
        INTO #Cols
        FROM STRING_SPLIT(@ColList, ',')
        WHERE value <> 'ConfigName'
        IF @dbg = 1
        BEGIN
           RAISERROR('Line 517', 10, 1) WITH NOWAIT
           
           SELECT *
           FROM #Cols
        END
        SET @DynamicQuery = '
            SELECT *
            FROM ##usp_CompareConfigValues
            WHERE ConfigName IS NOT NULL AND (~_PLHDR_SLIST_~)'
        IF @CompareDBs = 1
        BEGIN
            SET @DynamicQuery += CHAR(13)+CHAR(13) 
                +  'SELECT *
                    FROM ##usp_CompareConfigDBs
                    WHERE ConfigName IS NOT NULL AND (~_PLHDR_SLIST_~)'
        END
        IF @dbg = 1
        BEGIN
            BEGIN TRY;THROW 50000,'',1;END TRY BEGIN CATCH;SET @ErrorLine= REPLACE(@ErrorLineTmplt, '#', CAST(ERROR_LINE() AS NVARCHAR));END CATCH
            RAISERROR(@ErrorLine, 10, 1) WITH NOWAIT
            RAISERROR(@DynamicQuery, 10, 1) WITH NOWAIT
        END
            
        IF @FilterLevel = 0
        BEGIN
            SELECT @DynamicQuery = REPLACE(@DynamicQuery, 'WHERE ~_PLHDR_SLIST_~', '')
        END
        ELSE BEGIN --INNER JOIN filters out NULLs for us already
            DECLARE @InnerCol VARCHAR(128)
                , @FlowBit BIT 
            SELECT @CurCol = ''
                 , @InnerCol = ''
            WHILE EXISTS (SELECT 1 FROM #Cols WHERE value > @CurCol) 
            BEGIN
                SELECT @CurCol = MIN(value)
                FROM #Cols
                WHERE value > @CurCol
                IF @InnerCol = ''
                BEGIN
                    SELECT @DynamicQuery = REPLACE(@DynamicQuery, '~_PLHDR_SLIST_~', (@CurCol + ' <> ~_PLHDR_SLIST_~'))
                    SET @FlowBit = 0
                END
                ELSE BEGIN
                    SELECT @DynamicQuery = REPLACE(@DynamicQuery, '~_PLHDR_SLIST_~', (CHAR(13)+CHAR(9)+ '~_PLHDR_SLIST_~'))
                END
                SET @InnerCol = @CurCol
                WHILE EXISTS(SELECT 1 FROM #Cols WHERE value > @InnerCol)
                BEGIN
                    SELECT @InnerCol = MIN(value)
                    FROM #Cols
                    WHERE value > @InnerCol
                    
                    IF @FlowBit = 0
                    BEGIN
                        SELECT @DynamicQuery = REPLACE(@DynamicQuery, '~_PLHDR_SLIST_~', (@InnerCol + ' OR (' + @CurCol + ' IS NULL AND ' + @InnerCol + ' IS NOT NULL) OR (' + @CurCol + ' IS NOT NULL AND ' + @InnerCol + ' IS NULL)  ~_PLHDR_SLIST_~'))
                        SET @FlowBit = 1
                    END 
                    ELSE BEGIN
                        SELECT @DynamicQuery = REPLACE(@DynamicQuery, '~_PLHDR_SLIST_~', ('OR ' + @CurCol + ' <> ' + @InnerCol + ' OR (' + @CurCol + ' IS NULL AND ' + @InnerCol + ' IS NOT NULL) OR (' + @CurCol + ' IS NOT NULL AND ' + @InnerCol + ' IS NULL)  ~_PLHDR_SLIST_~'))
                    END
                END
            END
            SELECT @DynamicQuery = REPLACE(@DynamicQuery, '~_PLHDR_SLIST_~', '')
        END
        IF @dbg = 1
        BEGIN
            BEGIN TRY;THROW 50000,'',1;END TRY BEGIN CATCH;SET @ErrorLine= REPLACE(@ErrorLineTmplt, '#', CAST(ERROR_LINE() AS NVARCHAR));END CATCH
            RAISERROR(@ErrorLine, 10, 1) WITH NOWAIT
            RAISERROR(@DynamicQuery, 10, 1) WITH NOWAIT
        END
        EXEC(@DynamicQuery)
        RETURN
    END
END
