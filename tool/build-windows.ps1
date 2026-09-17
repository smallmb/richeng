# 使用本机 Flutter 构建；目录联接兼容未启用开发者模式的 Windows。
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath (Split-Path -Parent $PSScriptRoot)
$flutterTool = 'D:\Apps\flutter\bin\flutter.bat'
& $flutterTool pub get
if ($LASTEXITCODE -ne 0) { throw '依赖解析失败，请检查上方输出。' }
$pluginData = Get-Content -Raw -LiteralPath '.flutter-plugins-dependencies' | ConvertFrom-Json
foreach ($plugin in $pluginData.plugins.windows) {
    $linkPath = Join-Path (Get-Location) ('windows\flutter\ephemeral\.plugin_symlinks\' + $plugin.name)
    if (-not (Test-Path -LiteralPath $linkPath)) {
        New-Item -ItemType Junction -Path $linkPath -Target $plugin.path | Out-Null
    }
}
& $flutterTool build windows --no-pub
if ($LASTEXITCODE -ne 0) { throw 'Windows 构建失败，请检查上方输出。' }
