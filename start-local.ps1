# 启动当前项目的本地服务和 Windows 客户端，不修改系统设置。
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
$appPath = Join-Path $PSScriptRoot 'build\windows\x64\runner\Release\richeng.exe'
if (-not (Test-Path -LiteralPath $appPath)) { throw '请先运行 tool\build-windows.ps1。' }
try {
    $health = Invoke-RestMethod -Uri 'http://127.0.0.1:5318/health' -TimeoutSec 2
    if ($health.status -ne 'ok') { throw '端口已被其他服务占用。' }
} catch {
    $serviceProcess = Start-Process -FilePath 'python' -ArgumentList @('-u', 'server/server.py') -WorkingDirectory $PSScriptRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput 'server/service.log' -RedirectStandardError 'server/service-error.log'
    Set-Content -LiteralPath 'server/service.pid' -Value $serviceProcess.Id
}
# 用户执行启动脚本时打开交互式客户端。
Start-Process -FilePath $appPath
