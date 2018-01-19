@echo off
powershell -ExecutionPolicy ByPass %~dp0Build.ps1 -test %*
exit /b %ErrorLevel%