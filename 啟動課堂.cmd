@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\prepare-classroom.ps1" %*
set "EXIT_CODE=%ERRORLEVEL%"

echo.
if not "%EXIT_CODE%"=="0" (
    echo.
    echo 啟動失敗，請查看上方錯誤訊息。
) else (
    echo 啟動流程已完成，瀏覽器應已開啟課堂頁面。
)
echo 按任意鍵關閉此視窗；背景伺服器會繼續執行。
pause >nul
exit /b %EXIT_CODE%
