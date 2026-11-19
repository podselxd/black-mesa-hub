param([Parameter(Mandatory)][string]$Srv, [string]$SteamId = '', [switch]$Update)
# install.ps1 - instala en el servidor dedicado de Black Mesa: Metamod:Source, SourceMod, SourceCoop y el plugin del Hub.
# Lo lanza el Hub sin consola; escribe su avance en install.json. Es idempotente: solo baja lo que falta.
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Utf8 = New-Object System.Text.UTF8Encoding($false)
$LogFile = Join-Path $Root 'hub.log'
$Version = '0.0.0'; if (Test-Path (Join-Path $Root 'version.txt')) { $Version = (Get-Content (Join-Path $Root 'version.txt') -Raw).Trim() }
function Log($m) { try { Add-Content -Path $LogFile -Value ("{0} install: {1}" -f (Get-Date -Format s), $m) } catch {} }
. (Join-Path $Root 'lib.ps1')
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.IO.Compression.FileSystem

$StatusFile = Join-Path $Root 'install.json'
$steps = @(
    @{ k = 'metamod'; label = 'Metamod:Source'; done = $false }
    @{ k = 'sourcemod'; label = 'SourceMod'; done = $false }
    @{ k = 'sourcecoop'; label = 'SourceCoop (campaña cooperativa)'; done = $false }
    @{ k = 'hubcmds'; label = 'Comandos del Hub'; done = $false }
)
function Save-Status([string]$err = '', [bool]$finished = $false) {
    $cur = ($steps | Where-Object { -not $_.done } | Select-Object -First 1)
    Write-Atomic $StatusFile (@{ steps = $steps; error = $err; finished = $finished; current = $(if ($cur) { $cur.k } else { '' }); at = (Get-Date -Format s) } | ConvertTo-Json -Depth 5)
}
function Complete-Step([string]$k) { ($steps | Where-Object { $_.k -eq $k }).done = $true; Save-Status }

$Bms = Join-Path $Srv 'bms'
$dl = Join-Path $Root 'cache\dl'
New-Item -ItemType Directory -Force $dl | Out-Null

function Get-Web([string]$url) {
    $wc = New-Object Net.WebClient
    $wc.Headers['User-Agent'] = 'BlackMesaHub'
    return $wc
}

function Get-Zip([string]$url, [string]$name) {
    $out = Join-Path $dl $name
    Remove-Item $out -Force -ErrorAction SilentlyContinue
    (Get-Web $url).DownloadFile($url, $out)
    if ((Get-Item $out).Length -lt 100KB) { throw "La descarga de $name salio demasiado pequena." }
    return $out
}

# Descomprime dentro de $dest sin permitir salirse de esa carpeta (zip-slip). Los .cfg/.ini del usuario ya existentes no se pisan.
function Expand-Safe([string]$zip, [string]$dest) {
    $root = [IO.Path]::GetFullPath($dest).TrimEnd('\') + '\'
    $za = [IO.Compression.ZipFile]::OpenRead($zip)
    try {
        foreach ($e in $za.Entries) {
            if (-not $e.Name) { continue }
            $target = [IO.Path]::GetFullPath((Join-Path $dest $e.FullName))
            if (-not $target.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { throw "Entrada fuera de la carpeta en el zip: $($e.FullName)" }
            if ($e.FullName -match '(?i)\.(bat|cmd|ps1|vbs|msi|scr|lnk)$') { throw "El zip trae un archivo no permitido: $($e.FullName)" }
            $keepUser = ($e.FullName -match '(?i)^addons/sourcemod/(configs|data)/') -and (Test-Path $target)
            if ($keepUser) { continue }
            New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
            [IO.Compression.ZipFileExtensions]::ExtractToFile($e, $target, $true)
        }
    }
    finally { $za.Dispose() }
}

function Read-Latest([string]$url) {
    $wc = Get-Web $url
    return $Utf8.GetString($wc.DownloadData($url)).Trim()
}

try {
    Save-Status
    $comp = @{}; foreach ($c in (Get-Components $Srv)) { $comp[$c.id] = $c.ok }

    if (-not $comp.metamod) {
        $n = Read-Latest 'https://mms.alliedmods.net/mmsdrop/1.12/mmsource-latest-windows'
        if ($n -notmatch '^mmsource-[\d\.]+-git\d+-windows\.zip$') { throw "Nombre inesperado de Metamod: $n" }
        Log "bajando $n"
        Expand-Safe (Get-Zip "https://mms.alliedmods.net/mmsdrop/1.12/$n" $n) $Bms
    }
    Complete-Step 'metamod'

    if (-not $comp.sourcemod) {
        # SourceCoop avisa de que las versiones nuevas de SourceMod rompen sus detours (con la 7260 SourceCoop no carga: "Entity Outputs are disabled").
        # La 7228 es la mas antigua que sigue publicada y funciona; si algun dia la retiran, se usa la siguiente mas antigua.
        $page = $Utf8.GetString((Get-Web 'https://sm.alliedmods.net/smdrop/1.12/').DownloadData('https://sm.alliedmods.net/smdrop/1.12/'))
        $names = @([regex]::Matches($page, 'sourcemod-1\.12\.0-git(\d+)-windows\.zip') | ForEach-Object { [int]$_.Groups[1].Value } | Sort-Object -Unique)
        $pick = @($names | Where-Object { $_ -ge 7228 }) | Select-Object -First 1
        if (-not $pick) { throw 'No encuentro una version de SourceMod compatible con SourceCoop.' }
        $n = "sourcemod-1.12.0-git$pick-windows.zip"
        Log "bajando $n"
        Expand-Safe (Get-Zip "https://sm.alliedmods.net/smdrop/1.12/$n" $n) $Bms
        Disable-SmUpdater $Srv
    }
    Complete-Step 'sourcemod'

    if ($Update -or -not $comp.sourcecoop) {
        $latest = $null
        try { $latest = Get-SrcCoopLatest } catch { Log "no pude consultar la ultima version de SourceCoop: $($_.Exception.Message)" }
        $url = $null; $tag = 'v1.6'
        if ($latest) { $url = $latest.url; $tag = $latest.tag }
        if (-not $url) { $url = 'https://github.com/ampreeT/SourceCoop/releases/download/v1.6/SourceCoop-1.6-bms.zip' }
        if ($url -notmatch '^https://github\.com/ampreeT/SourceCoop/releases/download/') { throw 'Direccion inesperada de SourceCoop.' }
        Log "bajando $url"
        Expand-Safe (Get-Zip $url 'sourcecoop-bms.zip') $Bms
        Set-SrcCoopTag $tag
    }
    try { if (Install-SrcCoopFix $Srv) { Log 'aplicado el arreglo de gamedata de SourceCoop (PR 375)' } } catch { Log "no pude aplicar el arreglo de SourceCoop: $($_.Exception.Message)" }
    Complete-Step 'sourcecoop'

    Install-HubPlugin $Srv | Out-Null
    if ($SteamId) { Set-HostAdmin $Srv $SteamId }
    Complete-Step 'hubcmds'
    Save-Status '' $true
    Log 'instalacion terminada'
}
catch {
    Log "fallo: $($_.Exception.Message)"
    Save-Status $_.Exception.Message $true
    exit 1
}
