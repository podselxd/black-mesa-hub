param([switch]$NoBrowser)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Web = Join-Path $Root 'web'
$SettingsFile = Join-Path $Root 'settings.json'
$RunFile = Join-Path $Root 'run.json'
$LogFile = Join-Path $Root 'hub.log'
$Utf8 = New-Object System.Text.UTF8Encoding($false)
$AppTitle = 'Black Mesa Hub'

$Version = '0.0.0'
$versionFile = Join-Path $Root 'version.txt'
if (Test-Path $versionFile) { $Version = (Get-Content $versionFile -Raw).Trim() }

function Log($m) {
    try {
        # el log no crece sin limite: si pasa de 200 KB, se queda con las ultimas 200 lineas
        if ((Test-Path $LogFile) -and (Get-Item $LogFile).Length -gt 200KB) { $keep = Get-Content $LogFile -Tail 200; Set-Content $LogFile $keep -Encoding UTF8 }
        Add-Content -Path $LogFile -Value ("{0} {1}" -f (Get-Date -Format s), $m)
    } catch {}
}

function Get-Changelog {
    $f = Join-Path $Root 'changelog.json'
    if (-not (Test-Path $f)) { return @() }
    try {
        # PowerShell 5.1 devuelve el arreglo JSON como un solo objeto: hay que recorrerlo para aplanarlo
        $out = @(); foreach ($e in (Get-Content $f -Raw -Encoding UTF8 | ConvertFrom-Json)) { $out += $e }
        return $out
    }
    catch { return @() }
}

function Read-Settings {
    if (Test-Path $SettingsFile) { try { return (Get-Content $SettingsFile -Raw -Encoding UTF8 | ConvertFrom-Json) } catch {} }
    return $null
}

$HubWinSource = @"
using System;
using System.Runtime.InteropServices;
public static class HubWin {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
    [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte sc, uint flags, UIntPtr extra);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr h, System.Text.StringBuilder s, int n);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern int GetWindowThreadProcessId(IntPtr h, out int pid);
    [DllImport("user32.dll")] static extern bool AttachThreadInput(int a, int b, bool f);
    [DllImport("user32.dll")] static extern bool BringWindowToTop(IntPtr h);
    [DllImport("kernel32.dll")] static extern int GetCurrentThreadId();
    // Trae el juego al frente aunque otra app tenga el foco, para que capture el mouse
    public static void ForceForeground(IntPtr h) {
        ShowWindow(h, 9);
        int pid;
        int fgT = GetWindowThreadProcessId(GetForegroundWindow(), out pid);
        int me = GetCurrentThreadId();
        if (fgT != me) AttachThreadInput(me, fgT, true);
        BringWindowToTop(h);
        SetForegroundWindow(h);
        if (fgT != me) AttachThreadInput(me, fgT, false);
    }
    public static bool IsForeground(IntPtr h) { return GetForegroundWindow() == h; }
    public static int FocusByTitle(string prefix) {
        int c = 0;
        EnumWindows(delegate(IntPtr h, IntPtr l) {
            System.Text.StringBuilder sb = new System.Text.StringBuilder(256);
            GetWindowText(h, sb, 256);
            if (sb.ToString().StartsWith(prefix)) { ForceForeground(h); c++; return false; }
            return true;
        }, IntPtr.Zero);
        return c;
    }
    public static int MinimizeByTitle(string prefix) {
        int c = 0;
        EnumWindows(delegate(IntPtr h, IntPtr l) {
            System.Text.StringBuilder sb = new System.Text.StringBuilder(256);
            GetWindowText(h, sb, 256);
            if (IsWindowVisible(h) && sb.ToString().StartsWith(prefix)) { ShowWindow(h, 6); c++; }
            return true;
        }, IntPtr.Zero);
        return c;
    }
    // Minimiza sin activar todas las ventanas visibles de un proceso (la consola del servidor dedicado)
    public static int MinimizeByPid(int pid) {
        int c = 0;
        EnumWindows(delegate(IntPtr h, IntPtr l) {
            int p; GetWindowThreadProcessId(h, out p);
            if (p == pid && IsWindowVisible(h)) { ShowWindow(h, 7); c++; }
            return true;
        }, IntPtr.Zero);
        return c;
    }
}
"@

# Compilar C# cuesta ~0,4 s en cada arranque. Se compila una vez a cache\NOMBRE-<huella>.dll y despues solo se carga.
function Import-Cached([string]$Source, [string]$Name, [string[]]$Refs = @()) {
    $sha = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($Source))).Replace('-', '').Substring(0, 10)
    $dir = Join-Path $Root 'cache'
    $dll = Join-Path $dir "$Name-$sha.dll"
    try {
        if (-not (Test-Path $dll)) {
            New-Item -ItemType Directory -Force $dir | Out-Null
            Get-ChildItem $dir -Filter "$Name-*.dll" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
            if ($Refs.Count) { Add-Type -TypeDefinition $Source -OutputAssembly $dll -OutputType Library -ReferencedAssemblies $Refs } else { Add-Type -TypeDefinition $Source -OutputAssembly $dll -OutputType Library }
        }
        Add-Type -Path $dll
    }
    catch {
        if ($Refs.Count) { Add-Type -TypeDefinition $Source -ReferencedAssemblies $Refs } else { Add-Type -TypeDefinition $Source }
    }
}
Import-Cached $HubWinSource 'HubWin'
[HubWin]::SetProcessDPIAware() | Out-Null

function Hide-HubWindow { [HubWin]::MinimizeByTitle($AppTitle) | Out-Null }

function Get-ScreenSize { @{ w = [HubWin]::GetSystemMetrics(0); h = [HubWin]::GetSystemMetrics(1) } }

# ventana | full (resolucion nativa) | full43 (4:3 con barras negras a los lados)
function Get-ScreenArgs($mode) {
    $s = Get-ScreenSize
    switch ($mode) {
        'window' { return @('-windowed') }
        'full43' { return @('-fullscreen', '-width', [string][int]($s.h * 4 / 3), '-height', [string]$s.h) }
        default { return @('-fullscreen', '-width', [string]$s.w, '-height', [string]$s.h) }
    }
}

. (Join-Path $Root 'lib.ps1')

$script:Page = $null
$script:PageStamp = 0
function Get-Page {
    $f = Join-Path $Web 'index.html'
    $t = (Get-Item $f).LastWriteTimeUtc.Ticks
    if ($script:PageStamp -ne $t) {
        $script:Page = $Utf8.GetBytes((Get-Content $f -Raw -Encoding UTF8).Replace('__TOKEN__', $token))
        $script:PageStamp = $t
    }
    return , $script:Page
}

# ---------------- arranque de partidas ----------------
$script:Launch = $null

function Read-LogFrom($path, [long]$offset) {
    if (-not (Test-Path $path)) { return '' }
    $fs = [IO.File]::Open($path, 'Open', 'Read', 'ReadWrite')
    try {
        if ($fs.Length -lt $offset) { $offset = 0 }
        $fs.Seek($offset, 'Begin') | Out-Null
        return (New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8)).ReadToEnd()
    }
    finally { $fs.Close() }
}
function Get-LogLength($path) { if (Test-Path $path) { return (Get-Item $path).Length } else { return 0 } }
function Get-ClientLogPath($client) { Join-Path $client 'bms\console.log' }

function Stop-BmsServer($srv) {
    $p = Get-ServerProc $srv
    if (-not $p) { return }
    # primero se le pide que salga solo (cerrarlo a la fuerza deja a Steam creyendo que el juego sigue abierto)
    try { Send-ServerCmd $srv @('quit') -Raw | Out-Null } catch {}
    for ($i = 0; $i -lt 40 -and (Get-ServerProc $srv); $i++) { Start-Sleep -Milliseconds 250 }
    if (Get-ServerProc $srv) { Get-ServerProc $srv | Stop-Process -Force -ErrorAction SilentlyContinue; Log 'el servidor no salio solo: se cerro a la fuerza' }
}

# Los mismos argumentos que usa Steam en la opcion "Default" de Black Mesa: -steam -disabledxvk
function Get-GfxArgs($gfx) {
    switch ($gfx) { 'dxvk' { return @() } 'd3d9' { return @('-forceuid3d9', '-disabledxvk') } default { return @('-disabledxvk') } }
}
function Start-Client($client, $args2, $screen, $gfx) {
    $a = @('-steam') + (Get-GfxArgs $gfx) + @('-console', '-condebug', '-novid') + (Get-ScreenArgs $screen) + $args2
    Start-Process -FilePath (Join-Path $client 'bms.exe') -ArgumentList $a -WorkingDirectory $client | Out-Null
    Log ("cliente: " + ($a -join ' '))
}

function Start-Game($client, $srv, $user, $p) {
    if (-not $client) { throw 'No encuentro Black Mesa. Instálalo desde Steam.' }
    if (-not (Get-Process -Name steam -ErrorAction SilentlyContinue)) { throw 'Steam está cerrado. Abre Steam y vuelve a intentar.' }
    if (Get-ClientProc) { throw 'Black Mesa ya está abierto. Ciérralo primero (botón Cerrar juego).' }
    # un doble clic en Iniciar no debe apagar el servidor que acaba de arrancar
    $prev = $script:Launch
    if ($p.mode -ne 'join' -and $prev -and $prev.mode -ne 'join' -and -not $prev.handled -and ((Get-Date) - $prev.at).TotalSeconds -lt 120 -and (Get-ServerProc $srv)) { throw 'La partida ya se está iniciando.' }
    $mode = "$($p.screen)"; if (-not $mode) { $mode = 'full' }
    $script:Launch = @{ at = Get-Date; mode = "$($p.mode)"; minimize = ($p.minimize -ne $false); screen = $mode; gfx = "$($p.gfx)"; handled = $false; clientStarted = $false; seen = $false
        offset = (Get-LogLength (Get-ClientLogPath $client)); map = ''; ip = ''; pass = ''; srvPid = 0 }

    if ($p.mode -eq 'join') {
        if ("$($p.ip)" -notmatch '^[A-Za-z0-9\.\-]{1,100}(:\d{2,5})?$') { throw 'Dirección inválida. Usa IP o IP:puerto.' }
        $ip = "$($p.ip)"; if ($ip -notmatch ':') { $ip = "${ip}:$($script:GamePort)" }   # el puerto por defecto de Source
        $a = @("+connect", $ip)
        $pw = "$($p.password)"
        if ($pw) { if ($pw -notmatch '^[A-Za-z0-9_\-\.!@#\$%\^&\*]{1,40}$') { throw 'Contraseña con caracteres no válidos.' }; $a = @('+password', $pw) + $a }
        $script:Launch.ip = $ip; $script:Launch.clientStarted = $true
        Start-Client $client $a $mode "$($p.gfx)"
        return
    }

    # ----- anfitrion: servidor dedicado + este mismo PC como jugador -----
    if (-not $srv) { throw 'Falta Black Mesa Dedicated Server (es gratis en Steam, en Herramientas).' }
    if (-not (Test-ComponentsOk $srv)) { throw 'Faltan componentes del servidor: ve a Ajustes → Instalar.' }
    if ("$($p.map)" -notmatch '^[A-Za-z0-9_]+$') { throw 'Mapa inválido.' }
    $max = [math]::Min(32, [math]::Max(2, [int]$p.maxplayers))
    $host2 = "$($p.hostname)"; if (-not $host2) { $host2 = "Black Mesa Co-op de $($user.name)" }
    $cfgP = @{ hostname = $host2; password = $p.password; friendlyfire = [bool]$p.friendlyfire; cheats = [bool]$p.cheats; survival = [int]$p.survival; respawn = $p.respawn; extra = $p.extra }
    Stop-BmsServer $srv
    $sm = Join-Path $srv 'bms\addons\sourcemod'
    $sp = Join-Path $Root 'plugins\HubCmds.sp'; $smx = Join-Path $sm 'plugins\hubcmds.smx'
    if (-not (Test-Path $smx) -or (Get-Item $sp).LastWriteTimeUtc -gt (Get-Item $smx).LastWriteTimeUtc) { Install-HubPlugin $srv | Out-Null }
    try { if (Install-SrcCoopFix $srv) { Log 'aplicado el arreglo de gamedata de SourceCoop (PR 375)' } } catch { throw "SourceCoop 1.6 necesita un arreglo para la ultima version de Black Mesa y no pude descargarlo: $($_.Exception.Message)" }
    Set-ServerCfg $srv $cfgP
    if ($user) { Set-HostAdmin $srv $user.steamId }
    foreach ($f in 'hubcmd.txt', 'hubcmd.ack', 'hubstate.txt') { Remove-Item (Join-Path (Get-DataDir $srv) $f) -Force -ErrorAction SilentlyContinue }
    $gp = Get-FreeGamePort
    $a = @('-console', '-nomessagebox', '-condebug', '-game', 'bms', '-ip', '0.0.0.0', '-port', [string]$gp, '+maxplayers', [string]$max, '+mp_teamplay', '1', '+map', $p.map)
    $proc = Start-Process -FilePath (Join-Path $srv 'srcds.exe') -ArgumentList $a -WorkingDirectory $srv -WindowStyle Minimized -PassThru
    $script:Launch.srvArgs = $a; $script:Launch.srvOffset = (Get-LogLength (Join-Path $srv 'bms\console.log')); $script:Launch.srvRestarted = $false
    $script:Launch.map = "$($p.map)"; $script:Launch.srvPid = $proc.Id; # El servidor no contesta a 127.0.0.1 (Source ignora el loopback si escucha en 0.0.0.0): el propio PC entra por su direccion de red
    $self = @(Get-Addresses | Where-Object { $_.kind -eq 'lan' } | Select-Object -First 1); if (-not $self) { $self = @(Get-Addresses | Select-Object -First 1) }
    $selfIp = '127.0.0.1'; if ($self) { $selfIp = $self[0].ip }
    $script:Launch.ip = "${selfIp}:$gp"
    Log ("servidor: " + ($a -join ' '))
}

function Get-LaunchProgress($client, $srv, $user) {
    $L = $script:Launch
    if (-not $L) { return @{ active = $false } }
    $elapsed = [int]((Get-Date) - $L.at).TotalSeconds
    $cp = Get-ClientProc
    if ($cp) { $L.seen = $true }
    $steps = @(); $err = $null; $done = $false

    if ($L.mode -eq 'join') {
        $text = Read-LogFrom (Get-ClientLogPath $client) $L.offset
        $opened = [bool]($cp -and $cp.MainWindowHandle -ne 0) -or $text.Length -gt 0
        $conn = ($text -match 'Connected to|Spawn Server|Sending client info|SignonState')
        $steps += @{ k = 'game'; label = 'Abriendo Black Mesa'; done = $opened }
        $steps += @{ k = 'connect'; label = "Conectando a $($L.ip)"; done = ($opened -and ($conn -or $elapsed -gt 25)) }
        $steps += @{ k = 'ready'; label = 'Dentro de la partida'; done = ($opened -and ($conn -or $elapsed -gt 45)) -and $cp }
        $done = @($steps | Where-Object { -not $_.done }).Count -eq 0
        if (-not $cp -and $L.seen -and -not $done) { $err = 'El juego se cerró antes de terminar de cargar.' }
        elseif (-not $cp -and -not $L.seen -and $elapsed -gt 40) { $err = 'El juego no abrió. Revisa que Steam esté abierto.' }
    }
    else {
        $sp = Get-ServerProc $srv
        $st = Get-ServerState $srv
        if ($sp -and $elapsed -lt 40) { [HubWin]::MinimizeByPid($sp.Id) | Out-Null }
        # La primera vez, el Updater de SourceMod baja gamedata nuevo y pide reiniciar: el servidor se reinicia una sola vez, antes de abrir el juego
        if ($sp -and -not $L.srvRestarted -and -not $L.clientStarted -and $srv) {
            if ((Read-LogFrom (Join-Path $srv 'bms\console.log') $L.srvOffset) -match 'SourceMod has been updated, please reload') {
                $L.srvRestarted = $true
                Log 'SourceMod actualizo su gamedata: se reinicia el servidor una vez'
                Stop-BmsServer $srv
                foreach ($f in 'hubcmd.txt', 'hubcmd.ack', 'hubstate.txt') { Remove-Item (Join-Path (Get-DataDir $srv) $f) -Force -ErrorAction SilentlyContinue }
                $L.srvOffset = Get-LogLength (Join-Path $srv 'bms\console.log')
                $proc2 = Start-Process -FilePath (Join-Path $srv 'srcds.exe') -ArgumentList $L.srvArgs -WorkingDirectory $srv -WindowStyle Minimized -PassThru
                $L.srvPid = $proc2.Id; $L.at = Get-Date
                $sp = $proc2; $st = $null
            }
        }
        $mapOk = [bool]($st -and $st.map -eq $L.map)
        $steps += @{ k = 'srv'; label = 'Encendiendo el servidor'; done = [bool]$sp }
        $steps += @{ k = 'plug'; label = 'Cargando SourceMod y SourceCoop'; done = [bool]$st }
        $steps += @{ k = 'map'; label = "Cargando el mapa $($L.map)"; done = $mapOk }
        if ($mapOk -and -not $L.clientStarted) { $L.clientStarted = $true; Start-Client $client @('+connect', $L.ip) $L.screen $L.gfx }
        $steps += @{ k = 'game'; label = 'Abriendo Black Mesa'; done = [bool]($L.clientStarted -and $cp -and $cp.MainWindowHandle -ne 0) }
        $steps += @{ k = 'ready'; label = 'Dentro de la partida'; done = [bool]($mapOk -and $st.players -ge 1 -and $cp) }
        $done = @($steps | Where-Object { -not $_.done }).Count -eq 0
        if (-not $sp -and -not $done) { $err = 'El servidor se cerró. Mira el diagnóstico en Ajustes.' }
        elseif ($sp -and -not $st -and $elapsed -gt 120) { $err = 'El servidor no cargó el plugin del Hub en 2 minutos. Mira el diagnóstico en Ajustes.' }
        elseif ($L.clientStarted -and -not $cp -and $L.seen -and -not $done) { $err = 'El juego se cerró antes de entrar.' }
        elseif ($L.clientStarted -and -not $cp -and -not $L.seen -and ((Get-Date) - $L.at).TotalSeconds -gt 150) { $err = 'El juego no abrió. Revisa que Steam esté abierto.' }
    }
    if ($done -and -not $L.handled) {
        $L.handled = $true
        if ($L.minimize) { Hide-HubWindow }
        if ($cp) { Start-Sleep -Milliseconds 700; [HubWin]::ForceForeground($cp.MainWindowHandle) }
    }
    return @{ active = $true; steps = $steps; done = $done; error = $err; elapsed = $elapsed }
}

function Get-InstallStatus {
    $f = Join-Path $Root 'install.json'
    if (-not (Test-Path $f)) { return @{ active = $false } }
    try { $o = Get-Content $f -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return @{ active = $true; steps = @(); error = ''; finished = $false } }
    $age = ((Get-Date) - (Get-Item $f).LastWriteTime).TotalSeconds
    $alive = [bool]($script:InstallProc -and -not $script:InstallProc.HasExited)
    $err = "$($o.error)"
    if (-not $o.finished -and -not $alive -and $age -gt 5) { $err = 'La instalación se detuvo.' }
    return @{ active = $true; steps = @($o.steps); error = $err; finished = [bool]($o.finished -or $err) }
}
$script:InstallProc = $null

function Send($ctx, $body, $type = 'application/json; charset=utf-8', $status = 200) {
    if ($body -isnot [byte[]]) {
        if ($body -isnot [string]) { $body = $body | ConvertTo-Json -Depth 8 -Compress }
        $body = $Utf8.GetBytes($body)
    }
    $ctx.Response.StatusCode = $status
    $ctx.Response.ContentType = $type
    $ctx.Response.Headers.Add('Cache-Control', 'no-store')
    $ctx.Response.ContentLength64 = $body.Length
    $ctx.Response.OutputStream.Write($body, 0, $body.Length)
    $ctx.Response.OutputStream.Close()
}

function Open-Window($url) {
    if ($NoBrowser) { return $null }
    $edge = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $edge) { $edge = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe' -ErrorAction SilentlyContinue).'(default)' }
    if ($edge) {
        $prof = Join-Path $Root '.browser-profile'
        return Start-Process -FilePath $edge -ArgumentList @("--app=$url", '--start-maximized', "--user-data-dir=`"$prof`"", '--no-first-run', '--no-default-browser-check', '--disable-extensions', '--disable-sync', '--disable-features=Translate') -PassThru
    }
    Start-Process $url | Out-Null
    return $null
}

# ---- instancia unica: si ya esta corriendo, solo abre otra ventana ----
if (Test-Path $RunFile) {
    try {
        $r = Get-Content $RunFile -Raw | ConvertFrom-Json
        if ((Get-Process -Id $r.pid -ErrorAction SilentlyContinue).ProcessName -match 'powershell') { Open-Window "http://127.0.0.1:$($r.port)/?t=$($r.token)" | Out-Null; exit 0 }
    } catch {}
}

$client = Find-Client
$srv = Find-Server
$token = [guid]::NewGuid().ToString('N')
$listener = $null; $port = 0
foreach ($try in 1..30) {
    $port = Get-Random -Minimum 41000 -Maximum 49000
    try { $listener = New-Object System.Net.HttpListener; $listener.Prefixes.Add("http://127.0.0.1:$port/"); $listener.Start(); break } catch { $listener = $null }
}
if (-not $listener) { throw 'No pude abrir un puerto local.' }
@{ pid = $PID; port = $port; token = $token } | ConvertTo-Json | Set-Content $RunFile -Encoding ASCII
$user = Get-SteamUser
$lastPing = Get-Date
$edgeProc = Open-Window "http://127.0.0.1:$port/?t=$token"
Log "hub en puerto $port | cliente: $client | servidor: $srv"

try {
    while ($listener.IsListening) {
        $task = $listener.GetContextAsync()
        while (-not $task.Wait(1000)) {
            # El proceso de Edge que lanzamos puede terminar enseguida (en la primera ejecucion, o si ya hay una ventana abierta con el mismo perfil se la pasa a esa):
            # si el Hub muriera con el, la ventana se quedaria con «Se perdio la conexion». Se vive de los latidos de la pagina (cada 3 s).
            $quiet = ((Get-Date) - $lastPing).TotalSeconds
            if ($quiet -gt 900) { return }
            if ($quiet -gt 150 -and $edgeProc -and $edgeProc.HasExited) { return }
        }
        $ctx = $task.Result
        try {
            $path = $ctx.Request.Url.AbsolutePath
            $authed = ($ctx.Request.Headers['X-Hub'] -eq $token)
            if ($path -eq '/' -or $path -eq '/index.html') { Send $ctx (Get-Page) 'text/html; charset=utf-8'; continue }
            if (-not $authed) { Send $ctx '{"error":"no autorizado"}' 'application/json' 403; continue }
            switch ($path) {
                '/api/ping' {
                    $lastPing = Get-Date
                    $st = $null; if ($srv) { $st = Get-ServerState $srv }
                    Send $ctx @{ port = $(if ($sp = Get-ServerPort $srv) { $sp } else { Get-FreeGamePort }); running = [bool](Get-ClientProc); steam = [bool](Get-Process steam -ErrorAction SilentlyContinue); server = [bool](Get-ServerProc $srv); players = $(if ($st) { $st.names } else { @() }); map = $(if ($st) { $st.map } else { '' }) }
                }
                '/api/state' {
                    Send $ctx @{
                        clientPath = $client; serverPath = $srv; steamId = $user.steamId; steamName = $user.name
                        steamRunning = [bool](Get-Process steam -ErrorAction SilentlyContinue)
                        running = [bool](Get-ClientProc); serverRunning = [bool](Get-ServerProc $srv)
                        chapters = @(Get-Chapters $srv)
                        components = $(if ($srv) { @(Get-Components $srv) } else { @() })
                        addresses = @(Get-Addresses)
                        port = $(if ($sp = Get-ServerPort $srv) { $sp } else { Get-FreeGamePort })
                        version = $Version
                        changelog = @(Get-Changelog)
                        screen = (Get-ScreenSize)
                        settings = (Read-Settings)
                    }
                }
                '/api/save' {
                    $body = (Read-Body $ctx)
                    try { $null = $body | ConvertFrom-Json } catch { throw 'Ajustes invalidos (no son JSON).' }
                    Write-Atomic $SettingsFile $body
                    Send $ctx @{ ok = $true }
                }
                '/api/launch' {
                    $p = (Read-Body $ctx) | ConvertFrom-Json
                    try { Start-Game $client $srv $user $p; Send $ctx @{ ok = $true } }
                    catch { $script:Launch = $null; Send $ctx @{ ok = $false; error = $_.Exception.Message } }
                }
                '/api/progress' { Send $ctx (Get-LaunchProgress $client $srv $user) }
                '/api/cmd' {
                    $p = (Read-Body $ctx) | ConvertFrom-Json
                    try { $cid = Send-ServerCmd $srv @($p.cmds); Send $ctx @{ ok = $true; id = $cid } }
                    catch { Send $ctx @{ ok = $false; error = $_.Exception.Message } }
                }
                '/api/cmdstatus' { Send $ctx @{ done = [bool](Test-CmdAck $srv "$($ctx.Request.QueryString['id'])") } }
                '/api/stop' {
                    Get-Process -Name bms -ErrorAction SilentlyContinue | Stop-Process -Force
                    Send $ctx @{ ok = $true }
                }
                '/api/stopserver' {
                    Get-Process -Name bms -ErrorAction SilentlyContinue | Stop-Process -Force
                    Stop-BmsServer $srv
                    Send $ctx @{ ok = $true }
                }
                '/api/srccoop' {
                    $tag = Get-SrcCoopTag $srv; $latest = $null; $err = ''
                    if ($ctx.Request.QueryString['check'] -eq '1') { try { $latest = (Get-SrcCoopLatest).tag } catch { $err = $_.Exception.Message } }
                    Send $ctx @{ tag = $tag; latest = $latest; outdated = [bool]($latest -and $tag -and $latest -ne $tag); waiting = $false; error = $err }
                }
                '/api/install' {
                    $pInst = (Read-Body $ctx) | ConvertFrom-Json
                    if ($script:InstallProc -and -not $script:InstallProc.HasExited) { Send $ctx @{ ok = $true }; break }
                    if (-not $srv) { Send $ctx @{ ok = $false; error = 'Falta Black Mesa Dedicated Server.' }; break }
                    if (Get-ServerProc $srv) { Send $ctx @{ ok = $false; error = 'Detén el servidor antes de instalar.' }; break }
                    Remove-Item (Join-Path $Root 'install.json') -Force -ErrorAction SilentlyContinue
                    $ia = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$(Join-Path $Root 'install.ps1')`"", '-Srv', "`"$srv`"")
                    if ($user) { $ia += @('-SteamId', $user.steamId) }
                    if ($pInst.update) { $ia += '-Update' }
                    $script:InstallProc = Start-PSHidden $ia
                    Send $ctx @{ ok = $true }
                }
                '/api/installstatus' { Send $ctx (Get-InstallStatus) }
                '/api/addresses' { Send $ctx @{ addresses = @(Get-Addresses) } }
                '/api/publicip' {
                    try { Send $ctx @{ ok = $true; ip = (Get-PublicIp) } }
                    catch { Send $ctx @{ ok = $false; error = $_.Exception.Message } }
                }
                '/api/openurl' {
                    $p = (Read-Body $ctx) | ConvertFrom-Json
                    try { Open-AllowedUrl "$($p.url)"; Send $ctx @{ ok = $true } }
                    catch { Send $ctx @{ ok = $false; error = $_.Exception.Message } }
                }
                '/api/diag' { Send $ctx @{ text = (Get-Diag $client $srv $user $user.steamId) } }
                '/api/health' { Send $ctx @{ items = @(Get-Health $client $srv $user $user.steamId) } }
                '/api/repair' {
                    try {
                        if (-not $srv) { throw 'Falta Black Mesa Dedicated Server.' }
                        if (Test-ComponentsOk $srv) {
                            if (-not (Get-ServerProc $srv)) { [void](Install-SrcCoopFix $srv); Install-HubPlugin $srv | Out-Null }
                            if ($user) { Set-HostAdmin $srv $user.steamId }
                        }
                        Send $ctx @{ ok = $true; needsInstall = (-not (Test-ComponentsOk $srv)); items = @(Get-Health $client $srv $user $user.steamId) }
                    }
                    catch { Send $ctx @{ ok = $false; error = $_.Exception.Message } }
                }
                '/api/undo' {
                    try {
                        if (Get-ServerProc $srv) { throw 'Detén el servidor primero.' }
                        Undo-All $srv; Send $ctx @{ ok = $true; items = @(Get-Health $client $srv $user $user.steamId) }
                    }
                    catch { Send $ctx @{ ok = $false; error = $_.Exception.Message } }
                }
                '/api/steam' { Start-Process 'steam://open/main'; Send $ctx @{ ok = $true } }
                '/api/quit' { Send $ctx @{ ok = $true }; return }
                default { Send $ctx '{"error":"404"}' 'application/json' 404 }
            }
        }
        catch { Log ("error: " + $_.Exception.Message); try { Send $ctx @{ ok = $false; error = $_.Exception.Message } 'application/json' 500 } catch {} }
    }
}
finally {
    try { $listener.Stop() } catch {}
    Remove-Item $RunFile -ErrorAction SilentlyContinue
}
