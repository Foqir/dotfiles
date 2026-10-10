# YASB widget: running Docker containers (simulations) or "off" when Docker Desktop is stopped.
. "$PSScriptRoot\common.ps1"
$icon = [char]0xf308
$docker = "$env:ProgramFiles\Docker\Docker\resources\bin\docker.exe"
if (-not (Test-Path $docker)) { Out-Widget @{ icon = $icon; text = 'n/a'; names = 'Docker is not installed' }; exit }
$names = & $docker ps --format '{{.Names}}' 2>$null
if ($LASTEXITCODE -ne 0) { Out-Widget @{ icon = $icon; text = 'off'; names = 'Docker Desktop is not running' }; exit }
$names = @($names | Where-Object { $_ })
$list = if ($names.Count) { $names -join ', ' } else { 'no running containers' }
Out-Widget @{ icon = $icon; text = [string]$names.Count; names = $list }
