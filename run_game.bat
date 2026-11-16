@echo off
setlocal
rem Runs the project directly with Godot. Godot is searched: %GODOT%, folder _tools, PATH.
set "ROOT=%~dp0."
if not defined GODOT call :find_godot
if not defined GODOT set "GODOT=godot"
if not exist "%GODOT%" where "%GODOT%" >nul 2>nul || goto :nogodot
start "" "%GODOT%" --path "%ROOT%"
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
