# ============================================================
#  修复脚本：把已下载的模型从 C 盘搬到 D 盘，并让 Ollama 认新位置
#  背景：首次安装时用户级环境变量 OLLAMA_MODELS 未被子进程继承，
#        模型落在了默认目录 C:\Users\<你>\.ollama\models
#  用法：双击 fix_models_to_d.bat
# ============================================================
$ErrorActionPreference = "Stop"

$ModelsDir     = "D:\CityUproject\LocalAI\models"
$DefaultModels = "$env:USERPROFILE\.ollama\models"
$OllamaDir     = "D:\Ollama"

Write-Host ""
Write-Host "===== 模型搬移修复 =====" -ForegroundColor Cyan

if (-not (Test-Path "$OllamaDir\ollama.exe")) {
    Write-Host "未找到 D:\Ollama\ollama.exe，请先确认安装脚本已成功安装 Ollama。" -ForegroundColor Red
    exit 1
}

# ---------- 1. 彻底退出 Ollama ----------
Write-Host "正在退出 Ollama..." -ForegroundColor Cyan
Get-Process -Name "ollama*" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2

# ---------- 2. 永久设置环境变量（用户级） ----------
[Environment]::SetEnvironmentVariable("OLLAMA_MODELS", $ModelsDir, "User")
Write-Host "OLLAMA_MODELS 已设为 $ModelsDir" -ForegroundColor Green

# ---------- 3. 移动模型文件 ----------
New-Item -ItemType Directory -Force -Path $ModelsDir | Out-Null
$count = 0
if (Test-Path $DefaultModels) {
    $count = (Get-ChildItem $DefaultModels -Recurse -File | Measure-Object).Count
}
if ($count -gt 0) {
    Write-Host "发现 $count 个模型文件，正在从 C 盘移动到 D 盘（5GB 左右，需一两分钟）..." -ForegroundColor Cyan
    Get-ChildItem $DefaultModels -Force | ForEach-Object { Move-Item $_.FullName -Destination $ModelsDir -Force }
    Remove-Item $DefaultModels -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "移动完成。" -ForegroundColor Green
} else {
    Write-Host "C 盘默认目录没有模型文件，跳过移动（若无模型可用，请重跑 install_ollama.bat）。" -ForegroundColor Yellow
}

# ---------- 4. 显式带上环境变量重启 Ollama（关键：子进程继承当前会话环境） ----------
$env:OLLAMA_MODELS = $ModelsDir
Start-Process -FilePath "$OllamaDir\ollama app.exe"
Start-Sleep -Seconds 6

# ---------- 5. 验证 ----------
Write-Host "当前模型列表：" -ForegroundColor Cyan
& "$OllamaDir\ollama.exe" list

Write-Host ""
Write-Host "===== 修复完成 =====" -ForegroundColor Green
Write-Host "如果上面列出了模型（如 qwen3:8b），说明已切到 D 盘。"
Write-Host "试用：D:\Ollama\ollama.exe run qwen3:8b"
Write-Host "此后新开的进程（含开机自启的 Ollama）都会使用 D 盘模型目录。"
