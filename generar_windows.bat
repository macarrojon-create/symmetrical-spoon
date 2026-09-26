@echo off
setlocal
cd /d "%~dp0"
call comprobar_entorno.bat
if errorlevel 1 exit /b 1
if not exist "windows" flutter create . --platforms=windows --org com.andy.readingjournal
flutter pub get
flutter analyze
if errorlevel 1 exit /b 1
flutter build windows --release
if errorlevel 1 exit /b 1
echo.
echo Windows creado en:
echo %CD%\build\windows\x64\runner\Release
start "" explorer "%CD%\build\windows\x64\runner\Release"
pause
