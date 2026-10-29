<#
.SYNOPSIS
  Installs the LibreHardwareMonitor based OpenHardwareMonitorCLI into a locally installed
  Checkmk Windows agent (without agent bakery).

.DESCRIPTION
  - stops the Checkmk agent service and a running OpenHardwareMonitorCLI.exe
  - optionally removes the old, vulnerable WinRing0 driver service of the original OHM
  - removes the old WMI namespace root\OpenHardwareMonitor (schema of the old provider)
  - copies OpenHardwareMonitorCLI.exe + OpenHardwareMonitorLib.dll (+ optional .config)
    to C:\ProgramData\checkmk\agent\bin
  - starts the agent and checks that sensors appear in WMI

.PARAMETER Source
  Folder with OpenHardwareMonitorCLI.exe and OpenHardwareMonitorLib.dll (default: ..\dist or script folder)

.PARAMETER RemoveWinRing0
  Stop and delete the WinRing0 driver service left behind by the original OpenHardwareMonitor.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\install-checkmk.ps1 -RemoveWinRing0
#>
[CmdletBinding()]
param(
    [string]$Source,
    [string]$AgentBin = (Join-Path $env:ProgramData 'checkmk\agent\bin'),
    [string]$ServiceName = 'CheckMkService',
    [switch]$RemoveWinRing0
)

$ErrorActionPreference = 'Stop'

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Please run this script as administrator.'
}

if (-not $Source) {
    foreach ($candidate in @((Join-Path $PSScriptRoot '..\dist'), $PSScriptRoot, (Get-Location).Path)) {
        if (Test-Path (Join-Path $candidate 'OpenHardwareMonitorCLI.exe')) { $Source = $candidate; break }
    }
}
if (-not $Source -or -not (Test-Path (Join-Path $Source 'OpenHardwareMonitorCLI.exe')) -or -not (Test-Path (Join-Path $Source 'OpenHardwareMonitorLib.dll'))) {
    throw 'OpenHardwareMonitorCLI.exe / OpenHardwareMonitorLib.dll not found. Use -Source <folder>.'
}
if (-not (Test-Path $AgentBin)) {
    throw "Checkmk agent folder '$AgentBin' not found - is the Checkmk agent installed?"
}

Write-Host "Stopping $ServiceName ..."
$svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($svc -and $svc.Status -ne 'Stopped') { Stop-Service -Name $ServiceName -Force }
Get-Process -Name 'OpenHardwareMonitorCLI' -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2

if ($RemoveWinRing0) {
    foreach ($drv in @('winring0_1_2_0', 'WinRing0_1_2_0', 'WinRing0x64')) {
        if (Get-Service -Name $drv -ErrorAction SilentlyContinue) {
            Write-Host "Removing old driver service $drv ..."
            & sc.exe stop $drv | Out-Null
            & sc.exe delete $drv | Out-Null
        }
    }
    foreach ($sys in @('OpenHardwareMonitorLib.sys', 'WinRing0x64.sys')) {
        $f = Join-Path $AgentBin $sys
        if (Test-Path $f) { Remove-Item $f -Force -ErrorAction SilentlyContinue }
    }
}

Write-Host 'Removing old WMI namespace root\OpenHardwareMonitor ...'
Get-CimInstance -Namespace 'root' -ClassName '__Namespace' -Filter "Name='OpenHardwareMonitor'" -ErrorAction SilentlyContinue |
    Remove-CimInstance -ErrorAction SilentlyContinue

Write-Host "Copying files to $AgentBin ..."
Copy-Item (Join-Path $Source 'OpenHardwareMonitorCLI.exe') $AgentBin -Force
Copy-Item (Join-Path $Source 'OpenHardwareMonitorLib.dll') $AgentBin -Force
$config = Join-Path $Source 'OpenHardwareMonitorCLI.exe.config'
if (Test-Path $config) { Copy-Item $config $AgentBin -Force }

$pawn = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\PawnIO' -ErrorAction SilentlyContinue
if ($pawn) {
    Write-Host "PawnIO driver found: $($pawn.DisplayVersion)"
} else {
    Write-Warning 'PawnIO driver is NOT installed. CPU temperatures, mainboard (SuperIO) and RAM sensors will be missing.'
    Write-Warning 'Install it with:  winget install namazso.PawnIO   (or https://pawnio.eu)'
}

Write-Host "Starting $ServiceName ..."
if ($svc) { Start-Service -Name $ServiceName }

Write-Host 'Waiting for sensors in WMI (the agent starts the CLI on its first run) ...'
$sensors = $null
for ($i = 0; $i -lt 12 -and -not $sensors; $i++) {
    Start-Sleep -Seconds 5
    $sensors = Get-CimInstance -Namespace 'root/OpenHardwareMonitor' -ClassName Sensor -ErrorAction SilentlyContinue
}

if ($sensors) {
    Write-Host ("OK: {0} sensors published in root\OpenHardwareMonitor" -f @($sensors).Count) -ForegroundColor Green
    $sensors | Sort-Object Parent, SensorType, Index | Select-Object Index, Name, Parent, SensorType, Value | Format-Table -AutoSize
} else {
    Write-Warning 'No sensors in WMI yet. The agent starts the CLI when Checkmk queries it - run "cmk -d <host>" on the site, or test manually:'
    Write-Warning "  & '$AgentBin\OpenHardwareMonitorCLI.exe' --dump"
}
