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
      -Undo           вернуть Windows к состоянию ДО первого запуска скрипта

  Откат. При первом запуске скрипт запоминает исходное состояние в
  %USERPROFILE%\.dotfiles-backup\original\:
      registry.json   каждое значение реестра, которое скрипт меняет: было ли оно и каким было
      *.reg           полный экспорт затронутых веток (на всякий случай, для ручного восстановления)
      files\          исходные конфиги YASB и GlazeWM, если они были
  Повторные запуски этот снимок НЕ перезаписывают, поэтому -Undo всегда возвращает исходный вид,
  сколько бы раз скрипт ни запускался. Значения, которых до скрипта не было, при откате удаляются.
  После отката снимок переименовывается в original-undone-<дата>, следующий запуск снимет новый.
#>
param([switch]$SkipWallpaper, [switch]$NoStart, [switch]$Undo)

$ErrorActionPreference = 'Continue'
$Here      = Split-Path -Parent $MyInvocation.MyCommand.Path
$Stamp     = Get-Date -Format 'yyyyMMdd-HHmmss'
$BackupDir = "$HOME\.dotfiles-backup"
$Original  = Join-Path $BackupDir 'original'
$Snapshot  = Join-Path $Original 'registry.json'
$Yasbc     = "$env:ProgramFiles\YASB\yasbc.exe"
$YasbExe   = "$env:ProgramFiles\YASB\yasb.exe"
$GlazeExe  = "$env:ProgramFiles\glzr.io\GlazeWM\glazewm.exe"
$GlazeLnk  = Join-Path ([Environment]::GetFolderPath('Startup')) 'GlazeWM.lnk'

function Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "    [ok] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "    [!]  $m" -ForegroundColor Yellow }
function Dw([string]$hex) { [BitConverter]::ToInt32([BitConverter]::GetBytes([Convert]::ToUInt32($hex, 16)), 0) }
function Restart-Explorer {
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
    Start-Sleep -Seconds 2
}
function Set-Wallpaper([string]$path) {
    if (-not ('WinApi' -as [type])) {
        Add-Type -TypeDefinition 'using System.Runtime.InteropServices; public static class WinApi { [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern bool SystemParametersInfo(int a, int b, string c, int d); }'
    }
    [void][WinApi]::SystemParametersInfo(0x14, 0, $path, 3)   # SPI_SETDESKWALLPAPER, сохранить и разослать
}
function Saved-ConfigPath($dst) { Join-Path $Original ('files\' + ($dst.Substring($HOME.Length + 1) -replace '[\\/]', '__')) }

# ============================================================
# Реестр: чтение и запись отдельных значений
# ============================================================
function Get-RegValue($path, $name) {
    # @{ Existed; Kind; Value } — Kind в терминах RegistryValueKind (DWord, String, Binary, ...)
    $key = Get-Item -Path $path -ErrorAction SilentlyContinue
    if (-not $key -or $key.GetValueNames() -notcontains $name) { return @{ Existed = $false; Kind = $null; Value = $null } }
    $kind  = $key.GetValueKind($name).ToString()
    $value = $key.GetValue($name, $null, 'DoNotExpandEnvironmentNames')
    if ($kind -eq 'Binary') { $value = [Convert]::ToBase64String([byte[]]$value) }
    return @{ Existed = $true; Kind = $kind; Value = $value }
}

function Set-RegValue($path, $name, $value, $kind) {
    if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
    try { Set-ItemProperty -Path $path -Name $name -Value $value -Type $kind -ErrorAction Stop }
    catch { Warn "$name : $($_.Exception.Message)" }
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
$ConfigCopies = @(
    @("$Here\yasb\config.yaml",    "$HOME\.config\yasb\config.yaml"),
    @("$Here\yasb\styles.css",     "$HOME\.config\yasb\styles.css"),
    @("$Here\glazewm\config.yaml", "$HOME\.glzr\glazewm\config.yaml")
)

# ============================================================
# Откат
# ============================================================
if ($Undo) {
    if (-not (Test-Path $Snapshot)) {
        Warn "нет снимка исходного состояния ($Snapshot): скрипт ещё не запускался или откат уже сделан"
        exit 1
    }
    Step 'Откат реестра к состоянию до первого запуска'
    # PowerShell 5.1: ConvertFrom-Json отдаёт JSON-массив одним объектом, и @(... | ConvertFrom-Json)
    # дал бы массив из одного элемента. Поэтому сначала в переменную, потом @().
    $items = Get-Content $Snapshot -Raw -Encoding UTF8 | ConvertFrom-Json
    $items = @($items)
    foreach ($it in $items) {
        if ($it.Existed) {
            $v = if ($it.Kind -eq 'Binary') { [Convert]::FromBase64String($it.Value) } else { $it.Value }
            Set-RegValue $it.Path $it.Name $v $it.Kind
        } else {
            Remove-ItemProperty -Path $it.Path -Name $it.Name -ErrorAction SilentlyContinue
        }
    }
    Ok "восстановлено значений: $($items.Count)"

    Step 'Конфиги YASB и GlazeWM'
    foreach ($c in $ConfigCopies) {
        $dst = $c[1]; $saved = Saved-ConfigPath $dst
        if (Test-Path $saved) { Copy-Item $saved $dst -Force; Ok "возвращён исходный $dst" }
        elseif (Test-Path $dst) { Ok "$dst оставлен (до скрипта его не было, программа выключена)" }
    }

    Step 'Автозапуск YASB и GlazeWM'
    if (Test-Path $Yasbc) { & $Yasbc disable-autostart | Out-Null; Ok 'YASB: автозапуск выключен' }
    if (Test-Path $GlazeLnk) { Remove-Item $GlazeLnk; Ok 'GlazeWM: ярлык автозапуска удалён' }
    Get-Process glazewm, yasb -ErrorAction SilentlyContinue | Stop-Process -Force

    $wp = (Get-ItemProperty 'HKCU:\Control Panel\Desktop').WallPaper
    if ($wp) { Set-Wallpaper $wp }
    Restart-Explorer

    $done = Join-Path $BackupDir "original-undone-$Stamp"
    Rename-Item $Original $done
    Ok "готово. Снимок перенесён в $done; часть цветов Windows вернётся полностью после выхода и входа."
    exit 0
}

# ============================================================
# 0. Что меняем: сначала список, потом снимок, потом запись
# ============================================================
$P  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
$A  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent'
$D  = 'HKCU:\Software\Microsoft\Windows\DWM'
$X  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
$S  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'
$SR = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3'
$CD = 'HKCU:\Control Panel\Desktop'

# палитра акцента: от светлого к тёмному, по 4 байта R G B 0
$palette = '#c0d4ff', '#a3bffc', '#8db0ff', '#7aa2f7', '#5a7ecf', '#3d59a1', '#283c6e', '#1a1b26'
$paletteBytes = [byte[]]@(foreach ($c in $palette) {
    [Convert]::ToByte($c.Substring(1, 2), 16); [Convert]::ToByte($c.Substring(3, 2), 16)
    [Convert]::ToByte($c.Substring(5, 2), 16); 0 })

$Changes = New-Object System.Collections.ArrayList
function Plan($path, $name, $value, $kind = 'DWord') { [void]$Changes.Add(@{ Path = $path; Name = $name; Value = $value; Kind = $kind }) }

# 1. тёмная тема, прозрачность, акцент Tokyo Night
Plan $P  AppsUseLightTheme     0
Plan $P  SystemUsesLightTheme  0
Plan $P  EnableTransparency    1
Plan $P  ColorPrevalence       1                         # акцент на «Пуске» и панели задач
Plan $CD AutoColorization      '0' 'String'              # не брать цвет из обоев
Plan $A  AccentPalette         $paletteBytes 'Binary'
Plan $A  AccentColorMenu       (Dw 'FFF7A27A')           # ABGR #7aa2f7
Plan $A  StartColorMenu        (Dw 'FFA1593D')           # ABGR #3d59a1
Plan $D  AccentColor           (Dw 'FFA1593D')           # заголовки окон — приглушённый синий #3d59a1
Plan $D  ColorizationColor     (Dw 'C43D59A1')           # ARGB
Plan $D  ColorizationAfterglow (Dw 'C43D59A1')
Plan $D  ColorPrevalence       1                         # акцент на заголовках и рамках окон
# 2. панель задач: автоскрытие (сверху будет YASB), без лишних кнопок
Plan $X  ShowTaskViewButton    0
Plan $X  TaskbarDa             0                         # виджеты (новые сборки могут не дать — не страшно)
Plan $X  TaskbarMn             0                         # чат
Plan $S  SearchboxTaskbarMode  0
$stuck = (Get-ItemProperty $SR -ErrorAction SilentlyContinue).Settings
if ($stuck) { $stuck = [byte[]]$stuck.Clone(); $stuck[8] = 3; Plan $SR Settings $stuck 'Binary' }
# 3. Проводник для разработчика
Plan $X  HideFileExt           0                         # показывать расширения
Plan $X  Hidden                1                         # показывать скрытые файлы (.git, .claude, .config)
Plan $X  LaunchTo              1                         # открывать «Этот компьютер»
# 4. обои: само значение WallPaper пишет SystemParametersInfo, в снимок его берём отдельно
if (-not $SkipWallpaper) {
    Plan $CD WallpaperStyle '10' 'String'                # заполнение
    Plan $CD TileWallpaper  '0'  'String'
}

# ============================================================
# 1. Снимок исходного состояния — только при первом запуске
# ============================================================
Step 'Снимок исходного состояния'
if (Test-Path $Snapshot) {
    Ok "уже есть с первого запуска: $Original (не перезаписываю)"
} else {
    New-Item -ItemType Directory -Force (Join-Path $Original 'files') | Out-Null
    # все значения, которые скрипт может тронуть при любых ключах, плюс сам путь к обоям
    $names = @($Changes | ForEach-Object { "$($_.Path)|$($_.Name)" }) +
             "$CD|WallpaperStyle", "$CD|TileWallpaper", "$CD|WallPaper"
    $items = @(foreach ($n in ($names | Select-Object -Unique)) {
        $path, $name = $n -split '\|', 2
        $cur = Get-RegValue $path $name
        [ordered]@{ Path = $path; Name = $name; Existed = $cur.Existed; Kind = $cur.Kind; Value = $cur.Value }
    })
    ConvertTo-Json -InputObject $items -Depth 4 | Set-Content $Snapshot -Encoding UTF8
    foreach ($k in $RegKeys) { reg export $k (Join-Path $Original (($k -split '\\')[-1] + '.reg')) /y 2>$null | Out-Null }
    foreach ($c in $ConfigCopies) { $dst = $c[1]; if (Test-Path $dst) { Copy-Item $dst (Saved-ConfigPath $dst) } }
    Ok "$Original (значений: $($items.Count))"
}

# ============================================================
# 2. Запись в реестр
# ============================================================
Step 'Тема, акцент Tokyo Night, панель задач, Проводник'
foreach ($c in $Changes) { Set-RegValue $c.Path $c.Name $c.Value $c.Kind }
if (-not $stuck) { Warn 'StuckRects3 не найден, автоскрытие включи вручную: Параметры -> Персонализация -> Панель задач' }
Ok "записано значений: $($Changes.Count)"

# ============================================================
# 3. Обои
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
    if ($LASTEXITCODE -eq 0 -and (Test-Path $wp)) { Set-Wallpaper $wp; Ok "$wp ($w x $h)" }
    else { Warn 'обои не сгенерировались (нужны python, numpy, pillow)' }
}

# ============================================================
# 4. Конфиги YASB и GlazeWM из репозитория
# ============================================================
Step 'Конфиги YASB и GlazeWM'
foreach ($c in $ConfigCopies) {
    $src, $dst = $c
    if (-not (Test-Path $src)) { Warn "нет $src"; continue }
    New-Item -ItemType Directory -Force (Split-Path $dst) | Out-Null
    if (Test-Path $dst) { Copy-Item $dst "$dst.bak-$Stamp" }
    Copy-Item $src $dst -Force
    Ok $dst
}

# ============================================================
# 5. Автозапуск
# ============================================================
Step 'Автозапуск'
if (Test-Path $Yasbc) { & $Yasbc enable-autostart | Out-Null; Ok 'YASB' } else { Warn 'YASB не установлен (сначала setup-windows.ps1)' }
if (Test-Path $GlazeExe) {
    $lnk = (New-Object -ComObject WScript.Shell).CreateShortcut($GlazeLnk)
    $lnk.TargetPath = $GlazeExe
    $lnk.Save()
    Ok "GlazeWM ($GlazeLnk)"
} else { Warn 'GlazeWM не установлен (сначала setup-windows.ps1)' }

# ============================================================
# 6. Применить: перезапуск Проводника, старт YASB и GlazeWM
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

# ============================================================
# 7. Проверка: не мешает ли переключение раскладки сочетаниям GlazeWM
# ============================================================
# 'Language Hotkey': 1 = Alt+Shift (по умолчанию, если значения нет), 2 = Ctrl+Shift, 3 = выключено, 4 = Ё
$toggle = Get-ItemProperty 'HKCU:\Keyboard Layout\Toggle' -ErrorAction SilentlyContinue
$langHotkey = '1'
if ($toggle -and $toggle.'Language Hotkey') { $langHotkey = [string]$toggle.'Language Hotkey' }
elseif ($toggle -and $toggle.Hotkey)        { $langHotkey = [string]$toggle.Hotkey }
if ($langHotkey -eq '1') {
    Step 'Раскладка'
    Warn 'язык ввода переключается по Alt+Shift, а у GlazeWM много сочетаний Alt+Shift+<клавиша>.'
    Warn 'Если раскладка начнёт сбиваться, переключай язык по Win+Пробел или смени сочетание:'
    Warn 'Параметры -> Время и язык -> Ввод -> Дополнительные параметры клавиатуры -> Сочетания клавиш для языков ввода.'
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
    Окна WSLg (Gazebo, RViz из Docker) GlazeWM не трогает: правило для msrdc в glazewm\config.yaml.
    Конфиги: ~\.config\yasb\ и ~\.glzr\glazewm\config.yaml (исходники — репозиторий dotfiles)
    Откат к исходному виду: powershell -ExecutionPolicy Bypass -File .\style-windows.ps1 -Undo
    Часть настроек цвета Windows применяет полностью только после выхода из системы и входа.
"@ -ForegroundColor Gray
