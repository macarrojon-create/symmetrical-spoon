@echo off
setlocal
cd /d "%~dp0"
where flutter >nul 2>nul
if errorlevel 1 (
  echo Flutter no esta instalado o no esta en PATH.
  pause
  exit /b 1
)
flutter create . --platforms=android,windows --org com.andy.readingjournal
flutter pub get
pause
