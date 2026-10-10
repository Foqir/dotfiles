# YASB widget: is the VPN tunnel actually passing traffic?
# Checks the local proxy port, then fetches a tiny page through it (3 s timeout).
#   on     - proxy up and the internet reachable through it (ms = round trip)
#   down   - proxy port open, but nothing gets through (tunnel/server problem)
#   noproxy- proxy port closed or the system proxy is switched off (VPN client not running)
. "$PSScriptRoot\common.ps1"
# the shield icon is static in the YASB label (YASB does not format text inside <span>);
# problem states get a warning glyph in front of the text instead
$on = [char]0xf132; $off = [char]0xf071; $warn = "$off "
$proxy = Get-SystemProxy
if (-not $proxy) { Out-Widget @{ icon = $off; text = "${warn}VPN off"; state = 'noproxy'; tip = 'System proxy is disabled' }; exit }

$uri = [Uri]$proxy
$tcp = New-Object System.Net.Sockets.TcpClient
$open = $false
try { $open = $tcp.ConnectAsync($uri.Host, $uri.Port).Wait(800) -and $tcp.Connected } catch { } finally { $tcp.Close() }
if (-not $open) { Out-Widget @{ icon = $off; text = "${warn}VPN off"; state = 'noproxy'; tip = "Nothing listens on $($uri.Authority)" }; exit }

$sw = [Diagnostics.Stopwatch]::StartNew()
try {
    $req = [Net.HttpWebRequest]::Create('https://www.gstatic.com/generate_204')
    $req.Proxy = New-Object System.Net.WebProxy($proxy)
    $req.Timeout = 3000; $req.Method = 'GET'
    $resp = $req.GetResponse(); $resp.Close()
    Out-Widget @{ icon = $on; text = "VPN $($sw.ElapsedMilliseconds) ms"; state = 'on'; tip = "Through $($uri.Authority)" }
} catch {
    Out-Widget @{ icon = $off; text = "${warn}VPN down"; state = 'down'; tip = "Proxy $($uri.Authority) is up, but no traffic: $($_.Exception.InnerException.Message)" }
}
