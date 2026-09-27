@echo off
setlocal enabledelayedexpansion

rem === Release package of the player ==========================================
rem Builds dist\Player\ (and dist\Player.zip):
rem
rem   Player\
rem     Player.exe, Player.pck, libgozen...dll
rem     README.md             <- release\README.md
rem     portable.ini          <- release\portable.ini: saves stay in this folder
rem     shaders\              the built-in includes (preludes), editable
rem     shaders\effects\      the built-in effects, editable; add your own
rem     shaders\sources\      the built-in layer shaders, editable; add your own
rem     shaders\surfaces\     the built-in surfaces (Pillow, Dome), editable; add your own
rem     shaders\vertex\       the built-in vertex effects, editable; add your own
rem     presets\              <- release\presets\ (if any); the player saves here
rem     save\                 created by the player: settings and other saves
rem     media\                <- release\media\ (samples); the Files tab opens here
rem
rem Godot 4.7 must be on PATH as `godot`, with the Windows export templates
rem installed, and the release build of gozen at
rem project_engine\addons\gde_gozen\bin\libgozen.windows.template_release.x86_64.dll.

set REPO=%~dp0
if "%REPO:~-1%"=="\" set REPO=%REPO:~0,-1%

set ENGINE_PROJECT=%REPO%\project_engine
set VIS=%ENGINE_PROJECT%\player\visualizer
set RELEASE=%REPO%\release
set DIST_ROOT=%REPO%\dist
set DIST=%DIST_ROOT%\Player
set ZIP=%DIST_ROOT%\Player.zip
set PRESET=Windows Desktop
set GOZEN_DLL=%ENGINE_PROJECT%\addons\gde_gozen\bin\libgozen.windows.template_release.x86_64.dll

where godot >nul 2>&1
if errorlevel 1 (
    echo [error] `godot` not found on PATH. Install Godot 4.7 or add it to PATH.
    exit /b 1
)
if not exist "%GOZEN_DLL%" (
    echo [error] Missing the release build of gozen:
    echo   %GOZEN_DLL%
    exit /b 1
)

if exist "%DIST%" rmdir /s /q "%DIST%"
if exist "%ZIP%" del /q "%ZIP%"
mkdir "%DIST%"

echo.
echo === [1/3] Export release binary to %DIST%\Player.exe ===
godot --headless --path "%ENGINE_PROJECT%" --export-release "%PRESET%" "%DIST%\Player.exe"
if errorlevel 1 (
    echo [error] Export failed. Check the Windows export templates and the
    echo   "%PRESET%" preset in %ENGINE_PROJECT%\export_presets.cfg.
    exit /b 1
)
if not exist "%DIST%\Player.exe" (
    echo [error] Godot returned success but %DIST%\Player.exe is missing.
    exit /b 1
)

echo.
echo === [2/3] Shaders, presets, media, README ===
mkdir "%DIST%\shaders\effects" "%DIST%\shaders\sources" "%DIST%\shaders\surfaces" "%DIST%\shaders\vertex" "%DIST%\presets" "%DIST%\media"
copy /y "%VIS%\*.gdshaderinc" "%DIST%\shaders\" >nul || exit /b 1
copy /y "%VIS%\effects\*.gdshader" "%DIST%\shaders\effects\" >nul || exit /b 1
copy /y "%VIS%\shaders\*.gdshader" "%DIST%\shaders\sources\" >nul || exit /b 1
copy /y "%VIS%\surfaces\*.gdshaderinc" "%DIST%\shaders\surfaces\" >nul || exit /b 1
copy /y "%VIS%\vertex\*.gdshaderinc" "%DIST%\shaders\vertex\" >nul || exit /b 1
copy /y "%RELEASE%\README.md" "%DIST%\README.md" >nul || exit /b 1
copy /y "%RELEASE%\portable.ini" "%DIST%\portable.ini" >nul || exit /b 1
if exist "%RELEASE%\presets" robocopy "%RELEASE%\presets" "%DIST%\presets" /e /njh /njs /nfl /ndl >nul
if exist "%RELEASE%\media" robocopy "%RELEASE%\media" "%DIST%\media" /e /xf .gitkeep /njh /njs /nfl /ndl >nul
rem robocopy exit codes below 8 are success.
if errorlevel 8 (
    echo [error] Copying presets or media failed.
    exit /b 1
)

echo.
echo === [3/3] Zip to %ZIP% ===
powershell -NoProfile -Command "Compress-Archive -Path '%DIST%' -DestinationPath '%ZIP%' -Force"
if errorlevel 1 (
    echo [error] Zipping failed.
    exit /b 1
)

echo.
echo Done: %DIST%
echo       %ZIP%
exit /b 0
