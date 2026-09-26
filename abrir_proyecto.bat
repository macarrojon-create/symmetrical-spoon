@echo off
cd /d "%~dp0"
if exist "%ProgramFiles%\Android\Android Studio\bin\studio64.exe" (
  start "" "%ProgramFiles%\Android\Android Studio\bin\studio64.exe" "%CD%"
) else if exist "%LOCALAPPDATA%\Programs\Microsoft VS Code\Code.exe" (
  start "" "%LOCALAPPDATA%\Programs\Microsoft VS Code\Code.exe" "%CD%"
) else (
  start "" "%CD%"
)
