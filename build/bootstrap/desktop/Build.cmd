@echo off
powershell -ExecutionPolicy ByPass %~dp0Build.ps1 -restore -build %*
exit /b %ErrorLevel%
