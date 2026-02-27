@echo off
REM FPC Diagnostic Harness Runner
REM Renders test scenes and saves output to diag_output/
REM
REM Usage:
REM   run_diag.bat                     - Render default scene only
REM   run_diag.bat ABoxScale2Start.m3p - Render specific scene
REM   run_diag.bat ALL                 - Render all test matrix scenes
REM

setlocal enabledelayedexpansion

set EXEDIR=%~dp0..
set EXE=%EXEDIR%\Mandelbulb3D.exe
set PARAMDIR=%EXEDIR%\M3Parameter
set OUTDIR=%EXEDIR%\diag_output

if not exist "%EXE%" (
    echo ERROR: Mandelbulb3D.exe not found at %EXE%
    echo Build with -dFPC_DIAG first.
    exit /b 1
)

if not exist "%OUTDIR%" mkdir "%OUTDIR%"

if "%1"=="" (
    echo === Running default scene ===
    "%EXE%" --diag
    goto :done
)

if /i "%1"=="ALL" (
    echo === Running full test matrix ===

    echo.
    echo [1/6] Default scene ^(IntPow8^)
    "%EXE%" --diag

    echo.
    echo [2/6] ABoxScale2Start ^(AmazingBox^)
    "%EXE%" --diag "%PARAMDIR%\ABoxScale2Start.m3p"

    echo.
    echo [3/6] Aexion 10bulbs ^(AexionC^)
    "%EXE%" --diag "%PARAMDIR%\Aexion 10bulbs.m3p"

    echo.
    echo [4/6] BulboxCut ^(Bulbox^)
    "%EXE%" --diag "%PARAMDIR%\BulboxCut.m3p"

    echo.
    echo [5/6] ApolloBalloons dIFS ^(dIFS^)
    "%EXE%" --diag "%PARAMDIR%\ApolloBalloons dIFS.m3p"

    echo.
    echo [6/6] QuatP4hybridJulia ^(Quaternion^)
    "%EXE%" --diag "%PARAMDIR%\QuatP4hybridJulia.m3p"

    goto :done
)

REM Single scene
echo === Running scene: %1 ===
if exist "%1" (
    "%EXE%" --diag "%1"
) else if exist "%PARAMDIR%\%1" (
    "%EXE%" --diag "%PARAMDIR%\%1"
) else (
    echo ERROR: Scene file not found: %1
    exit /b 1
)

:done
echo.
echo === Done. Output in %OUTDIR% ===
dir /b "%OUTDIR%\*.bmp" 2>nul
dir /b "%OUTDIR%\*.txt" 2>nul
