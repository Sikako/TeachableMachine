param(
    [string]$ZipPath = (Join-Path (Split-Path -Parent $PSScriptRoot) "實作III\my-pose-model.zip"),
    [string]$ModelDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) "model"),
    [ValidateRange(1024, 65535)]
    [int]$Port = 8000,
    [switch]$PrepareOnly,
    [switch]$NoBrowser
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
$pidFile = Join-Path $root ".classroom-server.pid"
$serverProcess = $null

function Test-PortAvailable {
    param([int]$CandidatePort)

    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $CandidatePort)
    try {
        $listener.Start()
        return $true
    } catch {
        return $false
    } finally {
        $listener.Stop()
    }
}

function Stop-PreviousClassroomServer {
    if (-not (Test-Path -LiteralPath $pidFile -PathType Leaf)) {
        return
    }

    try {
        $serverState = Get-Content -Raw -LiteralPath $pidFile | ConvertFrom-Json
        $processInfo = Get-CimInstance Win32_Process -Filter "ProcessId = $($serverState.pid)" -ErrorAction SilentlyContinue
        if ($processInfo -and
            $processInfo.CommandLine -like "*http.server*" -and
            $processInfo.CommandLine -like "*$root*") {
            Stop-Process -Id ([int]$serverState.pid) -Force
            Write-Host "已停止上一個課堂伺服器。" -ForegroundColor DarkGray
        }
    } catch {
        Write-Warning "無法確認上一個課堂伺服器，將改用其他可用連接埠。"
    } finally {
        Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
    }
}

function Install-ModelArchive {
    $resolvedZipPath = [System.IO.Path]::GetFullPath($ZipPath)
    $resolvedModelDirectory = [System.IO.Path]::GetFullPath($ModelDirectory)

    if (-not (Test-Path -LiteralPath $resolvedZipPath -PathType Leaf)) {
        throw "找不到模型壓縮檔：$resolvedZipPath"
    }

    $modelParent = Split-Path -Parent $resolvedModelDirectory
    New-Item -ItemType Directory -Path $modelParent -Force | Out-Null

    $operationId = [Guid]::NewGuid().ToString("N")
    $stagingDirectory = Join-Path $modelParent ".model-staging-$operationId"
    $incomingDirectory = Join-Path $modelParent ".model-incoming-$operationId"
    $backupDirectory = Join-Path $modelParent ".model-backup-$operationId"

    try {
        Expand-Archive -LiteralPath $resolvedZipPath -DestinationPath $stagingDirectory -Force

        $modelFiles = @(Get-ChildItem -LiteralPath $stagingDirectory -Recurse -File -Filter "model.json")
        if ($modelFiles.Count -ne 1) {
            throw "ZIP 必須包含一個 model.json。"
        }

        $sourceDirectory = $modelFiles[0].Directory.FullName
        foreach ($requiredFile in @("metadata.json", "weights.bin")) {
            if (-not (Test-Path -LiteralPath (Join-Path $sourceDirectory $requiredFile) -PathType Leaf)) {
                throw "ZIP 缺少 $requiredFile。"
            }
        }

        $metadata = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $sourceDirectory "metadata.json") | ConvertFrom-Json
        if (($metadata.labels -join ",") -ne "開,合") {
            throw "模型類別必須依序為「開、合」，目前為：$($metadata.labels -join '、')。"
        }

        Move-Item -LiteralPath $sourceDirectory -Destination $incomingDirectory

        if (Test-Path -LiteralPath $resolvedModelDirectory) {
            Move-Item -LiteralPath $resolvedModelDirectory -Destination $backupDirectory
        }

        try {
            Move-Item -LiteralPath $incomingDirectory -Destination $resolvedModelDirectory
        } catch {
            if (Test-Path -LiteralPath $backupDirectory) {
                Move-Item -LiteralPath $backupDirectory -Destination $resolvedModelDirectory
            }
            throw
        }

        if (Test-Path -LiteralPath $backupDirectory) {
            Remove-Item -LiteralPath $backupDirectory -Recurse -Force
        }

        Write-Host "模型已更新：開、合（$($metadata.timeStamp)）" -ForegroundColor Green
    } finally {
        foreach ($temporaryPath in @($stagingDirectory, $incomingDirectory)) {
            if (Test-Path -LiteralPath $temporaryPath) {
                Remove-Item -LiteralPath $temporaryPath -Recurse -Force
            }
        }
    }
}

try {
    Install-ModelArchive

    if ($PrepareOnly) {
        return
    }

    Stop-PreviousClassroomServer

    $selectedPort = $null
    foreach ($candidatePort in $Port..([Math]::Min($Port + 10, 65535))) {
        if (Test-PortAvailable -CandidatePort $candidatePort) {
            $selectedPort = $candidatePort
            break
        }
    }
    if (-not $selectedPort) {
        throw "找不到可用的本機連接埠（$Port 至 $([Math]::Min($Port + 10, 65535))）。"
    }

    $python = Get-Command python -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $python) {
        throw "找不到 Python。請先安裝 Python 3，並確認 python 指令可用。"
    }

    $serverArguments = @(
        "-m", "http.server", "$selectedPort",
        "--bind", "127.0.0.1",
        "--directory", $root
    )
    $serverProcess = Start-Process -FilePath $python.Source -ArgumentList $serverArguments -WindowStyle Hidden -PassThru
    [PSCustomObject]@{
        pid = $serverProcess.Id
        port = $selectedPort
    } | ConvertTo-Json | Set-Content -LiteralPath $pidFile -Encoding UTF8

    $modelVersion = (Get-Item -LiteralPath $ZipPath).LastWriteTimeUtc.Ticks
    $url = "http://127.0.0.1:$selectedPort/index.html?model=$modelVersion"
    $metadataUrl = "http://127.0.0.1:$selectedPort/model/metadata.json?model=$modelVersion"
    $ready = $false
    for ($attempt = 0; $attempt -lt 20; $attempt += 1) {
        if ($serverProcess.HasExited) {
            throw "本機伺服器啟動失敗。"
        }
        try {
            $metadataResponse = Invoke-WebRequest -UseBasicParsing -Uri $metadataUrl -TimeoutSec 1
            if ($metadataResponse.StatusCode -eq 200) {
                $ready = $true
                break
            }
        } catch {
            Start-Sleep -Milliseconds 250
        }
    }
    if (-not $ready) {
        throw "本機伺服器未能在期限內提供正確模型。"
    }

    if (-not $NoBrowser) {
        Start-Process $url
    }

    Write-Host "課堂頁面已就緒：$url" -ForegroundColor Cyan
    Write-Host "重新下載模型後，再雙擊「啟動課堂.cmd」即可更新。" -ForegroundColor Cyan
} catch {
    if ($serverProcess -and -not $serverProcess.HasExited) {
        Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
    Write-Error $_
    exit 1
}
