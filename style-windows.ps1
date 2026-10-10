<#
  style-windows.ps1 — Windows в стиле Tokyo Night.

  Запуск (обычный PowerShell, НЕ от администратора):
      powershell -ExecutionPolicy Bypass -File .\style-windows.ps1

  Что делает: тёмная тема и прозрачность, акцент Tokyo Night на заголовках окон,
  панель задач — автоскрытие и без лишних кнопок, Проводник для разработчика,
  сгенерированные обои, конфиги YASB и GlazeWM из этого репозитория, их автозапуск и запуск.
  В конце перезапускается Проводник (открытые окна Проводника закроются).

  Ключи:
      -SkipWallpaper  не менять обои
      -NoStart        не запускать YASB и GlazeWM сейчас (автозапуск всё равно включится)
      -Undo           откатить реестр из последнего бэкапа и выключить автозапуск YASB/GlazeWM

  Бэкап реестра перед изменениями: %USERPROFILE%\.dotfiles-backup\<дата>\*.reg
#>
param([switch]$SkipWallpaper, [switch]$NoStart, [switch]$Undo)

$ErrorActionPreference = 'Continue'
$Here      = Split-Path -Parent $MyInvocation.MyCommand.Path
$Stamp     = Get-Date -Format 'yyyyMMdd-HHmmss'
$BackupDir = "$HOME\.dotfiles-backup"
$Yasbc     = "$env:ProgramFiles\YASB\yasbc.exe"
$YasbExe   = "$env:ProgramFiles\YASB\yasb.exe"
$GlazeExe  = "$env:ProgramFiles\glzr.io\GlazeWM\glazewm.exe"
$GlazeLnk  = Join-Path ([Environment]::GetFolderPath('Startup')) 'GlazeWM.lnk'

function Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "    [ok] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "    [!]  $m" -ForegroundColor Yellow }
function Dw([string]$hex) { [BitConverter]::ToInt32([BitConverter]::GetBytes([Convert]::ToUInt32($hex, 16)), 0) }
function SetReg($path, $name, $value, $type = 'DWord') {
    if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
    try { Set-ItemProperty -Path $path -Name $name -Value $value -Type $type -ErrorAction Stop }
    catch { Warn "$name : $($_.Exception.Message)" }
}
function Restart-Explorer {
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
    Start-Sleep -Seconds 2
}

$RegKeys = @(
    'HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize',
    'HKCU\Software\Microsoft\Windows\DWM',
    'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent',
    'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced',
    'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3',
    'HKCU\Software\Microsoft\Windows\CurrentVersion\Search',
    'HKCU\Control Panel\Desktop'
)

# ============================================================
# Откат
# ============================================================
if ($Undo) {
    $last = Get-ChildItem $BackupDir -Directory -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -Last 1
    if (-not $last) { Warn "бэкапов нет в $BackupDir"; exit 1 }
    Step "Откат реестра из $($last.FullName)"
    Get-ChildItem $last.FullName -Filter *.reg | ForEach-Object { reg import $_.FullName 2>$null; Ok $_.Name }
    Step 'Автозапуск YASB и GlazeWM'
    if (Test-Path $Yasbc) { & $Yasbc disable-autostart | Out-Null; Ok 'YASB: автозапуск выключен' }
    if (Test-Path $GlazeLnk) { Remove-Item $GlazeLnk; Ok 'GlazeWM: ярлык автозапуска удалён' }
    Get-Process glazewm, yasb -ErrorAction SilentlyContinue | Stop-Process -Force
    $wp = (Get-ItemProperty 'HKCU:\Control Panel\Desktop').WallPaper
    if (-not ('WinApi' -as [type])) {
        Add-Type -TypeDefinition 'using System.Runtime.InteropServices; public static class WinApi { [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern bool SystemParametersInfo(int a, int b, string c, int d); }'
    }
    [void][WinApi]::SystemParametersInfo(0x14, 0, $wp, 3)
    Restart-Explorer
    Ok 'готово. Конфиги в ~\.config\yasb и ~\.glzr\glazewm оставлены как есть.'
    exit 0
}

# ============================================================
# 0. Бэкап реестра
# ============================================================
Step 'Бэкап реестра'
$bk = Join-Path $BackupDir $Stamp
New-Item -ItemType Directory -Force $bk | Out-Null
foreach ($k in $RegKeys) {
    $file = Join-Path $bk (($k -split '\\')[-1] + '.reg')
    reg export $k $file /y 2>$null | Out-Null
}
Ok $bk

# ============================================================
# 1. Тёмная тема, прозрачность, акцентный цвет Tokyo Night
# ============================================================
Step 'Тёмная тема и акцент Tokyo Night'
$P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
SetReg $P AppsUseLightTheme   0
SetReg $P SystemUsesLightTheme 0
SetReg $P EnableTransparency  1
SetReg $P ColorPrevalence     1          # акцент на «Пуске» и панели задач
SetReg 'HKCU:\Control Panel\Desktop' AutoColorization 0 'String'   # не брать цвет из обоев

# палитра акцента: от светлого к тёмному, по 4 байта R G B 0
$palette = '#c0d4ff', '#a3bffc', '#8db0ff', '#7aa2f7', '#5a7ecf', '#3d59a1', '#283c6e', '#1a1b26'
$bytes = foreach ($c in $palette) { [Convert]::ToByte($c.Substring(1, 2), 16); [Convert]::ToByte($c.Substring(3, 2), 16); [Convert]::ToByte($c.Substring(5, 2), 16); 0 }
$A = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent'
SetReg $A AccentPalette ([byte[]]$bytes) 'Binary'
SetReg $A AccentColorMenu (Dw 'FFF7A27A')   # ABGR #7aa2f7
SetReg $A StartColorMenu  (Dw 'FFA1593D')   # ABGR #3d59a1

$D = 'HKCU:\Software\Microsoft\Windows\DWM'
SetReg $D AccentColor            (Dw 'FFA1593D')   # заголовки окон — приглушённый синий #3d59a1
SetReg $D ColorizationColor      (Dw 'C43D59A1')   # ARGB
SetReg $D ColorizationAfterglow  (Dw 'C43D59A1')
SetReg $D ColorPrevalence        1                 # акцент на заголовках и рамках окон
Ok 'тёмная тема, прозрачность, акцент #7aa2f7 / #3d59a1'

# ============================================================
# 2. Панель задач: автоскрытие (сверху будет YASB), без лишних кнопок
# ============================================================
Step 'Панель задач'
$X = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
SetReg $X ShowTaskViewButton 0
SetReg $X TaskbarDa 0          # виджеты (на новых сборках Windows может не дать — не страшно)
SetReg $X TaskbarMn 0          # чат
SetReg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' SearchboxTaskbarMode 0
$SR = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3'
$settings = (Get-ItemProperty $SR -ErrorAction SilentlyContinue).Settings
if ($settings) { $settings[8] = 3; SetReg $SR Settings ([byte[]]$settings) 'Binary'; Ok 'автоскрытие включено' }
else { Warn 'StuckRects3 не найден, автоскрытие включи вручную: Параметры -> Персонализация -> Панель задач' }

# ============================================================
# 3. Проводник для разработчика
# ============================================================
Step 'Проводник'
SetReg $X HideFileExt 0        # показывать расширения
SetReg $X Hidden      1        # показывать скрытые файлы (.git, .claude, .config)
SetReg $X LaunchTo    1        # открывать «Этот компьютер»
Ok 'расширения и скрытые файлы видны'

# ============================================================
# 4. Обои
# ============================================================
if (-not $SkipWallpaper) {
    Step 'Обои Tokyo Night'
    $vc = Get-CimInstance Win32_VideoController | Where-Object CurrentHorizontalResolution | Select-Object -First 1
    $w, $h = $vc.CurrentHorizontalResolution, $vc.CurrentVerticalResolution
    if (-not $w) { $w, $h = 1920, 1080 }
    $wpDir = Join-Path ([Environment]::GetFolderPath('MyPictures')) 'Wallpapers'
    New-Item -ItemType Directory -Force $wpDir | Out-Null
    $wp = Join-Path $wpDir 'tokyo-night-waves.png'
    python "$Here\wallpaper.py" $wp $w $h | Out-Null
    if ($LASTEXITCODE -eq 0 -and (Test-Path $wp)) {
        SetReg 'HKCU:\Control Panel\Desktop' WallpaperStyle '10' 'String'   # заполнение
        SetReg 'HKCU:\Control Panel\Desktop' TileWallpaper  '0'  'String'
        if (-not ('WinApi' -as [type])) {
            Add-Type -TypeDefinition 'using System.Runtime.InteropServices; public static class WinApi { [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern bool SystemParametersInfo(int a, int b, string c, int d); }'
        }
        [void][WinApi]::SystemParametersInfo(0x14, 0, $wp, 3)
        Ok "$wp ($w x $h)"
    } else { Warn 'обои не сгенерировались (нужны python, numpy, pillow)' }
}

# ============================================================
# 5. Конфиги YASB и GlazeWM из репозитория
# ============================================================
Step 'Конфиги YASB и GlazeWM'
$Copies = @(
    @("$Here\yasb\config.yaml",    "$HOME\.config\yasb\config.yaml"),
    @("$Here\yasb\styles.css",     "$HOME\.config\yasb\styles.css"),
    @("$Here\glazewm\config.yaml", "$HOME\.glzr\glazewm\config.yaml")
)
foreach ($c in $Copies) {
    $src, $dst = $c
    if (-not (Test-Path $src)) { Warn "нет $src"; continue }
    New-Item -ItemType Directory -Force (Split-Path $dst) | Out-Null
    if (Test-Path $dst) { Copy-Item $dst "$dst.bak-$Stamp" }
    Copy-Item $src $dst -Force
    Ok $dst
}

# ============================================================
# 6. Автозапуск
# ============================================================
Step 'Автозапуск'
if (Test-Path $Yasbc) { & $Yasbc enable-autostart | Out-Null; Ok 'YASB' } else { Warn 'YASB не установлен' }
if (Test-Path $GlazeExe) {
    $lnk = (New-Object -ComObject WScript.Shell).CreateShortcut($GlazeLnk)
    $lnk.TargetPath = $GlazeExe
    $lnk.Save()
    Ok "GlazeWM ($GlazeLnk)"
} else { Warn 'GlazeWM не установлен' }

# ============================================================
# 7. Применить: перезапуск Проводника, старт YASB и GlazeWM
# ============================================================
Step 'Перезапуск Проводника'
Restart-Explorer
Ok 'готово'

if (-not $NoStart) {
    Step 'Запуск YASB и GlazeWM'
    Get-Process glazewm, yasb -ErrorAction SilentlyContinue | Stop-Process -Force
    if (Test-Path $YasbExe)  { Start-Process $YasbExe;  Start-Sleep -Seconds 3; Ok 'YASB' }
    if (Test-Path $GlazeExe) { Start-Process $GlazeExe; Ok 'GlazeWM' }
}

Step 'Готово'
Write-Host @"
    GlazeWM — шпаргалка:
      Alt+1..9            рабочий стол 1..9          Alt+Shift+1..9   перенести окно туда
      Alt+стрелки / HJKL  фокус на соседнее окно     Alt+Shift+стрелки  двигать окно
      Alt+Enter           Windows Terminal           Alt+Shift+Q      закрыть окно
      Alt+F               во весь экран              Alt+Shift+Space  сделать окно плавающим
      Alt+V               сменить направление        Alt+R            режим ресайза (стрелки, Esc)
      Alt+Shift+P         пауза GlazeWM              Alt+Shift+E      выйти из GlazeWM
      Alt+Shift+R         перечитать конфиг
    Конфиги: ~\.config\yasb\ и ~\.glzr\glazewm\config.yaml (исходники — репозиторий dotfiles)
    Откат:   powershell -ExecutionPolicy Bypass -File .\style-windows.ps1 -Undo
    Часть настроек цвета Windows применяет полностью только после выхода из системы и входа.
"@ -ForegroundColor Gray
