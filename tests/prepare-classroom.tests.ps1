$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$launcher = Join-Path $root "scripts\prepare-classroom.ps1"
$shortcut = Join-Path $root "啟動課堂.cmd"
$index = Join-Path $root "index.html"
$zip = Join-Path $root "實作III\my-pose-model.zip"
$testModelDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("tm-model-test-" + [Guid]::NewGuid().ToString("N"))

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

try {
    Assert-True (Test-Path -LiteralPath $launcher -PathType Leaf) "缺少課堂準備腳本"
    Assert-True (Test-Path -LiteralPath $shortcut -PathType Leaf) "缺少可雙擊的啟動課堂.cmd"

    $launcherBytes = [System.IO.File]::ReadAllBytes($launcher)
    $hasUtf8Bom = $launcherBytes.Length -ge 3 -and
        $launcherBytes[0] -eq 0xEF -and
        $launcherBytes[1] -eq 0xBB -and
        $launcherBytes[2] -eq 0xBF
    Assert-True $hasUtf8Bom "PowerShell 腳本必須使用 UTF-8 BOM，才能由 Windows PowerShell 5.1 正確讀取中文"

    $shortcutSource = Get-Content -Raw -LiteralPath $shortcut
    Assert-True ($shortcutSource.Contains('set "EXIT_CODE=%ERRORLEVEL%"')) "啟動器必須保存 PowerShell 結束碼"
    Assert-True ($shortcutSource.Contains("啟動流程已完成")) "啟動器成功後必須顯示完成訊息"
    Assert-True ($shortcutSource.Contains("%*")) "啟動器必須轉交命令列參數"

    $shortcutBytes = [System.IO.File]::ReadAllBytes($shortcut)
    $hasWindowsLineEnding = $false
    for ($byteIndex = 1; $byteIndex -lt $shortcutBytes.Length; $byteIndex += 1) {
        if ($shortcutBytes[$byteIndex - 1] -eq 13 -and $shortcutBytes[$byteIndex] -eq 10) {
            $hasWindowsLineEnding = $true
            break
        }
    }
    Assert-True $hasWindowsLineEnding "啟動器必須使用 Windows CRLF 換行"

    & $launcher -ZipPath $zip -ModelDirectory $testModelDirectory -PrepareOnly

    foreach ($fileName in @("model.json", "metadata.json", "weights.bin")) {
        Assert-True (Test-Path -LiteralPath (Join-Path $testModelDirectory $fileName) -PathType Leaf) "模型缺少 $fileName"
    }

    $metadata = Get-Content -Raw -LiteralPath (Join-Path $testModelDirectory "metadata.json") | ConvertFrom-Json
    Assert-True (($metadata.labels -join ",") -eq "開,合") "模型類別必須依序為開、合"

    $indexSource = Get-Content -Raw -LiteralPath $index
    Assert-True ($indexSource.Contains('const MODEL_URL = "./model/";')) "index.html 尚未改用本機模型"
    Assert-True (-not $indexSource.Contains("teachablemachine.withgoogle.com/models/")) "index.html 仍依賴雲端模型"

    Write-Host "PASS: 課堂啟動器可部署開／合本機模型，且 index.html 使用本機模型。" -ForegroundColor Green
} finally {
    if (Test-Path -LiteralPath $testModelDirectory) {
        Remove-Item -LiteralPath $testModelDirectory -Recurse -Force
    }
}
