<#
.SYNOPSIS
  Builds the Checkmk drop-in package (dist\OpenHardwareMonitorCLI.exe + OpenHardwareMonitorLib.dll).

.DESCRIPTION
  By default LibreHardwareMonitorLib is compiled from the current source of
  https://github.com/LibreHardwareMonitor/LibreHardwareMonitor (branch master).
  The repository is cloned to .\external\LibreHardwareMonitor and updated on every build.

.PARAMETER Ref
  Branch, tag or commit of LibreHardwareMonitor to build (default: master).
  Examples: master, v0.9.6, 71040ce2083ecde1f8471acd740a5f1d599744f7

.PARAMETER NoUpdate
  Build the source that is already in .\external\LibreHardwareMonitor without fetching.

.PARAMETER FromNuGet
  Use the last stable release from nuget.org instead of the repository source.

.EXAMPLE
  .\build.ps1
  .\build.ps1 -Ref v0.9.6
  .\build.ps1 -FromNuGet
#>
[CmdletBinding()]
param(
    [string]$Ref = 'master',
    [switch]$NoUpdate,
    [switch]$FromNuGet,
    [string]$Configuration = 'Release'
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$repoUrl = 'https://github.com/LibreHardwareMonitor/LibreHardwareMonitor.git'
$repoDir = Join-Path $PSScriptRoot 'external\LibreHardwareMonitor'
$project = Join-Path $PSScriptRoot 'src\OpenHardwareMonitorCLI.csproj'
$dist = Join-Path $PSScriptRoot 'dist'

function Fail([string]$message) {
    Write-Host $message -ForegroundColor Red
    exit 1
}

# --- .NET SDK -------------------------------------------------------------------------------
if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    Fail 'dotnet SDK not found. Install it with:  winget install Microsoft.DotNet.SDK.10'
}

$sdks = & dotnet --list-sdks
$hasSdk10 = $sdks | Where-Object { $_ -match '^(\d+)\.' -and [int]$Matches[1] -ge 10 }
if (-not $FromNuGet -and -not $hasSdk10) {
    Fail ("Building LibreHardwareMonitor from source requires the .NET 10 SDK (it also targets net10.0).`n" +
          "Install it with:  winget install Microsoft.DotNet.SDK.10`n" +
          "Or build with the NuGet release:  build.cmd -FromNuGet")
}

# --- LibreHardwareMonitor source ------------------------------------------------------------
$lhmInfo = $null
if ($FromNuGet) {
    $lhmInfo = 'LibreHardwareMonitorLib from nuget.org (stable release)'
}
elseif ($NoUpdate) {
    if (-not (Test-Path (Join-Path $repoDir 'LibreHardwareMonitorLib\LibreHardwareMonitorLib.csproj'))) {
        Fail "No source in $repoDir - run without -NoUpdate first."
    }
}
else {
    if (Get-Command git -ErrorAction SilentlyContinue) {
        if (-not (Test-Path (Join-Path $repoDir '.git'))) {
            Write-Host "Cloning $repoUrl ..."
            New-Item -ItemType Directory -Force -Path $repoDir | Out-Null
            & git -C $repoDir init -q
            & git -C $repoDir remote add origin $repoUrl
        }
        Write-Host "Fetching LibreHardwareMonitor '$Ref' ..."
        & git -C $repoDir fetch -q --depth 1 origin $Ref
        if ($LASTEXITCODE -ne 0) { Fail "git fetch of '$Ref' failed." }
        & git -C $repoDir checkout -q --force FETCH_HEAD
        if ($LASTEXITCODE -ne 0) { Fail 'git checkout failed.' }
        & git -C $repoDir clean -q -fdx
    }
    else {
        # No git installed: download the source archive from GitHub.
        Write-Host "git not found - downloading source archive of '$Ref' from GitHub ..."
        $zip = Join-Path $env:TEMP "LibreHardwareMonitor-$([guid]::NewGuid()).zip"
        $tmp = Join-Path $env:TEMP "LibreHardwareMonitor-$([guid]::NewGuid())"
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -UseBasicParsing -Uri "https://codeload.github.com/LibreHardwareMonitor/LibreHardwareMonitor/zip/$Ref" -OutFile $zip
        Expand-Archive -Path $zip -DestinationPath $tmp -Force
        if (Test-Path $repoDir) { Remove-Item $repoDir -Recurse -Force }
        New-Item -ItemType Directory -Force -Path (Split-Path $repoDir) | Out-Null
        Move-Item (Get-ChildItem $tmp | Select-Object -First 1).FullName $repoDir
        Remove-Item $zip, $tmp -Recurse -Force -ErrorAction SilentlyContinue
        $lhmInfo = "LibreHardwareMonitor source archive '$Ref' (downloaded $(Get-Date -Format 'yyyy-MM-dd HH:mm'))"
    }
}

if (-not $FromNuGet -and -not $lhmInfo) {
    $lhmInfo = & git -C $repoDir log -1 --format='LibreHardwareMonitor commit %H (%cd)%n%s' --date=iso
}

# --- Build ----------------------------------------------------------------------------------
$source = if ($FromNuGet) { 'nuget' } else { 'repo' }
Write-Host "Building ($source) ..."
& dotnet build $project -c $Configuration "-p:LhmSource=$source" "-p:LhmRepoDir=$repoDir"
if ($LASTEXITCODE -ne 0) { Fail 'Build failed.' }

Set-Content -Path (Join-Path $dist 'BUILD-INFO.txt') -Encoding UTF8 -Value @(
    "OpenHardwareMonitorCLI (LibreHardwareMonitor edition)",
    "Built: $(Get-Date -Format 'yyyy-MM-dd HH:mm')",
    $lhmInfo
)

Write-Host ''
Write-Host 'Done. Files for Checkmk in dist\:' -ForegroundColor Green
Get-ChildItem $dist | ForEach-Object { Write-Host "  $($_.Name)" }
Write-Host ''
Write-Host $lhmInfo
