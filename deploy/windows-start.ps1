$ErrorActionPreference = 'Stop'
$deployRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $deployRoot
$serverRoot = Join-Path $projectRoot 'server'
$envFile = Join-Path $deployRoot '.env'
$pidRoot = Join-Path $deployRoot 'runtime'
New-Item -ItemType Directory -Path $pidRoot -Force | Out-Null
# 中文说明：重启前仅停止本项目记录的进程，避免影响服务器其他服务
$stopScript = Join-Path $deployRoot 'windows-stop.ps1'
if (Test-Path -LiteralPath $stopScript) {
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $stopScript | Out-Null
}
if (-not (Test-Path -LiteralPath $envFile)) { throw 'Missing deploy .env file.' }
foreach ($line in Get-Content -LiteralPath $envFile) {
  $cleanLine = $line.Trim()
  if ($cleanLine -and $cleanLine[0] -ne '#') {
    $separator = $cleanLine.IndexOf('=')
    if ($separator -gt 0) {
      $key = $cleanLine.Substring(0, $separator).Trim()
      $value = $cleanLine.Substring($separator + 1).Trim()
      [Environment]::SetEnvironmentVariable($key, $value)
    }
  }
}
if (-not $env:RICHENG_ORIGIN -and $env:APP_DOMAIN) { $env:RICHENG_ORIGIN = "https://$($env:APP_DOMAIN)" }
$python = (Get-Command python -ErrorAction Stop).Source
# 中文说明：每次启动先确保实时同步依赖可用，避免首次启动因导入失败而中止。
& $python -m pip install --disable-pip-version-check -r (Join-Path $serverRoot 'requirements.txt')
if ($LASTEXITCODE -ne 0) { throw 'WebSocket dependency installation failed.' }
$caddyCommand = Get-Command caddy -ErrorAction SilentlyContinue
if ($caddyCommand) {
  $caddy = $caddyCommand.Source
} else {
  # 中文说明：支持把 caddy.exe 直接放在 deploy 目录
  $localCaddy = Join-Path $deployRoot 'caddy.exe'
  if (-not (Test-Path -LiteralPath $localCaddy)) { throw 'Caddy not found. Put caddy.exe in deploy folder or add it to PATH.' }
  $caddy = $localCaddy
}
$api = Start-Process -FilePath $python -ArgumentList 'server.py' -WorkingDirectory $serverRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $pidRoot 'api.log') -RedirectStandardError (Join-Path $pidRoot 'api-error.log')
$api.Id | Set-Content -LiteralPath (Join-Path $pidRoot 'api.pid')
$proxy = Start-Process -FilePath $caddy -ArgumentList 'run','--config',(Join-Path $deployRoot 'Caddyfile.windows') -WorkingDirectory $deployRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $pidRoot 'caddy.log') -RedirectStandardError (Join-Path $pidRoot 'caddy-error.log')
$proxy.Id | Set-Content -LiteralPath (Join-Path $pidRoot 'caddy.pid')
Write-Output "API started PID=$($api.Id); Caddy started PID=$($proxy.Id)"





