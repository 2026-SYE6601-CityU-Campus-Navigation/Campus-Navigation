# ============================================================
#  城大校园导航 · 本地生成式 AI 一键部署脚本
#  功能：安装 Ollama 到 D:\Ollama，模型存 D:\CityUproject\LocalAI\models
#        自动检测显卡显存，按映射表选择 Qwen3 小模型
#  用法：双击 install_ollama.bat（或右键本文件用 PowerShell 运行）
# ============================================================
$ErrorActionPreference = "Stop"

$LocalAI     = "D:\CityUproject\LocalAI"
$OllamaDir   = "D:\Ollama"
$ModelsDir   = "$LocalAI\models"
$Installer   = "$LocalAI\OllamaSetup.exe"
$DownloadUrl = "https://ollama.com/download/OllamaSetup.exe"

Write-Host ""
Write-Host "===== 城大校园导航 · 本地生成式 AI 部署 =====" -ForegroundColor Cyan

# ---------- 1. 检测显卡显存 ----------
$vramMB = 0
if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
    try {
        $lines = & nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>$null
        foreach ($line in $lines) {
            $v = [int]($line.ToString().Trim())
            if ($v -gt $vramMB) { $vramMB = $v }
        }
    } catch { $vramMB = 0 }
}
if ($vramMB -le 0) {
    # 无 NVIDIA 显卡或驱动缺失：用 WMI 粗略估计（>4GB 的显卡可能读不准，以 nvidia-smi 为准）
    try {
        foreach ($g in Get-CimInstance Win32_VideoController) {
            if ($g.AdapterRAM -and $g.AdapterRAM -gt 0) {
                $v = [double]$g.AdapterRAM / 1MB
                if ($v -gt $vramMB) { $vramMB = $v }
            }
        }
    } catch { $vramMB = 0 }
}
$vramGB = [math]::Round($vramMB / 1024, 1)

# ---------- 2. 按显存选择模型 ----------
$model  = "qwen3:1.7b"
$reason = "未检测到可用显卡，按 CPU 模式选择"
if     ($vramGB -ge 12)  { $model = "qwen3:14b"; $reason = "显存 >= 12GB" }
elseif ($vramGB -ge 6)   { $model = "qwen3:8b";  $reason = "显存 6~12GB" }
elseif ($vramGB -ge 3.5) { $model = "qwen3:4b";  $reason = "显存 3.5~6GB" }
elseif ($vramGB -ge 1.5) { $model = "qwen3:1.7b"; $reason = "显存 1.5~3.5GB" }

Write-Host "检测到显存：$vramGB GB（$reason）" -ForegroundColor Yellow
Write-Host "将部署模型：$model"                -ForegroundColor Yellow
Write-Host "模型存储目录：$ModelsDir"           -ForegroundColor Yellow
Write-Host ""

# ---------- 3. 建目录 ----------
New-Item -ItemType Directory -Force -Path $LocalAI, $ModelsDir | Out-Null

# ---------- 4. 安装 Ollama 到 D:\Ollama ----------
if (Test-Path "$OllamaDir\ollama.exe") {
    Write-Host "Ollama 已存在（$OllamaDir），跳过安装。" -ForegroundColor Green
} else {
    Write-Host "正在下载 Ollama 安装包（约 1GB，视网速需数分钟）..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $Installer -UseBasicParsing
    Write-Host "正在安装到 $OllamaDir ..." -ForegroundColor Cyan
    Start-Process -FilePath $Installer -ArgumentList '/S', '/DIR="D:\Ollama"' -Wait
    if (-not (Test-Path "$OllamaDir\ollama.exe")) {
        Write-Host "静默安装后未找到程序，可能已弹出安装界面。" -ForegroundColor Red
        Write-Host "请手动运行 $Installer 并把安装目录选为 D:\Ollama，装完后再双击本脚本一次。" -ForegroundColor Red
        exit 1
    }
    Remove-Item $Installer -ErrorAction SilentlyContinue
}

# ---------- 5. 设置环境变量（模型目录 + PATH） ----------
[Environment]::SetEnvironmentVariable("OLLAMA_MODELS", $ModelsDir, "User")
$path = [Environment]::GetEnvironmentVariable("Path", "User")
if ($path -notlike "*$OllamaDir*") {
    [Environment]::SetEnvironmentVariable("Path", "$path;$OllamaDir", "User")
}

# ---------- 6. 重启 Ollama 使环境变量生效 ----------
Get-Process -Name "ollama*" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2
Start-Process -FilePath "$OllamaDir\ollama app.exe"
Start-Sleep -Seconds 5

# ---------- 7. 拉取模型 ----------
Write-Host "正在拉取模型 $model（首次需下载，视大小需几分钟到几十分钟）..." -ForegroundColor Cyan
& "$OllamaDir\ollama.exe" pull $model
& "$OllamaDir\ollama.exe" list
Set-Content -Path "$LocalAI\active_model.txt" -Value $model -Encoding UTF8

# ---------- 8. 测试 ----------
Write-Host "正在测试模型..." -ForegroundColor Cyan
& "$OllamaDir\ollama.exe" run $model "用一句话介绍香港城市大学" --nowordwrap

Write-Host ""
Write-Host "===== 部署完成 =====" -ForegroundColor Green
Write-Host "本机 API 地址：http://localhost:11434"
Write-Host "命令行试用：D:\Ollama\ollama.exe run $model"
Write-Host "Python 示例：python D:\CityUproject\LocalAI\test_api.py 图书馆"
