<#
  setup-windows.ps1 — dev-окружение в стиле хакатона.

  Запуск (обычный PowerShell, НЕ от администратора, на отдельные установки winget сам попросит UAC):
      powershell -ExecutionPolicy Bypass -File .\setup-windows.ps1

  Повторный запуск безопасен: установленное пропускается, блоки в конфигах заменяются,
  перед каждой правкой конфига делается бэкап *.bak-<дата>.

  Ключи:
      -SkipApps     не ставить программы через winget
      -SkipVSCode   не трогать VS Code
#>
param([switch]$SkipApps, [switch]$SkipVSCode)

$ErrorActionPreference = 'Continue'   # Stop в 5.1 обрывал бы скрипт на любом выводе winget в stderr
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

function Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "    [ok] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "    [!]  $m" -ForegroundColor Yellow }
function Refresh-Path {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User')
}
function Backup($f) { if (Test-Path $f) { Copy-Item $f "$f.bak-$Stamp"; Ok "бэкап: $f.bak-$Stamp" } }

# ============================================================
# 1. Программы (winget)
# ============================================================
$Apps = [ordered]@{
    # база
    'Microsoft.WindowsTerminal'    = 'Windows Terminal'
    'Microsoft.PowerShell'         = 'PowerShell 7'
    'DEVCOM.JetBrainsMonoNerdFont' = 'шрифт JetBrainsMono Nerd Font'
    'Microsoft.PowerToys'          = 'PowerToys'
    'astral-sh.uv'                 = 'uv (Python-окружения)'
    'JohnMacFarlane.Pandoc'        = 'Pandoc (md -> docx)'
    'GitHub.cli'                   = 'GitHub CLI'
    'voidtools.Everything'         = 'Everything (поиск файлов)'
    'Anthropic.ClaudeCode'         = 'Claude Code CLI'
    # терминал
    'JanDeDobbeleer.OhMyPosh'      = 'Oh My Posh'
    'ajeetdsouza.zoxide'           = 'zoxide'
    'junegunn.fzf'                 = 'fzf'
    'Fastfetch-cli.Fastfetch'      = 'fastfetch'
    # хакатонный вид
    'glzr-io.glazewm'              = 'GlazeWM (плиточные окна)'
    'AmN.yasb'                     = 'YASB (верхняя панель)'
    'Flow-Launcher.Flow-Launcher'  = 'Flow Launcher'
}

if (-not $SkipApps) {
    Step 'Программы через winget'
    foreach ($id in $Apps.Keys) {
        winget list --id $id -e --accept-source-agreements --disable-interactivity *> $null
        if ($LASTEXITCODE -eq 0) { Ok "$($Apps[$id]) уже установлен"; continue }
        Write-Host "    ставлю $($Apps[$id])..."
        winget install --id $id -e --silent --accept-source-agreements --accept-package-agreements --disable-interactivity
        if ($LASTEXITCODE -eq 0) { Ok $Apps[$id] } else { Warn "$($Apps[$id]): winget вернул код $LASTEXITCODE" }
    }
    Refresh-Path

    Step 'Ruff (линтер Python) через uv'
    if (Get-Command uv -ErrorAction SilentlyContinue) {
        if (Get-Command ruff -ErrorAction SilentlyContinue) { Ok 'ruff уже есть' }
        else { uv tool install ruff; uv tool update-shell; Refresh-Path; Ok 'ruff' }
    } else { Warn 'uv не найден, ruff пропущен' }
}

# winget ставит PowerShell 7 либо как MSI (Program Files), либо как MSIX (ярлык в WindowsApps)
Refresh-Path
$Pwsh = @("$env:ProgramFiles\PowerShell\7\pwsh.exe",
          "$env:LOCALAPPDATA\Microsoft\WindowsApps\pwsh.exe",
          (Get-Command pwsh -ErrorAction SilentlyContinue).Source) |
        Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $Pwsh) {
    Warn 'PowerShell 7 не найден. Настройка профиля и терминала пропущена.'
    exit 1
}
Ok "PowerShell 7: $Pwsh"

# ============================================================
# 2. Модули PowerShell 7
# ============================================================
Step 'Модули PowerShell 7: Terminal-Icons, PSFzf'
& $Pwsh -NoProfile -Command {
    foreach ($m in 'Terminal-Icons', 'PSFzf') {
        if (Get-Module -ListAvailable $m) { "    [ok] $m уже есть"; continue }
        if (Get-Command Install-PSResource -ErrorAction SilentlyContinue) {
            Install-PSResource $m -Scope CurrentUser -TrustRepository -Quiet
        } else {
            Install-Module $m -Scope CurrentUser -Force -AllowClobber
        }
        "    [ok] $m"
    }
}

# ============================================================
# 3. Тема Oh My Posh + профиль PowerShell 7
# ============================================================
Step 'Тема Oh My Posh (tokyonight_storm)'
$OmpDir = "$HOME\.config\oh-my-posh"
New-Item -ItemType Directory -Force $OmpDir | Out-Null
try {
    Invoke-WebRequest -UseBasicParsing -ErrorAction Stop -OutFile "$OmpDir\tokyonight_storm.omp.json" `
        'https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/tokyonight_storm.omp.json'
    Ok "$OmpDir\tokyonight_storm.omp.json"
} catch { Warn "не скачалась тема: $($_.Exception.Message)" }

Step 'Профиль PowerShell 7'
$ProfilePath = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell\Microsoft.PowerShell_profile.ps1'
New-Item -ItemType Directory -Force (Split-Path $ProfilePath) | Out-Null
$Block = @'
# >>> dev-setup >>>
$OmpTheme = "$HOME\.config\oh-my-posh\tokyonight_storm.omp.json"
if ((Get-Command oh-my-posh -ErrorAction SilentlyContinue) -and (Test-Path $OmpTheme)) {
    oh-my-posh init pwsh --config $OmpTheme | Invoke-Expression
}
Import-Module Terminal-Icons -ErrorAction SilentlyContinue

# серые подсказки из истории, Tab — меню дополнения, стрелки — поиск по истории с введённым началом
Set-PSReadLineOption -PredictionSource History -PredictionViewStyle InlineView -HistorySearchCursorMovesToEnd
Set-PSReadLineKeyHandler -Key Tab       -Function MenuComplete
Set-PSReadLineKeyHandler -Key UpArrow   -Function HistorySearchBackward
Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward

# Ctrl+T — найти файл, Ctrl+R — найти команду в истории
if (Get-Command fzf -ErrorAction SilentlyContinue) {
    Import-Module PSFzf -ErrorAction SilentlyContinue
    Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r'
}
# z <часть имени папки> — прыжок в недавнюю папку
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    Invoke-Expression (& { (zoxide init powershell | Out-String) })
}

function ll    { Get-ChildItem -Force @args }
function which { param($name) (Get-Command $name).Source }
function labs  { Set-Location (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Foqir') }

if ($env:WT_SESSION -and (Get-Command fastfetch -ErrorAction SilentlyContinue)) { fastfetch }
# <<< dev-setup <<<
'@
$Old = if (Test-Path $ProfilePath) { Get-Content $ProfilePath -Raw -Encoding UTF8 } else { '' }
if ($null -eq $Old) { $Old = '' }
Backup $ProfilePath
$New = ([regex]::Replace($Old, '(?s)# >>> dev-setup >>>.*?# <<< dev-setup <<<\r?\n?', '')).TrimEnd()
$New = ($New + "`r`n`r`n" + $Block).TrimStart() + "`r`n"
Set-Content $ProfilePath $New -Encoding UTF8
Ok $ProfilePath

# ============================================================
# 4. Windows Terminal
#    PowerShell 7 по умолчанию, Tokyo Night, Nerd Font, акрил,
#    отдельный профиль «Hacker (CRT)» с зелёной схемой и эффектом старого монитора.
#    Win+` — выпадающий терминал (Quake mode, есть в WT по умолчанию).
# ============================================================
Step 'Windows Terminal'
$WtSettings = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
New-Item -ItemType Directory -Force (Split-Path $WtSettings) | Out-Null
Backup $WtSettings
& $Pwsh -NoProfile -Command {
    param($file)
    $s = if (Test-Path $file) { Get-Content $file -Raw | ConvertFrom-Json -AsHashtable } else { $null }
    if (-not $s) { $s = [ordered]@{ '$schema' = 'https://aka.ms/terminal-profiles-schema' } }
    if (-not $s.profiles)               { $s.profiles = [ordered]@{ list = @() } }
    elseif ($s.profiles -is [array])    { $s.profiles = [ordered]@{ list = $s.profiles } }
    if (-not $s.profiles.list)          { $s.profiles.list = @() }

    $font = [ordered]@{ face = 'JetBrainsMono Nerd Font'; size = 11 }
    $s.defaultProfile = '{574e775e-4f2a-5b96-ac1e-a2962a402336}'   # PowerShell 7
    $s.profiles.defaults = [ordered]@{
        font = $font; colorScheme = 'Tokyo Night'
        opacity = 88; useAcrylic = $true; padding = '10'; cursorShape = 'filledBox'
    }

    $hackerGuid = '{8b3f0c2e-7a41-4d6e-9c55-2f1e0a9b7d13}'
    $hacker = [ordered]@{
        guid = $hackerGuid; name = 'Hacker (CRT)'; commandline = 'pwsh.exe -NoLogo'
        colorScheme = 'Matrix'; font = $font; opacity = 100
        'experimental.retroTerminalEffect' = $true
    }
    $s.profiles.list = @(@($s.profiles.list | Where-Object { $_.guid -ne $hackerGuid }) + $hacker)

    $tokyo = [ordered]@{
        name = 'Tokyo Night'; background = '#1A1B26'; foreground = '#C0CAF5'
        cursorColor = '#C0CAF5'; selectionBackground = '#33467C'
        black = '#15161E'; red = '#F7768E'; green = '#9ECE6A'; yellow = '#E0AF68'
        blue = '#7AA2F7'; purple = '#BB9AF7'; cyan = '#7DCFFF'; white = '#A9B1D6'
        brightBlack = '#414868'; brightRed = '#F7768E'; brightGreen = '#9ECE6A'; brightYellow = '#E0AF68'
        brightBlue = '#7AA2F7'; brightPurple = '#BB9AF7'; brightCyan = '#7DCFFF'; brightWhite = '#C0CAF5'
    }
    $matrix = [ordered]@{
        name = 'Matrix'; background = '#0D0208'; foreground = '#00FF41'
        cursorColor = '#00FF41'; selectionBackground = '#003B00'
        black = '#0D0208'; red = '#FF3B3B'; green = '#00FF41'; yellow = '#C6FF00'
        blue = '#008F11'; purple = '#00B33C'; cyan = '#39FF88'; white = '#B8FFB8'
        brightBlack = '#1F3B1F'; brightRed = '#FF6B6B'; brightGreen = '#5CFF7A'; brightYellow = '#E1FF5C'
        brightBlue = '#22B33C'; brightPurple = '#33D96B'; brightCyan = '#7CFFB0'; brightWhite = '#E6FFE6'
    }
    $s.schemes = @(@($s.schemes | Where-Object { $_ -and $_.name -notin 'Tokyo Night', 'Matrix' }) + $tokyo + $matrix)

    $s | ConvertTo-Json -Depth 32 | Set-Content $file -Encoding utf8NoBOM
    "    [ok] $file"
} -args $WtSettings

# ============================================================
# 5. VS Code: тема, иконки, шрифт, расширения
#    formatOnSave НЕ включается: ruff format сломал бы выравнивание комментариев в lab*.py
# ============================================================
if (-not $SkipVSCode -and (Get-Command code -ErrorAction SilentlyContinue)) {
    Step 'Расширения VS Code'
    $have = @(code --list-extensions) | ForEach-Object { $_.ToLower() }
    foreach ($ext in 'enkia.tokyo-night', 'PKief.material-icon-theme', 'usernamehw.errorlens',
                     'eamodio.gitlens', 'ms-toolsai.jupyter', 'charliermarsh.ruff', 'Gruntfuggly.todo-tree') {
        if ($have -contains $ext.ToLower()) { Ok "$ext уже есть"; continue }
        code --install-extension $ext | Out-Null
        if ($LASTEXITCODE -eq 0) { Ok $ext } else { Warn "${ext}: код $LASTEXITCODE" }
    }

    Step 'Настройки VS Code'
    $VsSettings = "$env:APPDATA\Code\User\settings.json"
    Backup $VsSettings
    & $Pwsh -NoProfile -Command {
        param($file)
        try {
            $s = if (Test-Path $file) { Get-Content $file -Raw | ConvertFrom-Json -AsHashtable } else { $null }
            if (-not $s) { $s = [ordered]@{} }
            $s['workbench.colorTheme']                     = 'Tokyo Night'
            $s['workbench.iconTheme']                      = 'material-icon-theme'
            $s['editor.fontFamily']                        = "'JetBrainsMono Nerd Font', Consolas, monospace"
            $s['editor.fontLigatures']                     = $true
            $s['editor.cursorSmoothCaretAnimation']        = 'on'
            $s['editor.smoothScrolling']                   = $true
            $s['editor.guides.bracketPairs']               = 'active'
            $s['terminal.integrated.fontFamily']           = "'JetBrainsMono Nerd Font'"
            $s['terminal.integrated.defaultProfile.windows'] = 'PowerShell'
            $s['ruff.lint.select']                         = @('F', 'E4', 'E9')   # без E741: имена I, l в расчётах — норма
            $s | ConvertTo-Json -Depth 32 | Set-Content $file -Encoding utf8NoBOM
            "    [ok] $file"
        } catch { "    [!]  не удалось разобрать $file ($($_.Exception.Message)), настройки не изменены" }
    } -args $VsSettings
}

# ============================================================
Step 'Готово'
Write-Host @'
    Что дальше:
      1. Открой Windows Terminal (Win -> "Terminal"). Профиль "Hacker (CRT)" — в стрелке рядом с вкладками.
      2. Win+`             — выпадающий терминал
         Ctrl+R / Ctrl+T   — поиск по истории / по файлам
         z foqir, labs     — переход в папку с лабами
      3. gh auth login     — один раз, чтобы связать GitHub
      4. GlazeWM, YASB и Flow Launcher установлены, но не запущены — включай по желанию
         (GlazeWM: выход Alt+Shift+E). Если Alt+Space занят PowerToys, поменяй хоткей в одном из них.
      5. Перезапусти VS Code, чтобы подхватились шрифт и тема.
'@ -ForegroundColor Gray
