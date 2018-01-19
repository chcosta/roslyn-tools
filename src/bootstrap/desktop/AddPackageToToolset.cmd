@echo off
powershell -ExecutionPolicy ByPass %~dp0Build.ps1 -addpackage -restore %*
exit /b %ErrorLevel%
