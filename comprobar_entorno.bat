@echo off
where flutter >nul 2>nul
if errorlevel 1 (
  echo ERROR: Flutter no esta instalado o no esta en PATH.
  echo Instala Flutter y vuelve a abrir esta ventana de CMD.
  exit /b 1
)
where adb >nul 2>nul
if errorlevel 1 echo AVISO: ADB no esta en PATH. Podras generar el APK, pero no instalarlo automaticamente.
flutter doctor -v
if errorlevel 1 (
  echo.
  echo Flutter ha detectado problemas en el entorno. Corrigelos antes de continuar.
  exit /b 1
)
exit /b 0
