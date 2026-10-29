@echo off
rem Builds the Checkmk drop-in package into .\dist
rem
rem   build.cmd                 LibreHardwareMonitor from the current repository state (master)
rem   build.cmd -Ref v0.9.6     a specific branch, tag or commit
rem   build.cmd -NoUpdate       rebuild the already downloaded source without updating
rem   build.cmd -FromNuGet      last stable release from nuget.org
rem
rem Requirement: .NET 10 SDK   (winget install Microsoft.DotNet.SDK.10), git recommended
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build.ps1" %*
exit /b %errorlevel%
