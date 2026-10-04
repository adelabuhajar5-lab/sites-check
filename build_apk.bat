@echo off
REM Build the APK on your own Windows PC (needs Flutter + Android Studio installed).
REM Run this file from inside this folder.
call flutter create --platforms=android --org com.sitescheck --project-name sites_check build_app
if errorlevel 1 exit /b 1
rmdir /s /q build_app\lib
rmdir /s /q build_app\test
xcopy /e /i /y lib build_app\lib
copy /y pubspec.yaml build_app\pubspec.yaml
cd build_app
call flutter pub get
call flutter build apk --release
echo.
echo Done. Your APK is here:
echo   %cd%\build\app\outputs\flutter-apk\app-release.apk
pause
