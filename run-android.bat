@echo off
setlocal
set "PROJECT_DIR=%~dp0"
set "FLUTTER=%PROJECT_DIR%..\flutter\bin\flutter.bat"
set "ANDROID_HOME=%LOCALAPPDATA%\Android\Sdk"
set "ANDROID_SDK_ROOT=%ANDROID_HOME%"
set "JAVA_HOME=C:\Program Files\Android\Android Studio\jbr"
set "PUB_CACHE=%PROJECT_DIR%..\pub-cache"
set "GRADLE_USER_HOME=%PROJECT_DIR%..\gradle-home"
set "FLUTTER_SUPPRESS_ANALYTICS=true"
set "PATH=%JAVA_HOME%\bin;%ANDROID_HOME%\platform-tools;%PATH%"

if not exist "%FLUTTER%" (
  echo Flutter SDK not found at "%FLUTTER%".
  goto :failed
)
if not exist "%JAVA_HOME%\bin\java.exe" (
  echo Android Studio Java not found at "%JAVA_HOME%\bin\java.exe".
  goto :failed
)
"%ANDROID_HOME%\platform-tools\adb.exe" -s emulator-5554 get-state >nul 2>&1
if errorlevel 1 (
  echo Start Pixel 9a in Android Studio Device Manager, then run this file again.
  goto :failed
)
cd /d "%PROJECT_DIR%"
echo Syncing Flutter packages...
call "%FLUTTER%" pub get
if errorlevel 1 goto :failed
echo Launching the single-file preview on Pixel 9a...
call "%FLUTTER%" run -d emulator-5554
if errorlevel 1 goto :failed
echo Press any key to close this window.
pause >nul
exit /b 0

:failed
echo.
echo Could not start the preview. Check the message above.
pause
exit /b 1
