# Shared helpers for the YASB custom widgets (dot-sourced by the other scripts).
# Output is one line of ASCII JSON: icons are \u escapes, so the console code page of
# Windows PowerShell 5.1 cannot garble them; YASB parses it with return_format: json.

function Get-SystemProxy {
    # The VPN client (e.g. Happ) publishes an HTTP proxy in the Windows proxy settings.
    # Go tools such as gh ignore those settings, so the widgets pass the proxy explicitly.
    $ie = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
    if ($ie -and $ie.ProxyEnable -eq 1 -and $ie.ProxyServer) {
        $p = ($ie.ProxyServer -split ';')[0] -replace '^\w+=', ''
        if ($p -notmatch '^\w+://') { $p = "http://$p" }
        return $p
    }
    return $null
}

function Out-Widget([hashtable]$data) {
    $parts = foreach ($k in $data.Keys) {
        $v = [string]$data[$k]
        $sb = New-Object System.Text.StringBuilder
        foreach ($ch in $v.ToCharArray()) {
            $code = [int]$ch
            if ($ch -eq '"' -or $ch -eq '\') { [void]$sb.Append('\').Append($ch) }
            elseif ($code -lt 32 -or $code -gt 126) { [void]$sb.AppendFormat('\u{0:x4}', $code) }
            else { [void]$sb.Append($ch) }
        }
        '"{0}":"{1}"' -f $k, $sb.ToString()
    }
    [Console]::Out.WriteLine('{' + ($parts -join ',') + '}')
}
