@echo off
setlocal
cd /d "%~dp0"
call comprobar_entorno.bat
if errorlevel 1 exit /b 1
if not exist "windows" flutter create . --platforms=windows --org com.andy.readingjournal
flutter pub get
flutter run -d windows
pause
