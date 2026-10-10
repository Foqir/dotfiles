# YASB widget: unread GitHub notifications through the gh CLI (uses gh's own stored login,
# so no token lives in the YASB config). gh ignores the Windows proxy settings -> pass it.
. "$PSScriptRoot\common.ps1"
$icon = [char]0xf09b
$gh = "$env:ProgramFiles\GitHub CLI\gh.exe"
if (-not (Test-Path $gh)) { Out-Widget @{ icon = $icon; text = 'n/a'; tip = 'gh is not installed' }; exit }
$proxy = Get-SystemProxy
if ($proxy) { $env:HTTPS_PROXY = $proxy }
$n = & $gh api notifications --jq 'length' 2>$null
if ($LASTEXITCODE -ne 0 -or -not $n) { Out-Widget @{ icon = $icon; text = '?'; tip = 'gh api failed (offline or not logged in: gh auth login)' }; exit }
$tip = if ([int]$n -eq 0) { 'No unread notifications' } else { "$n unread notifications" }
Out-Widget @{ icon = $icon; text = [string]$n; tip = $tip }
