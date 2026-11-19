# lib.ps1 - utilidades del Black Mesa Hub (se carga con dot-source desde hub.ps1 e install.ps1)
# Usa $Utf8 y $Root, definidos por quien lo carga. Aqui solo hay funciones: cargarlo no hace nada.

$script:GamePort = 27015
$script:MarkBegin = '// >>> Black Mesa Hub'
$script:MarkEnd = '// <<< Black Mesa Hub'
$script:AllowedHosts = 'steamcommunity.com', 'store.steampowered.com', 'www.moddb.com', 'www.sourcemod.net', 'wiki.alliedmods.net', 'github.com', 'developer.valvesoftware.com', 'blackmesasource.com', 'discord.gg', 'www.blackmesasource.com'

# Escritura atomica: se escribe a un temporal y se reemplaza. Un corte de luz no deja un archivo roto.
function Write-Atomic([string]$Path, [string]$Text) {
    $tmp = "$Path.hubtmp"
    [IO.File]::WriteAllText($tmp, $Text, $Utf8)
    if (Test-Path $Path) {
        $old = "$Path.hubold"
        [IO.File]::Replace($tmp, $Path, $old)
        Remove-Item $old -Force -ErrorAction SilentlyContinue
    }
    else { [IO.File]::Move($tmp, $Path) }
}

# Lee el cuerpo de una peticion con tope de tamano
function Read-Body($ctx, [int]$Max = 65536) {
    $sr = New-Object IO.StreamReader($ctx.Request.InputStream, $Utf8)
    $buf = New-Object char[] ($Max + 1)
    $n = $sr.Read($buf, 0, $Max + 1)
    if ($n -gt $Max) { throw 'Peticion demasiado grande.' }
    return [string]::new($buf, 0, $n)
}

function Set-Setting([string]$Name, $Value) {
    $f = Join-Path $Root 'settings.json'
    $o = [ordered]@{}
    if (Test-Path $f) { try { (Get-Content $f -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $o[$_.Name] = $_.Value } } catch {} }
    $o[$Name] = $Value
    Write-Atomic $f ($o | ConvertTo-Json -Depth 6)
}

# Lanza un powershell SIN consola (CreateNoWindow). Start-Process -WindowStyle Hidden no basta en Windows 11.
function Start-PSHidden([string[]]$ArgList) {
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = ($ArgList -join ' ')
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.WorkingDirectory = $Root
    return [Diagnostics.Process]::Start($psi)
}

function Open-AllowedUrl([string]$Url) {
    $u = $null
    if (-not [Uri]::TryCreate($Url, 'Absolute', [ref]$u) -or $u.Scheme -ne 'https' -or $script:AllowedHosts -notcontains $u.Host) { throw 'Ese enlace no esta permitido.' }
    Start-Process $u.AbsoluteUri | Out-Null
}

# ================= Steam y rutas =================
function Get-SteamPath {
    $p = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
    if ($p) { return ($p -replace '/', '\') }
    'C:\Program Files (x86)\Steam'
}

function Get-SteamLibraries {
    $steam = Get-SteamPath
    $libs = @($steam)
    $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
    if (Test-Path $vdf) { foreach ($m in [regex]::Matches((Get-Content $vdf -Raw), '"path"\s+"([^"]+)"')) { $libs += ($m.Groups[1].Value -replace '\\\\', '\') } }
    return @($libs | Select-Object -Unique)
}

function Find-SteamGame([string]$Dir, [string]$Exe) {
    foreach ($l in (Get-SteamLibraries)) {
        $d = Join-Path $l "steamapps\common\$Dir"
        if (Test-Path (Join-Path $d $Exe)) { return $d }
    }
    return $null
}

function Find-Client { Find-SteamGame 'Black Mesa' 'bms.exe' }
function Find-Server { Find-SteamGame 'Black Mesa Dedicated Server' 'srcds.exe' }

function Get-SteamUser {
    $vdf = Join-Path (Get-SteamPath) 'config\loginusers.vdf'
    if (-not (Test-Path $vdf)) { return $null }
    $best = $null; $bestScore = -1
    foreach ($m in [regex]::Matches((Get-Content $vdf -Raw), '"(7656\d{13})"\s*\{(.*?)\}', 'Singleline')) {
        $body = $m.Groups[2].Value
        $name = [regex]::Match($body, '"PersonaName"\s+"([^"]*)"').Groups[1].Value
        $ts = [regex]::Match($body, '"timestamp"\s+"(\d+)"').Groups[1].Value
        $score = 0; if ($ts) { $score = [int64]$ts }
        if ($body -match '"MostRecent"\s+"1"') { $score += 100000000000 }
        if ($score -gt $bestScore) {
            $acc = [int64]$m.Groups[1].Value - 76561197960265728
            $best = @{ name = $name; steamId = ('STEAM_0:{0}:{1}' -f ($acc % 2), [math]::Floor($acc / 2)) }
            $bestScore = $score
        }
    }
    return $best
}

function Get-ClientProc { Get-Process -Name bms -ErrorAction SilentlyContinue | Select-Object -First 1 }
function Get-ServerProc($srv) {
    if (-not $srv) { return $null }
    Get-Process -Name srcds -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path -like "$srv\*" } | Select-Object -First 1
}

# Capitulos: los lee de los chapterN.cfg del propio servidor ("map bm_c1a1a")
function Get-Chapters($srv) {
    $out = @()
    if (-not $srv) { return $out }
    foreach ($i in 1..20) {
        $f = Join-Path $srv "bms\cfg\chapter$i.cfg"
        if (Test-Path $f) {
            $m = [regex]::Match((Get-Content $f -Raw), '(?m)^\s*map\s+([A-Za-z0-9_]+)')
            if ($m.Success -and $m.Groups[1].Value -ne 'credits') { $out += @{ n = $i; map = $m.Groups[1].Value } }
        }
    }
    return $out
}

# ================= puerto del servidor =================
# Otro programa (por ejemplo un juego de Unreal) puede tener ya el 27015: srcds se mueve solo a otro puerto y la invitacion quedaria mal.
function Test-PortFree([int]$p) {
    $ip = [Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties()
    -not (@($ip.GetActiveUdpListeners() | Where-Object { $_.Port -eq $p }).Count -or @($ip.GetActiveTcpListeners() | Where-Object { $_.Port -eq $p }).Count)
}
function Get-FreeGamePort {
    foreach ($p in (@(27015..27019) + @(27021..27040))) { if (Test-PortFree $p) { return $p } }
    return $script:GamePort
}
# Puerto en el que esta escuchando el servidor ya encendido
function Get-ServerPort($srv) {
    $sp = Get-ServerProc $srv
    if (-not $sp) { return $null }
    $e = @(Get-NetUDPEndpoint -OwningProcess $sp.Id -ErrorAction SilentlyContinue | Where-Object { $_.LocalPort -in (@(27015..27019) + @(27021..27040)) } | Sort-Object LocalPort)
    if ($e.Count) { return [int]$e[0].LocalPort }
    return $script:GamePort
}

# ================= direcciones para la invitacion =================
function Get-Addresses {
    $list = @()
    try {
        foreach ($a in (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop | Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' -and $_.PrefixOrigin -ne 'WellKnown' })) {
            $ip = $a.IPAddress; $kind = 'lan'; $label = 'Red local'
            if ($ip -match '^100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.') { $kind = 'tailscale'; $label = 'Tailscale' }
            elseif ($a.InterfaceAlias -match 'Tailscale|ZeroTier|Hamachi|Radmin') { $kind = 'vpn'; $label = $a.InterfaceAlias }
            $list += @{ ip = $ip; kind = $kind; label = $label }
        }
    } catch {}
    return $list
}

# Solo se llama cuando el usuario pulsa el boton: es la unica consulta a internet del Hub aparte de las instalaciones
function Get-PublicIp {
    $wc = New-Object Net.WebClient
    $ip = $wc.DownloadString('https://api.ipify.org').Trim()
    if ($ip -notmatch '^\d{1,3}(\.\d{1,3}){3}$') { throw 'No pude obtener tu IP publica.' }
    return $ip
}

# ================= componentes del servidor (Metamod, SourceMod, SourceCoop, plugin del Hub) =================
function Get-Components($srv) {
    $b = Join-Path $srv 'bms'
    $sm = Join-Path $b 'addons\sourcemod'
    $coop = @(Get-ChildItem (Join-Path $sm 'plugins') -Filter '*coop*.smx' -ErrorAction SilentlyContinue)
    $hub = (Test-Path (Join-Path $sm 'plugins\hubcmds.smx'))
    @(
        @{ id = 'metamod'; name = 'Metamod:Source'; ok = [bool]((Test-Path (Join-Path $b 'addons\metamod.vdf')) -and (Test-Path (Join-Path $b 'addons\metamod'))); detail = 'Carga los plugins del servidor' }
        @{ id = 'sourcemod'; name = 'SourceMod'; ok = [bool](Test-Path (Join-Path $sm 'bin')); detail = 'Plataforma de plugins' }
        @{ id = 'sourcecoop'; name = 'SourceCoop'; ok = [bool]($coop.Count -gt 0); detail = 'Convierte la campaña en cooperativo' }
        @{ id = 'hubcmds'; name = 'Comandos del Hub'; ok = $hub; detail = '/tp, /god, /noclip y la cola de órdenes' }
    )
}

function Test-ComponentsOk($srv) { (@(Get-Components $srv | Where-Object { -not $_.ok }).Count -eq 0) }

# El Updater de SourceMod reemplaza el gamedata por el de la ultima version, que no es el de la compilacion instalada (y SourceCoop necesita una concreta):
# con el gamedata mezclado el servidor se cae al entrar el primer jugador. Se quita siempre.
function Disable-SmUpdater($srv) {
    Remove-Item (Join-Path $srv 'bms\addons\sourcemod\extensions\updater.ext.dll') -Force -ErrorAction SilentlyContinue
}

# SourceCoop v1.6 se rompio con la actualizacion de Black Mesa del 16-nov-2026 (el servidor se cae al entrar el primer jugador, issue #374).
# El arreglo es solo el archivo gamedata/srccoop.games.txt (PR #375). Se descarga de un commit fijo y se comprueba su SHA-256; solo se aplica
# si el archivo instalado es exactamente el de la v1.6. Cuando salga una version nueva de SourceCoop, el archivo sera otro y el Hub no lo toca.
$script:SrcCoopBrokenHash = 'B52E7FB9EC94C3393D168F8F2944A8BFAFB1ED011391D46B33EBF271FC975B3F'
$script:SrcCoopFixHash = '89149BC82D3612CFD0D2EA8C63EC90EF8D79AC16278AE9F1BD24F66DBB6DA5F4'
$script:SrcCoopFixUrl = 'https://raw.githubusercontent.com/ampreeT/SourceCoop/86408624629d7b1185d37fc785da126c157d1fbb/gamedata/srccoop.games.txt'
function Test-SrcCoopBroken($srv) {
    $f = Join-Path $srv 'bms\addons\sourcemod\gamedata\srccoop.games.txt'
    (Test-Path $f) -and ((Get-FileHash $f -Algorithm SHA256).Hash -eq $script:SrcCoopBrokenHash)
}
function Install-SrcCoopFix($srv) {
    if (-not (Test-SrcCoopBroken $srv)) { return $false }
    $f = Join-Path $srv 'bms\addons\sourcemod\gamedata\srccoop.games.txt'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $tmp = Join-Path $env:TEMP 'srccoop-fix.txt'
    $wc = New-Object Net.WebClient; $wc.Headers['User-Agent'] = 'BlackMesaHub'
    $wc.DownloadFile($script:SrcCoopFixUrl, $tmp)
    if ((Get-FileHash $tmp -Algorithm SHA256).Hash -ne $script:SrcCoopFixHash) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue; throw 'El arreglo de SourceCoop descargado no coincide con el esperado.' }
    Copy-Item $f "$f.v1.6.orig" -Force
    Copy-Item $tmp $f -Force
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    return $true
}

# Version de SourceCoop que instalo el Hub (si no hay registro pero esta instalado, es la v1.6 de la primera instalacion)
function Get-SrcCoopTag($srv) {
    $f = Join-Path $Root 'srccoop.json'
    if (Test-Path $f) { try { $t = (Get-Content $f -Raw -Encoding UTF8 | ConvertFrom-Json).tag; if ($t) { return "$t" } } catch {} }
    if ($srv -and @(Get-ChildItem (Join-Path $srv 'bms\addons\sourcemod\plugins') -Filter 'srccoop.smx' -ErrorAction SilentlyContinue).Count) { return 'v1.6' }
    return ''
}
function Set-SrcCoopTag([string]$tag) { Write-Atomic (Join-Path $Root 'srccoop.json') (@{ tag = $tag } | ConvertTo-Json) }
# Ultima release publicada de SourceCoop para Black Mesa (consulta a la API de GitHub; solo cuando se pide)
function Get-SrcCoopLatest {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $wc = New-Object Net.WebClient; $wc.Headers['User-Agent'] = 'BlackMesaHub'
    $rel = $wc.DownloadString('https://api.github.com/repos/ampreeT/SourceCoop/releases/latest') | ConvertFrom-Json
    $a = @($rel.assets | Where-Object { $_.name -like '*-bms.zip' }) | Select-Object -First 1
    if (-not $a) { throw 'La ultima release de SourceCoop no trae el zip de Black Mesa.' }
    return @{ tag = "$($rel.tag_name)"; url = "$($a.browser_download_url)" }
}

# ---- server.cfg (solo el bloque del Hub; lo demas no se toca) ----
function Get-CfgPath($srv) { Join-Path $srv 'bms\cfg\server.cfg' }

function ConvertTo-CfgText([string]$s) { ("$s" -replace '["\r\n;\\]', ' ').Trim() }

function Set-ServerCfg($srv, $p) {
    $f = Get-CfgPath $srv
    $txt = ''; if (Test-Path $f) { $txt = Get-Content $f -Raw }
    $txt = [regex]::Replace($txt, '(?s)\r?\n?' + [regex]::Escape($script:MarkBegin) + '.*?' + [regex]::Escape($script:MarkEnd) + '\r?\n?', "`r`n")
    $name = ConvertTo-CfgText $p.hostname; if (-not $name) { $name = 'Black Mesa Co-op' }
    $pw = ConvertTo-CfgText $p.password
    $ff = 0; if ($p.friendlyfire) { $ff = 1 }
    $ch = 0; if ($p.cheats) { $ch = 1 }
    $sv = 0; if ($p.survival -eq 1) { $sv = 1 }
    $rs = [math]::Min(60, [math]::Max(0, [double]$p.respawn)); if ($rs -lt 0.1) { $rs = 0.1 }
    $extra = ''
    if ($p.extra) { $extra = (($p.extra -split "[\r\n]+" | Where-Object { $_.Trim() -and $_ -notmatch '(?i)^\s*(quit|exit|rcon_password|alias|bind|unbind|sm_rcon)\b' }) -join "`r`n") }
    if ($extra.Length -gt 2000) { throw 'Comandos extra demasiado largos.' }
    $block = @"
$($script:MarkBegin) (se reescribe cada vez que inicias una partida)
hostname "$name"
sv_lan 0
sv_password "$pw"
rcon_password ""
mp_teamplay 1
mp_fraglimit 0
mp_forcerespawn 1
mp_friendlyfire $ff
sv_cheats $ch
sourcecoop_survival_mode $sv
sourcecoop_respawntime $($rs.ToString([Globalization.CultureInfo]::InvariantCulture))
$extra
$($script:MarkEnd)
"@
    Write-Atomic $f ($txt.TrimEnd() + "`r`n`r`n" + $block + "`r`n")
}

function Test-ServerCfg($srv) { $f = Get-CfgPath $srv; (Test-Path $f) -and ((Get-Content $f -Raw) -like "*$($script:MarkBegin)*") }

# ---- anfitrion = admin con flag z para los comandos de chat ----
function Get-AdminPath($srv) { Join-Path $srv 'bms\addons\sourcemod\configs\admins_simple.ini' }

function Set-HostAdmin($srv, [string]$steamId) {
    if ($steamId -notmatch '^STEAM_[0-5]:([01]):(\d{1,12})$') { throw 'STEAM_ID invalido.' }
    $y = $Matches[1]; $z = $Matches[2]
    $f = Get-AdminPath $srv
    if (-not (Test-Path (Split-Path $f))) { throw 'SourceMod no esta instalado.' }
    $txt = ''; if (Test-Path $f) { $txt = Get-Content $f -Raw }
    $txt = [regex]::Replace($txt, '(?s)\r?\n?' + [regex]::Escape($script:MarkBegin) + '.*?' + [regex]::Escape($script:MarkEnd) + '\r?\n?', "`r`n")
    $block = "$($script:MarkBegin) (anfitrion)`r`n`"STEAM_0:${y}:${z}`" `"z`"`r`n`"STEAM_1:${y}:${z}`" `"z`"`r`n$($script:MarkEnd)"
    Write-Atomic $f ($txt.TrimEnd() + "`r`n`r`n" + $block + "`r`n")
}

function Test-HostAdmin($srv, [string]$steamId) {
    $f = Get-AdminPath $srv
    if (-not $steamId -or -not (Test-Path $f)) { return $false }
    $t = Get-Content $f -Raw
    ($t -like "*$($script:MarkBegin)*") -and ($t -like "*$($steamId.Substring(8))*")
}

# ---- plugin del Hub: se copia y se compila con el spcomp de SourceMod ----
function Install-HubPlugin($srv) {
    $sm = Join-Path $srv 'bms\addons\sourcemod'
    $spcomp = Join-Path $sm 'scripting\spcomp.exe'
    if (-not (Test-Path $spcomp)) { throw 'No encuentro spcomp.exe (SourceMod no esta instalado).' }
    $src = Join-Path $Root 'plugins\HubCmds.sp'
    $dst = Join-Path $sm 'scripting\hubcmds.sp'
    Copy-Item $src $dst -Force
    New-Item -ItemType Directory -Force (Join-Path $sm 'data') | Out-Null
    $out = Join-Path $sm 'plugins\hubcmds.smx'
    $res = & $spcomp $dst "-o$out" "-i$(Join-Path $sm 'scripting\include')" 2>&1 | Out-String
    if (-not (Test-Path $out) -or $res -match 'error \d+') { throw "No pude compilar el plugin del Hub: $res" }
    return $res
}

# ---- cola de ordenes al servidor (la lee el plugin cada 0.5 s) ----
function Get-DataDir($srv) { Join-Path $srv 'bms\addons\sourcemod\data' }

function Send-ServerCmd($srv, $lines, [switch]$Raw) {
    if (-not (Get-ServerProc $srv)) { throw 'El servidor no esta encendido.' }
    $clean = @($lines | ForEach-Object { "$_".Trim() } | Where-Object { $_ -and ($Raw -or $_ -notmatch '(?i)^(quit|exit|rcon_password|alias|bind|unbind|sm_rcon|sm\s+(plugins|exts)\s+unload|meta\s)') })
    if ($clean.Count -eq 0) { throw 'Sin comandos.' }
    if ($clean.Count -gt 40) { throw 'Demasiados comandos.' }
    foreach ($c in $clean) { if ($c.Length -gt 240) { throw 'Comando demasiado largo.' } }
    $id = [guid]::NewGuid().ToString('N').Substring(0, 8)
    $dir = Get-DataDir $srv
    New-Item -ItemType Directory -Force $dir | Out-Null
    Write-Atomic (Join-Path $dir 'hubcmd.txt') ("#id $id`r`n" + ($clean -join "`r`n") + "`r`n")
    Log ("cmd $id " + ($clean -join ' | '))
    return $id
}

function Test-CmdAck($srv, [string]$id) {
    $f = Join-Path (Get-DataDir $srv) 'hubcmd.ack'
    if (-not (Test-Path $f)) { return $false }
    try { return ((Get-Content $f -Raw -ErrorAction Stop).Trim() -eq $id) } catch { return $false }
}

# Estado que escribe el plugin cada 2 s: mapa, jugadores...
function Get-ServerState($srv) {
    $f = Join-Path (Get-DataDir $srv) 'hubstate.txt'
    if (-not (Test-Path $f)) { return $null }
    $age = ((Get-Date) - (Get-Item $f).LastWriteTime).TotalSeconds
    if ($age -gt 10) { return $null }
    try {
        $fs = [IO.File]::Open($f, 'Open', 'Read', 'ReadWrite')
        try { $t = (New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8)).ReadToEnd() } finally { $fs.Close() }
    } catch { return $null }
    $o = @{}
    foreach ($l in ($t -split "`r?`n")) { $i = $l.IndexOf('='); if ($i -gt 0) { $o[$l.Substring(0, $i)] = $l.Substring($i + 1) } }
    if (-not $o.ContainsKey('time')) { return $null }   # el plugin escribe 'time' al final: sin el, el archivo esta a medias
    $names = @(); if ($o.names) { $names = @($o.names -split ';' | Where-Object { $_ }) }
    return @{ map = $o.map; players = [int]$o.players; max = [int]$o.max; names = $names; coop = ($o.coop -eq '1') }
}

# ================= salud, reparacion, diagnostico =================
function New-Check($id, $level, $label, $detail) { @{ id = $id; level = $level; label = $label; detail = $detail } }

function Get-Health($client, $srv, $user, [string]$steamId) {
    $items = @()
    if ($client) { $items += New-Check 'client' 'ok' 'Black Mesa encontrado' $client } else { $items += New-Check 'client' 'bad' 'No encuentro Black Mesa' 'Instálalo desde Steam.' }
    if ($srv) { $items += New-Check 'server' 'ok' 'Servidor dedicado encontrado' $srv }
    else { $items += New-Check 'server' 'bad' 'Falta Black Mesa Dedicated Server' 'Es gratis: en Steam busca "Black Mesa Dedicated Server" (herramientas) e instálalo.'; return $items }
    if (Get-Process -Name steam -ErrorAction SilentlyContinue) { $items += New-Check 'steam' 'ok' 'Steam abierto' '' } else { $items += New-Check 'steam' 'bad' 'Steam está cerrado' '' }
    if ($user) { $items += New-Check 'user' 'ok' "Cuenta detectada: $($user.name)" $user.steamId } else { $items += New-Check 'user' 'warn' 'No detecté tu cuenta de Steam' '' }
    foreach ($c in (Get-Components $srv)) {
        if ($c.ok) { $items += New-Check $c.id 'ok' "$($c.name) instalado" '' } else { $items += New-Check $c.id 'bad' "Falta $($c.name)" $c.detail }
    }
    if (Test-SrcCoopBroken $srv) { $items += New-Check 'srccoopfix' 'bad' 'SourceCoop 1.6 se cae con la actualización de Black Mesa del 16-nov' 'Pulsa Reparar todo: aplica el arreglo oficial (gamedata del PR #375).' }
    if (Test-ServerCfg $srv) { $items += New-Check 'cfg' 'ok' 'Reglas del servidor escritas' 'server.cfg' } else { $items += New-Check 'cfg' 'warn' 'Aún no hay reglas escritas' 'Se crean al iniciar la primera partida.' }
    if (Test-Path (Join-Path $srv 'bms\addons\sourcemod\plugins\hubcmds.smx')) {
        if (Test-HostAdmin $srv $steamId) { $items += New-Check 'admin' 'ok' 'Eres el anfitrión (comandos de chat)' 'admins_simple.ini' } else { $items += New-Check 'admin' 'warn' 'Falta marcarte como anfitrión' 'Se hace al iniciar o con Reparar todo.' }
    }
    if (Get-ServerProc $srv) {
        $stt = Get-ServerState $srv
        if ($stt -and -not $stt.coop) { $items += New-Check 'coop' 'bad' 'SourceCoop no cargó en el servidor' 'Mira el diagnóstico: suele ser una versión de SourceMod incompatible. Reinstala desde Mods → Instalar lo que falta.' }
        if ($stt) { $items += New-Check 'plugin' 'ok' 'Servidor encendido y respondiendo' '' } else { $items += New-Check 'plugin' 'bad' 'El servidor está encendido pero no responde al Hub' 'Reinícialo con Detener servidor e Iniciar partida.' }
    }
    return $items
}

function Get-Diag($client, $srv, $user, [string]$steamId) {
    $L = New-Object System.Collections.Generic.List[string]
    $L.Add("Black Mesa Hub v$Version")
    $L.Add("Fecha: $(Get-Date -Format s)")
    $L.Add("Windows: $([Environment]::OSVersion.VersionString) | PowerShell $($PSVersionTable.PSVersion)")
    $steam = 'cerrado'; if (Get-Process -Name steam -ErrorAction SilentlyContinue) { $steam = 'abierto' }
    $L.Add("Cliente: $client | Servidor: $srv | Steam: $steam")
    $L.Add("Juego abierto: $([bool](Get-ClientProc)) | Servidor encendido: $([bool](Get-ServerProc $srv))")
    if ($user) { $L.Add("Cuenta: $($user.name) $($user.steamId)") }
    $L.Add('--- Salud')
    foreach ($i in (Get-Health $client $srv $user $steamId)) { $L.Add(("[{0}] {1} {2}" -f $i.level, $i.label, $i.detail).Trim()) }
    $L.Add('--- hub.log (ultimas 25 lineas)')
    if (Test-Path $LogFile) { foreach ($x in (Get-Content $LogFile -Tail 25)) { $L.Add($x) } }
    if ($srv) {
        $con = Join-Path $srv 'bms\console.log'
        if (Test-Path $con) { $L.Add('--- consola del servidor (ultimas 25 lineas)'); foreach ($x in (Get-Content $con -Tail 25 -ErrorAction SilentlyContinue)) { $L.Add($x) } }
        $el = Get-ChildItem (Join-Path $srv 'bms\addons\sourcemod\logs') -Filter 'errors_*.log' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($el) { $L.Add("--- errores de SourceMod ($($el.Name), ultimas 15 lineas)"); foreach ($x in (Get-Content $el.FullName -Tail 15)) { $L.Add($x) } }
    }
    return ($L -join "`r`n")
}

# Quita lo que el Hub escribio en el servidor (no desinstala Metamod/SourceMod/SourceCoop)
function Undo-All($srv) {
    $cfg = Get-CfgPath $srv
    foreach ($f in $cfg, (Get-AdminPath $srv)) {
        if (Test-Path $f) {
            $t = Get-Content $f -Raw
            $t = [regex]::Replace($t, '(?s)\r?\n?' + [regex]::Escape($script:MarkBegin) + '.*?' + [regex]::Escape($script:MarkEnd) + '\r?\n?', "`r`n")
            Write-Atomic $f ($t.TrimEnd() + "`r`n")
        }
    }
    $sm = Join-Path $srv 'bms\addons\sourcemod'
    foreach ($f in 'plugins\hubcmds.smx', 'scripting\hubcmds.sp', 'data\hubcmd.txt', 'data\hubcmd.ack', 'data\hubstate.txt') { Remove-Item (Join-Path $sm $f) -Force -ErrorAction SilentlyContinue }
}
