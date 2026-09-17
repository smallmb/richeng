# 中文说明：只停止本项目运行时记录的 API 与 Caddy 进程，不影响其他服务。
$ErrorActionPreference = 'SilentlyContinue'
$pidRoot = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'runtime'

foreach ($name in 'api', 'caddy') {
  $pidFile = Join-Path $pidRoot "$name.pid"
  if (Test-Path -LiteralPath $pidFile) {
    $processId = [int](Get-Content -LiteralPath $pidFile -Raw).Trim()
    Stop-Process -Id $processId -Force
    Remove-Item -LiteralPath $pidFile -Force
  }
}

Write-Output 'API and Caddy stopped.'
