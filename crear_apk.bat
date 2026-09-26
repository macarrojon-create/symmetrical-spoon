@echo off
setlocal
cd /d "%~dp0"
call comprobar_entorno.bat
if errorlevel 1 exit /b 1

echo.
echo [1/3] Instalando dependencias...
flutter pub get
if errorlevel 1 goto :error

echo.
echo [2/3] Comprobando codigo...
flutter analyze
if errorlevel 1 goto :error

echo.
echo [3/3] Generando APK de Android...
flutter build apk --release
if errorlevel 1 goto :error

echo.
echo ============================================
echo APK CREADO CORRECTAMENTE
echo ============================================
echo.
echo %CD%\build\app\outputs\flutter-apk\app-release.apk
start "" explorer /select,"%CD%\build\app\outputs\flutter-apk\app-release.apk"
pause
exit /b 0
:error
echo.
echo ERROR: revisa el mensaje anterior.
pause
exit /b 1
