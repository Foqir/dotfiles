<#
  style-windows.ps1 — Windows в стиле Tokyo Night.

  Запуск (обычный PowerShell, НЕ от администратора):
      powershell -ExecutionPolicy Bypass -File .\style-windows.ps1

  Что делает: тёмная тема и прозрачность, акцент Tokyo Night на заголовках окон,
  панель задач — автоскрытие и без лишних кнопок, Проводник для разработчика,
  сгенерированные обои, курсор Bibata Modern Ice, конфиги и виджеты YASB, конфиг GlazeWM,
  их автозапуск и запуск. В конце перезапускается Проводник (открытые окна Проводника закроются).

  Ключи:
      -SkipWallpaper  не менять обои
      -SkipCursor     не ставить курсор
      -CursorSize     Regular (по умолчанию), Large или ExtraLarge
      -NoStart        не запускать YASB и GlazeWM сейчас (автозапуск всё равно включится)
      -Undo           вернуть Windows к состоянию ДО первого запуска скрипта

  Откат. При первом запуске скрипт запоминает исходное состояние в
  %USERPROFILE%\.dotfiles-backup\original\:
      registry.json   каждое значение реестра, которое скрипт меняет: было ли оно и каким было
      *.reg           полный экспорт затронутых веток (на всякий случай, для ручного восстановления)
      files\          исходные конфиги YASB и GlazeWM, если они были
  Повторные запуски уже записанное в снимке НЕ перезаписывают, поэтому -Undo всегда возвращает
  исходный вид, сколько бы раз скрипт ни запускался. Если новая версия скрипта меняет значения,
  которых в снимке ещё нет (например, курсор), они дописываются в снимок до изменения.
  Значения, которых до скрипта не было, при откате удаляются.
  После отката снимок переименовывается в original-undone-<дата>, следующий запуск снимет новый.
#>
param([switch]$SkipWallpaper, [switch]$SkipCursor, [ValidateSet('Regular', 'Large', 'ExtraLarge')][string]$CursorSize = 'Regular',
      [switch]$NoStart, [switch]$Undo)

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
$YasbLnk   = Join-Path ([Environment]::GetFolderPath('Startup')) 'YASB.lnk'   # yasbc enable-autostart молча ничего не создавал

# Курсор Bibata Modern Ice (GPL-3.0, github.com/ful1e5/Bibata_Cursor): закреплённый релиз + SHA256.
# Ставится только для текущего пользователя: файлы в %LOCALAPPDATA%\Cursors, схема в HKCU, без прав админа.
$CursorScheme = 'Bibata-Modern-Ice'
$CursorUrl    = 'https://github.com/ful1e5/Bibata_Cursor/releases/download/v2.0.7/Bibata-Modern-Ice-Windows.zip'
$CursorSha256 = '0045E40324DA5B540B3BEE260F53D0792DF62BE9CDEF91655A024AE9F151BD04'
$CursorDir    = "$env:LOCALAPPDATA\Cursors\$CursorScheme"
$CursorDirReg = "%LOCALAPPDATA%\Cursors\$CursorScheme"          # REG_EXPAND_SZ, как у системных схем
$CursorKey    = 'HKCU:\Control Panel\Cursors'
# 17 стандартных ролей Windows в порядке строки схемы -> файл Bibata
$CursorRoles  = [ordered]@{
    Arrow = 'Pointer.cur'; Help = 'Help.cur'; AppStarting = 'Work.ani'; Wait = 'Busy.ani'
    Crosshair = 'Cross.cur'; IBeam = 'Text.cur'; NWPen = 'Handwriting.cur'; No = 'Unavailable.cur'
    SizeNS = 'Vert.cur'; SizeWE = 'Horz.cur'; SizeNWSE = 'Dgn1.cur'; SizeNESW = 'Dgn2.cur'
    SizeAll = 'Move.cur'; UpArrow = 'Alternate.cur'; Hand = 'Link.cur'; Pin = 'Pin.cur'; Person = 'Person.cur'
}

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
function Set-TaskbarAutoHide([bool]$on) {
    # Windows 11 25H2 не подхватывает автоскрытие из StuckRects3 при перезапуске Проводника,
    # поэтому включаем его тем же вызовом, что и переключатель в «Параметрах» (ABM_SETSTATE).
    if (-not ('AppBarApi' -as [type])) {
        Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class AppBarApi {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int l, t, r, b; }
    [StructLayout(LayoutKind.Sequential)] public struct APPBARDATA { public int cbSize; public IntPtr hWnd; public uint uCallbackMessage; public uint uEdge; public RECT rc; public IntPtr lParam; }
    [DllImport("shell32.dll")] static extern UIntPtr SHAppBarMessage(uint msg, ref APPBARDATA data);
    [DllImport("user32.dll")] public static extern IntPtr FindWindow(string cls, string title);
    public static int GetState() { var d = new APPBARDATA(); d.cbSize = Marshal.SizeOf(d); return (int)SHAppBarMessage(4, ref d); }
    public static void SetState(int s) { var d = new APPBARDATA(); d.cbSize = Marshal.SizeOf(d); d.hWnd = FindWindow("Shell_TrayWnd", null); d.lParam = (IntPtr)s; SHAppBarMessage(10, ref d); }
}
'@
    }
    for ($i = 0; $i -lt 20 -and [AppBarApi]::FindWindow('Shell_TrayWnd', $null) -eq [IntPtr]::Zero; $i++) { Start-Sleep -Milliseconds 500 }
    [AppBarApi]::SetState($(if ($on) { 1 } else { 0 }))   # ABS_AUTOHIDE = 1
    Start-Sleep -Milliseconds 500
    return [bool]([AppBarApi]::GetState() -band 1) -eq $on
}
function Update-Cursors {
    if (-not ('WinApi' -as [type])) {
        Add-Type -TypeDefinition 'using System.Runtime.InteropServices; public static class WinApi { [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern bool SystemParametersInfo(int a, int b, string c, int d); }'
    }
    [void][WinApi]::SystemParametersInfo(0x57, 0, $null, 3)   # SPI_SETCURSORS: перечитать схему из реестра
}
function Install-CursorFiles {
    # Скачивает закреплённый релиз, проверяет SHA256 и копирует нужный размер в $CursorDir.
    $marker = Join-Path $CursorDir '.size'
    if ((Test-Path "$CursorDir\Pointer.cur") -and (Test-Path $marker) -and ((Get-Content $marker) -eq $CursorSize)) { return $true }
    $folder = @{ Regular = 'Regular'; Large = 'Large'; ExtraLarge = 'Extra-Large' }[$CursorSize]
    $zip = Join-Path $env:TEMP "$CursorScheme-$Stamp.zip"
    $tmp = Join-Path $env:TEMP "$CursorScheme-$Stamp"
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -UseBasicParsing -Uri $CursorUrl -OutFile $zip -ErrorAction Stop
        $hash = (Get-FileHash $zip -Algorithm SHA256).Hash
        if ($hash -ne $CursorSha256) { Warn "SHA256 архива курсора не совпал ($hash), курсор не ставлю"; return $false }
        Expand-Archive $zip $tmp -Force
        $src = Join-Path $tmp "$CursorScheme-$folder-Windows"
        New-Item -ItemType Directory -Force $CursorDir | Out-Null
        Copy-Item "$src\*.cur", "$src\*.ani" $CursorDir -Force
        Set-Content $marker $CursorSize
        return (Test-Path "$CursorDir\Pointer.cur")
    } catch {
        Warn "курсор не скачался: $($_.Exception.Message)"
        return $false
    } finally {
        Remove-Item $zip -Force -ErrorAction SilentlyContinue
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
function Saved-ConfigPath($dst) { Join-Path $Original ('files\' + ($dst.Substring($HOME.Length + 1) -replace '[\\/]', '__')) }

# ============================================================
# Реестр: чтение и запись отдельных значений
# ============================================================
function Get-RegValue($path, $name) {
    # @{ Existed; Kind; Value } — Kind в терминах RegistryValueKind (DWord, String, Binary, ...)
    # '(default)' — так PowerShell называет безымянное значение ключа; в API реестра это ''.
    $raw = if ($name -eq '(default)') { '' } else { $name }
    $key = Get-Item -Path $path -ErrorAction SilentlyContinue
    if (-not $key -or $key.GetValueNames() -notcontains $raw) { return @{ Existed = $false; Kind = $null; Value = $null } }
    $kind  = $key.GetValueKind($raw).ToString()
    $value = $key.GetValue($raw, $null, 'DoNotExpandEnvironmentNames')
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
    'HKCU\Control Panel\Desktop',
    'HKCU\Control Panel\Cursors'
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
    Update-Cursors
    if (Test-Path $CursorDir) { Remove-Item $CursorDir -Recurse -Force -ErrorAction SilentlyContinue; Ok "курсор: исходная схема, $CursorDir удалён" }

    Step 'Конфиги YASB и GlazeWM'
    foreach ($c in $ConfigCopies) {
        $dst = $c[1]; $saved = Saved-ConfigPath $dst
        if (Test-Path $saved) { Copy-Item $saved $dst -Force; Ok "возвращён исходный $dst" }
        elseif (Test-Path $dst) { Ok "$dst оставлен (до скрипта его не было, программа выключена)" }
    }

    Step 'Автозапуск YASB и GlazeWM'
    if (Test-Path $YasbLnk) { Remove-Item $YasbLnk; Ok 'YASB: ярлык автозапуска удалён' }
    if (Test-Path $Yasbc) { & $Yasbc disable-autostart | Out-Null }
    if (Test-Path $GlazeLnk) { Remove-Item $GlazeLnk; Ok 'GlazeWM: ярлык автозапуска удалён' }
    Get-Process yasb -ErrorAction SilentlyContinue | Stop-Process -Force
    if ((Get-Process glazewm -ErrorAction SilentlyContinue) -and (Test-Path $GlazeExe)) {
        Start-Process $GlazeExe -ArgumentList 'command', 'wm-exit' -WindowStyle Hidden -Wait   # uiAccess: см. запуск ниже
    }

    $wp = (Get-ItemProperty 'HKCU:\Control Panel\Desktop').WallPaper
    if ($wp) { Set-Wallpaper $wp }
    Restart-Explorer
    # автоскрытие панели задач — как было до скрипта (байт 8 исходного StuckRects3: 3 = скрывать)
    $sr = $items | Where-Object { $_.Name -eq 'Settings' -and $_.Path -like '*StuckRects3' -and $_.Existed } | Select-Object -First 1
    if ($sr) {
        $wasHidden = ([Convert]::FromBase64String($sr.Value))[8] -eq 3
        [void](Set-TaskbarAutoHide $wasHidden)
        Ok "панель задач: автоскрытие $(if ($wasHidden) { 'включено' } else { 'выключено' }), как было"
    }

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
# 5. курсор: файлы ставим до снимка и записи — если не скачался, схему не трогаем вовсе
$cursorReady = $false
if (-not $SkipCursor) {
    Step "Курсор $CursorScheme ($CursorSize)"
    $cursorReady = Install-CursorFiles
    if ($cursorReady) {
        $schemeParts = foreach ($role in $CursorRoles.Keys) {
            Plan $CursorKey $role "$CursorDirReg\$($CursorRoles[$role])" 'ExpandString'
            "$CursorDirReg\$($CursorRoles[$role])"
        }
        Plan $CursorKey '(default)'     $CursorScheme 'String'          # имя активной схемы
        Plan $CursorKey 'Scheme Source' 1                                # 1 = пользовательская схема
        Plan "$CursorKey\Schemes" $CursorScheme ($schemeParts -join ',') 'ExpandString'   # видна в «Свойствах мыши»
        Ok "$CursorDir"
    }
}

# ============================================================
# 1. Снимок исходного состояния: создаётся при первом запуске,
#    потом только дополняется значениями, которых в нём ещё нет
# ============================================================
Step 'Снимок исходного состояния'
$firstRun = -not (Test-Path $Snapshot)
$items = @(); $known = @{}
if (-not $firstRun) {
    $items = Get-Content $Snapshot -Raw -Encoding UTF8 | ConvertFrom-Json   # PS 5.1: сначала в переменную
    $items = @($items)
    foreach ($it in $items) { $known["$($it.Path)|$($it.Name)"] = $true }
}
# все значения, которые скрипт трогает при текущих ключах, плюс сам путь к обоям
$names = @($Changes | ForEach-Object { "$($_.Path)|$($_.Name)" }) +
         "$CD|WallpaperStyle", "$CD|TileWallpaper", "$CD|WallPaper"
$added = @(foreach ($n in ($names | Select-Object -Unique)) {
    if ($known.ContainsKey($n)) { continue }
    $path, $name = $n -split '\|', 2
    $cur = Get-RegValue $path $name
    [ordered]@{ Path = $path; Name = $name; Existed = $cur.Existed; Kind = $cur.Kind; Value = $cur.Value }
})
if ($firstRun) {
    New-Item -ItemType Directory -Force (Join-Path $Original 'files') | Out-Null
    foreach ($k in $RegKeys) { reg export $k (Join-Path $Original (($k -split '\\')[-1] + '.reg')) /y 2>$null | Out-Null }
    foreach ($c in $ConfigCopies) { $dst = $c[1]; if (Test-Path $dst) { Copy-Item $dst (Saved-ConfigPath $dst) } }
}
if ($added.Count) {
    $all = @($items) + $added
    ConvertTo-Json -InputObject $all -Depth 4 | Set-Content $Snapshot -Encoding UTF8
}
if ($firstRun) { Ok "$Original (значений: $($added.Count))" }
elseif ($added.Count) { Ok "дописано в снимок новых значений: $($added.Count) (старые не тронуты)" }
else { Ok "уже есть с первого запуска: $Original (не перезаписываю)" }

# ============================================================
# 2. Запись в реестр
# ============================================================
Step 'Тема, акцент Tokyo Night, панель задач, Проводник'
foreach ($c in $Changes) { Set-RegValue $c.Path $c.Name $c.Value $c.Kind }
if (-not $stuck) { Warn 'StuckRects3 не найден, автоскрытие включи вручную: Параметры -> Персонализация -> Панель задач' }
if ($cursorReady) { Update-Cursors }
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
# скрипты пользовательских виджетов YASB (VPN, Docker, GitHub)
$ScriptsDst = "$HOME\.config\yasb\scripts"
New-Item -ItemType Directory -Force $ScriptsDst | Out-Null
Copy-Item "$Here\yasb\scripts\*.ps1" $ScriptsDst -Force
Ok "$ScriptsDst ($(@(Get-ChildItem "$Here\yasb\scripts\*.ps1").Count) скрипта)"

# ============================================================
# 5. Автозапуск
# ============================================================
Step 'Автозапуск'
if (Test-Path $YasbExe) {
    $lnk = (New-Object -ComObject WScript.Shell).CreateShortcut($YasbLnk)
    $lnk.TargetPath = $YasbExe; $lnk.WorkingDirectory = Split-Path $YasbExe
    $lnk.Save()
    Ok "YASB ($YasbLnk)"
} else { Warn 'YASB не установлен (сначала setup-windows.ps1)' }
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
if ($stuck) {
    if (Set-TaskbarAutoHide $true) { Ok 'панель задач: автоскрытие включено' }
    else { Warn 'автоскрытие панели задач не включилось: Параметры -> Персонализация -> Панель задач' }
}

if (-not $NoStart) {
    Step 'Запуск YASB и GlazeWM'
    Get-Process yasb -ErrorAction SilentlyContinue | Stop-Process -Force
    if (Test-Path $YasbExe) { Start-Process $YasbExe; Start-Sleep -Seconds 3; Ok 'YASB' }
    # GlazeWM работает с uiAccess: Stop-Process его не берёт ("Access is denied"), а запуск через
    # оператор & падает ("requires elevation"). Поэтому только Start-Process и его собственный CLI.
    if (Test-Path $GlazeExe) {
        if (Get-Process glazewm -ErrorAction SilentlyContinue) {
            Start-Process $GlazeExe -ArgumentList 'command', 'wm-reload-config' -WindowStyle Hidden -Wait
            Ok 'GlazeWM уже запущен: конфиг перечитан'
        } else { Start-Process $GlazeExe; Ok 'GlazeWM' }
    }
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
