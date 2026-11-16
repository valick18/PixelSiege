@echo off
setlocal
rem === Builds build\PixelSiege.exe (one file) ===
rem Godot is searched in this order: %GODOT% variable, folder _tools (any Godot*.exe), PATH.
rem Export templates must be installed once: Godot > Editor > Manage Export Templates > Download.
set "ROOT=%~dp0."
if not defined GODOT call :find_godot
if not defined GODOT set "GODOT=godot"
if not exist "%GODOT%" where "%GODOT%" >nul 2>nul || goto :nogodot
if not exist "%ROOT%\build" mkdir "%ROOT%\build"
echo Using Godot: %GODOT%
"%GODOT%" --headless --path "%ROOT%" --import
"%GODOT%" --headless --path "%ROOT%" --export-release "Windows Desktop" "%ROOT%\build\PixelSiege.exe"
if exist "%ROOT%\build\PixelSiege.exe" (
  echo.
  echo DONE: build\PixelSiege.exe
) else (
  echo.
  echo FAILED. Check that export templates are installed.
)
pause
exit /b 0

:find_godot
for %%F in ("%ROOT%\_tools\Godot*.exe" "%ROOT%\_tools\godot*.exe" "%ROOT%\_tools\*\Godot*.exe" "%ROOT%\_tools\*\godot*.exe") do (
  if not defined GODOT set "GODOT=%%~fF"
)
exit /b 0

:nogodot
echo Godot not found. Put Godot_v4.x_win64.exe into the _tools folder, or set GODOT=full\path\to\godot.exe
pause
exit /b 1
