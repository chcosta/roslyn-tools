@echo off
powershell -ExecutionPolicy ByPass %~dp0Build.ps1 -restore %*
exit /b %ErrorLevel%
