@echo off
echo.
echo ============================================
echo  Azure DevOps Service Connection Validator
echo ============================================
echo.
echo Starting guided validation wizard...
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-CustomerValidation.ps1"
echo.
echo Wizard complete. Press any key to close.
pause >nul
