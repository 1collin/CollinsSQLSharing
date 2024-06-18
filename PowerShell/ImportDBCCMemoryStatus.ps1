$File = "C:\Temp\YourMemoryStatusFileHere.txt"
[string]$SQLInstance = "mymachine\SQL2019"
[string]$Database = 'NormalizedDBCCMEMORYSTATUS'
[int]$ProgressThreshold = 1

$fs = [System.IO.StreamReader]::new($File);
$Tables = New-Object System.Collections.Generic.List[System.Data.DataTable]

[string]$TimestampLineSignature = "Job 'MSFT_MemoryStatus' : Step 1, 's1' : Began Executing"
[string]$CurrentTimestamp = ''
[string]$SectionSeparator = "------------------------------------------------------------------------";
[string]$EndString = "DBCC execution completed. If DBCC printed error messages, contact your system administrator. [SQLSTATE 01000]"

[boolean]$InSection = $false
[System.Collections.Hashtable]$CurrentSectionData = @{}

[System.Data.DataTable]$CurrentTable = $null
[string]$CurrentTableName = ''
[boolean]$TableExisted = $false

[long]$counter = 0


function Initialize-TableSchema()
{
    if($null -eq ($Tables | Where-Object{$_.TableName -eq $CurrentTableName}))
    {
        $runtimeColumn = New-Object System.Data.DataColumn
        $runtimeColumn.ColumnName = "runtime"
        $runtimeColumn.DataType = [System.Type]::GetType('System.DateTime')
        $CurrentTable.Columns.Add($runtimeColumn)
    
        foreach($pair in $CurrentSectionData.GetEnumerator())
        {
            #We already added runtime
            if($pair.Key -ne 'runtime')
            {
                $column = New-Object System.Data.DataColumn
                $column.ColumnName = $pair.Key

                if($pair.Value.ToString().Contains('.'))
                {
                    $column.DataType = [System.Type]::GetType('System.Decimal')
                }
                elseif($pair.Value -match "^-?\d+$")
                {
                    $column.DataType = [System.Type]::GetType('System.Int64')
                }
                else
                {
                    $column.DataType = [System.Type]::GetType('System.String')
                    $column.MaxLength = 512
                }

                $CurrentTable.Columns.Add($column)
            }
        }

        $Tables.Add($CurrentTable)
    }

    $TableExisted = $true
}
function Add-TableData()
{
    [System.Data.DataRow]$currentRow = $CurrentTable.NewRow()

    #By this point we should have table structure. Let's populate
    foreach($pair in $CurrentSectionData.GetEnumerator())
    {       
        try {
            $currentRow[$pair.Key] = $pair.Value
        }
        catch {
            Out-Host "Error writing value $($pair.Value) in column $($pair.Key) of table $($CurrentTable.TableName)"
            Out-Host $_
        }
        
    }

    $CurrentTable.Rows.Add($currentRow)
}

function Import-TableData()
{
    $tableCount = $Tables.Count
    $tablesImported = 0

    if($null -eq $Database)
    {
        $Database = 'DBCCMemoryStatusOutput'
    }
    foreach($table in $Tables)
    {
        $normalized = $false

        if($table.TableName -like "CACHESTORE*")
        {
            $NormalizedTableName = "CACHESTORE"
            $normalized = $true
        }
        elseif($table.TableName -like "MEMORYCLERK*")
        {
            $NormalizedTableName = "MEMORYCLERK"
            $normalized = $true
        }
        elseif($table.TableName -like "OBJECTSTORE*")
        {
            $NormalizedTableName = "OBJECTSTORE"
            $normalized = $true
        }
        elseif($table.TableName -like "USERSTORE*")
        {
            $NormalizedTableName = "USERSTORE"
            $normalized = $true
        }
        elseif($table.TableName -like "MEMORYBROKER_FOR*")
        {
            $NormalizedTableName = "MEMORYBROKER"
        }
        
        if($normalized)
        {
            if($NormalizedTableName -eq "MEMORYBROKER")
            {
                $normalizedType = $table.TableName.Replace("MEMORYBROKER_FOR_",'')
            }
            else
            {
                $normalizedType = $table.TableName.Substring($table.TableName.IndexOf('_')+1)
            }
            
            $normalizedType = $normalizedType.Substring(0,$normalizedType.IndexOf(' ')).Trim()

            $nodeId = $table.TableName.Substring($table.TableName.IndexOf('(')+1)
            
            $column = New-Object System.Data.DataColumn

            $column.DataType = [System.Type]::GetType('System.String')
            $column.MaxLength = 64
            $column.ColumnName = 'Type'
            $column.DefaultValue = $normalizedType

            $table.Columns.Add($column)

            if($null -ne $nodeId)
            {
                $column = New-Object System.Data.DataColumn
                $nodeId = $nodeId.Replace(')', '').Trim()
                $column.DataType = [System.Type]::GetType('System.String')
                $column.MaxLength = 32
                $column.ColumnName = 'Subset'
                $column.DefaultValue = $nodeId

                $table.Columns.Add($column)
            }

            $table.TableName = $NormalizedTableName
        }


        try
        {
            Write-SqlTableData -ServerInstance $SQLInstance -DatabaseName $Database -SchemaName 'dbo' -TableName $table.TableName -InputData $table -Force

            if($tablesImported % $ProgressThreshold -eq 0)
            {
                Write-Progress -Activity "Table import" -CurrentOperation "Imported table $tablesImported of $tableCount." -PercentComplete ($tablesImported/$tableCount)
            }

            $tablesImported++
        }
        catch 
        {
            Out-Host "Error importing $($table.TableName):"
            Out-Host $_
        }
    }
}


while($null -ne ($line = $fs.ReadLine()))
{
    $PreviousLine = $CurrentLine
    $CurrentLine = $line
    
    if($line.Contains($TimestampLineSignature))
    {
        $CurrentTimestamp = $line.Replace($TimestampLineSignature, "").Trim();
    }

    elseif($line.Contains($SectionSeparator))
    {
        $exit = $false

        while(!$exit)
        {
            #If already in a section, we need to close it out and add to table before reusing
            if($InSection)
            {
                #The last thing added would have been the section header for upcoming section. Remove it
                $CurrentSectionData.Remove($PreviousLine.Substring(0,$PreviousLine.IndexOf('  ')).Trim());

                #Table didn't exist. We need to add the columns
                if(!$TableExisted)
                {
                    Initialize-TableSchema
                }
                
                Add-TableData

                $InSection = $false
            }
            else
            {
                $InSection = $true
                $CurrentSectionData.Clear()
        
                $CurrentTableName = $PreviousLine.Substring(0, $PreviousLine.IndexOf('  ')).Trim();
        
                #Use table if we've got it
                $CurrentTable = $Tables | Where-Object{$_.TableName -eq $CurrentTableName} | Select-Object -First 1
        
                #Create table if we didn't yet
                #We'll need to add columns after read from file, so start populating hashtable staging object
                if($null -eq $CurrentTable)
                {
                    $TableExisted = $false
                    $CurrentTable = New-Object System.Data.DataTable
                    $CurrentTable.TableName = $CurrentTableName          
                }
                else {
                    $TableExisted = $true
                }
        
                $CurrentSectionData.Add('runtime', $CurrentTimestamp) 

                $exit = $true
            }
        }
    }

    elseif($line.Contains($EndString))
    {
        $Runtime = ""
        $InSection = $false

        if(!$TableExisted)
        {
            Initialize-TableSchema
        }
        #CurrentTable must have been identified (or created) at this point
        Add-TableData

        $CurrentSectionData.Clear()
    }
    #Assume this is data line
    elseif($InSection)
    {
        $columnName = $line.Substring(0,$line.IndexOf('  ')).Trim();
        $currentValue = $line.Substring($line.IndexOf('  ')+1).Trim();

        [string]$val = $currentValue

        #Some numbers expressed with scientific notiation (e.g. 6.2041170295207316E-9). Need to convert to decimal or will error
        if($val.Contains('.'))
        {
            if($val.Contains('E'))
            {
                $style = [Globalization.NumberStyles]::Float
                $culture = [cultureinfo]::GetCultureInfo('en-US')
                [decimal]$val = 0
                [Decimal]::TryParse($currentValue, $style, $culture, [ref] $val)
            }
        }
        $CurrentSectionData.Add($columnName, $val)
    }

    if($counter % 1000 -eq 0)
    {
        "Parsed $counter lines..." | Out-Host 
    }

    $counter++
}


Import-TableData
