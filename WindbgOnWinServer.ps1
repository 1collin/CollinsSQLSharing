  
#Use default "Downloads" folder if not changed  
$DownloadLocation = Join-Path -Path "$([System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::UserProfile))" -ChildPath "Downloads"

#This is where files will be copied if not changed
$DropLocation = "C:\Tools\Debuggers\Windbg"

#This is where we'll tell Windows to keep cached symbols
$SymbolPath = "C:\Tools\Debuggers\Symbols"

#Just like https://learn.microsoft.com/en-us/windows-hardware/drivers/debugger/microsoft-public-symbols#how-to-access
[System.Environment]::SetEnvironmentVariable('_NT_SYMBOL_PATH',"srv*$SymbolPath*https://msdl.microsoft.com/download/symbols", 'Machine')
[System.Environment]::SetEnvironmentVariable('_NT_SYMBOL_PATH',"srv*$SymbolPath*https://msdl.microsoft.com/download/symbols", 'User')

#Create folders if they don't already exist

[System.IO.Directory]::CreateDirectory($DownloadLocation) | Out-Null

[System.IO.Directory]::CreateDirectory($DropLocation) | Out-Null

[System.IO.Directory]::CreateDirectory($SymbolPath) | Out-Null

#Need to set TLS 1.2 or downloads will fail...
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12


#Thanks, https://gist.github.com/awakecoding/43f615e116fae64f721be7a98f8f60cf
Write-Host "Downloading windbg.appinstaller (XML manifest file)"
$AppInstallerUrl = "https://aka.ms/windbg/download"
$AppInstallerPath = Join-Path -Path $DownloadLocation -ChildPath "windbg.appinstaller"
Invoke-WebRequest -Uri $AppInstallerUrl -OutFile $AppInstallerPath

Write-Host "Parsing .appinstaller XML for windbg.msixbundle URL"
[xml]$AppInstallerXml = Get-Content -Path $AppInstallerPath
$NamespaceManager = New-Object System.Xml.XmlNamespaceManager($AppInstallerXml.NameTable)
$NamespaceManager.AddNamespace("ns", "http://schemas.microsoft.com/appx/appinstaller/2018")
$BundleUrl = $AppInstallerXml.SelectSingleNode("//ns:MainBundle", $NamespaceManager).Uri


Write-Host "Downloading windbg.msixbundle (actual package file)"
$MsixBundlePath = Join-Path -Path $DownloadLocation -ChildPath "windbg.msixbundle"
Invoke-WebRequest -Uri $BundleUrl -OutFile $MsixBundlePath

#If this works, great. Didn't work for me so let's just treat as xcopy if not...

try
{
    #Set ErrorAction to trip try/catch in case of error:
    $ErrorActionPreference = 'Stop'

    Write-Host "Invoking Add-AppxPackage to install windbg.msixbundle"
    if ($PSEdition -eq 'Core') {
        $Command = "Add-AppxPackage -Path `"$MsixBundlePath`""
        Start-Process powershell.exe -ArgumentList "-Command", $Command -Wait
    } else {
        Add-AppxPackage -Path $MsixBundlePath
    }

    Write-Host "WinDbg should be installed - you'll see in start menu"

    $WinDbgAppID = (Get-StartApps | Where-Object { $_.Name -eq 'WinDbg' }).AppID
    if ($WinDbgAppID) {
        Write-Host "Launching WinDbg..."
        Start-Process "shell:AppsFolder\$WinDbgAppID"
    } else {
        Write-Warning "WinDbg not found or could not be started."
    }
}catch
{
    Write-Host "Install didn't work - let's just treat as xcopy"

    Rename-Item $MsixBundlePath -NewName $MsixBundlePath.Replace(".msixbundle", ".zip")

    #Need to rename because Expand-Archive doesn't even try if not .zip
    $MsixBundlePath = $MsixBundlePath.Replace(".msixbundle", ".zip") 

    #This should result in windbg folder with nested windbg_win7-x64.msix file
    Expand-Archive $MsixBundlePath -DestinationPath (Join-Path $DownloadLocation -ChildPath "windbg")

    $MsixPath = Join-Path $DownloadLocation -ChildPath "windbg\windbg_win7-x64.msix"

    #Once again, need to rename because Expand-Archive doesn't even try if not .zip
    Rename-Item $MsixPath -NewName $MsixPath.Replace(".msix", ".zip")

    $MsixPath = $MsixPath.Replace(".msix", ".zip")

    Expand-Archive -Path $MsixPath -DestinationPath $DropLocation

    Write-Host "WinDbg should be installed - you'll see in $DropLocation"

    Start-Process -FilePath (Join-Path $DropLocation -ChildPath "DbgX.Shell.exe")
}

#Optionally cleanup...

<#
Remove-Item -Path $MsixBundlePath -Force

Remove-Item -Path (Join-Path $DownloadLocation -ChildPath "windbg") -Recurse -Force
#> 
