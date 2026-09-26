@echo off
setlocal
cd /d "%~dp0"
call comprobar_entorno.bat
if errorlevel 1 exit /b 1
flutter devices

echo.
echo Conecta el telefono Android por USB, activa Depuracion USB y acepta la autorizacion.
pause
flutter devices
flutter install --release
if errorlevel 1 (
  echo No se pudo instalar automaticamente. Puedes copiar el APK de build\app\outputs\flutter-apk\app-release.apk al telefono.
  pause
  exit /b 1
)
echo Aplicacion instalada.
pause
