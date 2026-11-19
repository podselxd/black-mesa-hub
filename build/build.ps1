param([switch]$Smoke)
# build.ps1 - revisa lo estatico antes de compilar. Si algo falla, no se genera el .exe.
# -Smoke ademas arranca el Hub desde una copia temporal y le pregunta por su API (el .exe en si no se ejecuta).
$ErrorActionPreference = 'Stop'
$Hub = Split-Path -Parent $PSScriptRoot
$Share = Join-Path $Hub 'Compartir'
$script:fail = 0

function Check($name, [scriptblock]$test) {
    try {
        $msg = & $test
        if ($msg -is [string] -and $msg.StartsWith('SKIP:')) { Write-Host ("  [--] {0}  ({1})" -f $name, $msg.Substring(5).Trim()) -ForegroundColor Yellow }
        else { Write-Host ("  [ok] {0}" -f $name) -ForegroundColor Green }
    }
    catch { $script:fail++; Write-Host ("  [XX] {0}`n       {1}" -f $name, $_.Exception.Message) -ForegroundColor Red }
}

$version = (Get-Content (Join-Path $Hub 'version.txt') -Raw).Trim()
Write-Host "Black Mesa Hub v$version - comprobaciones" -ForegroundColor Cyan

Check 'PowerShell: hub.ps1, lib.ps1 e install.ps1 compilan' {
    foreach ($f in 'hub.ps1', 'lib.ps1', 'install.ps1') {
        $errs = $null
        [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $Hub $f), [ref]$null, [ref]$errs)
        if ($errs.Count) { throw "$f linea $($errs[0].Extent.StartLineNumber): $($errs[0].Message)" }
        # PowerShell 5.1 lee sin BOM como ANSI: los acentos y flechas de los textos romperian las comillas
        $b = [IO.File]::ReadAllBytes((Join-Path $Hub $f))
        if (-not ($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)) { throw "$f debe guardarse como UTF-8 con BOM" }
    }
}

Check 'JavaScript de la interfaz compila' {
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) { return 'SKIP: node no esta instalado' }
    $html = Get-Content (Join-Path $Hub 'web\index.html') -Raw -Encoding UTF8
    $js = ([regex]::Matches($html, '(?s)<script>(.*?)</script>') | ForEach-Object { $_.Groups[1].Value }) -join "`n"
    if (-not $js) { throw 'No encontre el <script>.' }
    $tmp = Join-Path $env:TEMP 'bmhub_build_check.js'
    [IO.File]::WriteAllText($tmp, $js)
    $out = & node --check $tmp 2>&1
    if ($LASTEXITCODE -ne 0) { throw ($out -join ' ') }
}

Check 'HTML: el marcador __TOKEN__ aparece una sola vez' {
    $html = Get-Content (Join-Path $Hub 'web\index.html') -Raw -Encoding UTF8
    $n = ([regex]::Matches($html, '__TOKEN__')).Count
    if ($n -ne 1) { throw "aparece $n veces" }
}

Check 'Plugin HubCmds.sp: llaves y parentesis balanceados' {
    $t = Get-Content (Join-Path $Hub 'plugins\HubCmds.sp') -Raw
    $t = [regex]::Replace($t, '(?s)/\*.*?\*/|//[^\r\n]*|"(\\.|[^"\\])*"', '')
    foreach ($pair in @(@('{', '}'), @('(', ')'))) {
        $a = ($t.ToCharArray() | Where-Object { $_ -eq $pair[0] }).Count
        $b = ($t.ToCharArray() | Where-Object { $_ -eq $pair[1] }).Count
        if ($a -ne $b) { throw "$($pair[0]) x$a vs $($pair[1]) x$b" }
    }
}

Check 'Version: formato x.y.z y coincide con la primera novedad' {
    if ($version -notmatch '^\d+\.\d+\.\d+$') { throw "version invalida: $version" }
    $cl = @(); foreach ($e in (Get-Content (Join-Path $Hub 'changelog.json') -Raw -Encoding UTF8 | ConvertFrom-Json)) { $cl += $e }
    if ($cl.Count -eq 0) { throw 'changelog.json vacio' }
    if ($cl[0].version -ne $version) { throw "version.txt dice $version pero la primera novedad es $($cl[0].version)" }
    if (-not $cl[0].notes -or $cl[0].notes.Count -eq 0) { throw 'la version actual no tiene notas' }
}

if ($Smoke) {
    Check 'Prueba de humo: el Hub arranca y responde' {
        $tmp = Join-Path $env:TEMP ("bmhub-smoke-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory $tmp | Out-Null
        Copy-Item (Join-Path $Hub 'hub.ps1'), (Join-Path $Hub 'lib.ps1'), (Join-Path $Hub 'install.ps1'), (Join-Path $Hub 'version.txt'), (Join-Path $Hub 'changelog.json') $tmp
        Copy-Item (Join-Path $Hub 'web'), (Join-Path $Hub 'plugins') $tmp -Recurse
        $proc = Start-Process powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$tmp\hub.ps1`"", '-NoBrowser' -PassThru
        try {
            $run = Join-Path $tmp 'run.json'
            for ($i = 0; $i -lt 40 -and -not (Test-Path $run); $i++) { Start-Sleep -Milliseconds 250 }
            if (-not (Test-Path $run)) { throw 'El Hub no arranco en 10 s.' }
            $r = Get-Content $run -Raw | ConvertFrom-Json
            $h = @{ 'X-Hub' = $r.token }; $u = "http://127.0.0.1:$($r.port)"
            if ((Invoke-WebRequest "$u/" -UseBasicParsing).Content -match '__TOKEN__') { throw 'La pagina salio sin token.' }
            $st = Invoke-RestMethod "$u/api/state" -Headers $h
            foreach ($k in 'version', 'changelog', 'screen', 'steamRunning', 'chapters', 'components', 'port') { if ($null -eq $st.PSObject.Properties[$k]) { throw "/api/state no trae '$k'" } }
            if ($st.version -ne $version) { throw "el Hub dice v$($st.version) y deberia ser v$version" }
            $ou = Invoke-RestMethod "$u/api/openurl" -Headers $h -Method Post -Body '{"url":"https://evil.example/"}'
            if ($ou.ok) { throw 'openurl abrio un sitio que no esta en la lista' }
            $denied = $false; try { Invoke-RestMethod "$u/api/state" | Out-Null } catch { $denied = $true }
            if (-not $denied) { throw 'La API respondio sin token.' }
            Invoke-RestMethod "$u/api/quit" -Headers $h | Out-Null
        }
        finally {
            if (-not $proc.HasExited) { Start-Sleep -Seconds 1; if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } }
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
else { Write-Host '  [--] Prueba de humo omitida (usa -Smoke)' -ForegroundColor Yellow }

if ($script:fail -gt 0) { Write-Host "`n$($script:fail) comprobacion(es) fallaron: NO se genero el .exe." -ForegroundColor Red; exit 1 }

# ---- compilar ----
Write-Host "`nCompilando..." -ForegroundColor Cyan
$ico = Join-Path $PSScriptRoot 'hub.ico'
if (-not (Test-Path $ico)) { & (Join-Path $PSScriptRoot 'make-icon.ps1') -Out $ico | Out-Null }
New-Item -ItemType Directory -Force $Share | Out-Null
$exe = Join-Path $Share 'BlackMesaHub.exe'
$csc = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$res = @('hub.ps1,hub.ps1', 'lib.ps1,lib.ps1', 'install.ps1,install.ps1', 'version.txt,version.txt', 'changelog.json,changelog.json', 'web\index.html,web/index.html', 'plugins\HubCmds.sp,plugins/HubCmds.sp')
$args2 = @('/nologo', '/target:winexe', "/out:$exe", "/win32icon:$ico") + ($res | ForEach-Object { $p = $_ -split ','; "/resource:$(Join-Path $Hub $p[0]),$($p[1])" }) + (Join-Path $PSScriptRoot 'Stub.cs')
& $csc @args2
if ($LASTEXITCODE -ne 0) { Write-Host 'csc fallo.' -ForegroundColor Red; exit 1 }

@"
BLACK MESA HUB v$version
1. Instala "Black Mesa" y "Black Mesa Dedicated Server" (gratis, en Herramientas) desde Steam y deja Steam abierto.
2. Ejecuta BlackMesaHub.exe (Windows avisa: Mas informacion > Ejecutar de todas formas).
3. La primera vez pulsa "Instalar ahora" en Crear partida: baja Metamod, SourceMod y SourceCoop.
4. Si algo falla: Ajustes > Reparar todo.
"@ | Set-Content (Join-Path $Share 'LEEME.txt') -Encoding UTF8
Compress-Archive -Path $exe, (Join-Path $Share 'LEEME.txt') -DestinationPath (Join-Path $Share 'BlackMesaHub.zip') -Force

$sha = (Get-FileHash $exe -Algorithm SHA256).Hash.ToLower()
Write-Host ("`nListo: v{0}  {1} KB  sha256 {2}" -f $version, [int]((Get-Item $exe).Length / 1KB), $sha.Substring(0, 16)) -ForegroundColor Green
