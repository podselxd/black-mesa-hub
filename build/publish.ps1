param([switch]$Release, [string]$Repo = 'podselxd/black-mesa-hub')
# publish.ps1 - sube el codigo al repositorio de GitHub (copia de trabajo en ~\.blackmesahub\repo) y, con -Release, crea la release con el .exe.
$ErrorActionPreference = 'Stop'
$Hub = Split-Path -Parent $PSScriptRoot
$work = Join-Path $env:USERPROFILE '.blackmesahub\repo'
$version = (Get-Content (Join-Path $Hub 'version.txt') -Raw).Trim()
$utf8 = New-Object Text.UTF8Encoding($false)
$files = 'hub.ps1', 'lib.ps1', 'install.ps1', 'version.txt', 'changelog.json', 'README.md', 'NOTAS.md', 'LICENSE', 'Abrir Black Mesa Hub.vbs'

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw 'Falta GitHub CLI (gh).' }
New-Item -ItemType Directory -Force $work | Out-Null
foreach ($f in $files) { Copy-Item (Join-Path $Hub $f) (Join-Path $work $f) -Force }
foreach ($d in 'web', 'plugins') {
    $dst = Join-Path $work $d
    if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
    Copy-Item (Join-Path $Hub $d) $dst -Recurse -Force
}
$bd = Join-Path $work 'build'
if (Test-Path $bd) { Remove-Item $bd -Recurse -Force }
New-Item -ItemType Directory $bd | Out-Null
Copy-Item (Join-Path $Hub 'build\*') $bd -Force -Include '*.ps1', '*.cs', '*.ico'
[IO.File]::WriteAllText((Join-Path $work '.gitignore'), "cache/`nhub.log`ninstall.json`nsettings.json`nrun.json`nsrccoop.json`n.browser-profile/`nCompartir/`n*.hubtmp`n*.hubold`n", $utf8)
[IO.File]::WriteAllText((Join-Path $work '.gitattributes'), "* -text`n", $utf8)   # sin conversion CRLF/LF: los .ps1 conservan su BOM

$login = (& gh api user --jq .login).Trim(); $uid = (& gh api user --jq .id).Trim()
$email = "$uid+$login@users.noreply.github.com"   # el correo real no se publica
Push-Location $work
try {
    $ErrorActionPreference = 'Continue'   # los avisos de git/gh por stderr no deben abortar el script
    if (-not (Test-Path (Join-Path $work '.git'))) { & git init -b main 2>&1 | Out-Null }
    & git config core.autocrlf false
    & git add -A 2>&1 | Out-Null
    $msg = "Black Mesa Hub v$version`n`nCo-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
    & git -c "user.name=$login" -c "user.email=$email" commit -m $msg 2>&1 | Out-Null
    $has = @(& git remote)
    & gh repo view $Repo 2>&1 | Out-Null
    $exists = ($LASTEXITCODE -eq 0)
    if (-not $exists) { & gh repo create $Repo --public --source . --remote origin --push 2>&1 | Out-Null }
    else {
        if (-not ($has -contains 'origin')) { & git remote add origin "https://github.com/$Repo.git" }
        & git push -u origin main 2>&1 | Out-Null
    }
    if ($LASTEXITCODE -ne 0) { throw 'git push / gh repo create fallo.' }
    # la descripcion va como JSON UTF-8 desde archivo: por argumento, PowerShell 5.1 estropea los acentos
    $df = Join-Path ([IO.Path]::GetTempPath()) 'bmhub-repo-desc.json'
    [IO.File]::WriteAllText($df, '{"description":"Lanzador para jugar la campaña de Black Mesa en cooperativo con amigos (SourceCoop): invitación, reglas y comandos de chat."}', $utf8)
    & gh api -X PATCH "repos/$Repo" --input $df 2>&1 | Out-Null
    Remove-Item $df -Force -ErrorAction SilentlyContinue
    & gh repo edit $Repo --add-topic black-mesa --add-topic sourcecoop --add-topic sourcemod --add-topic launcher --add-topic powershell 2>&1 | Out-Null
    $sha = (& git rev-parse HEAD).Trim()
    $ErrorActionPreference = 'Stop'
}
finally { Pop-Location }
Write-Host "Codigo subido (commit $sha)  ->  https://github.com/$Repo" -ForegroundColor Green

if ($Release) {
    $exe = Join-Path $Hub 'Compartir\BlackMesaHub.exe'; $zip = Join-Path $Hub 'Compartir\BlackMesaHub.zip'
    foreach ($p in $exe, $zip) { if (-not (Test-Path $p)) { throw "Falta $p : ejecuta build\build.ps1." } }
    if ((Get-Content (Join-Path $Hub 'Compartir\LEEME.txt') -Raw) -notmatch [regex]::Escape("v$version")) { throw "Compartir\ no es de la v$version : ejecuta build\build.ps1." }
    $cl = (Get-Content (Join-Path $Hub 'changelog.json') -Raw -Encoding UTF8 | ConvertFrom-Json) | Where-Object { $_.version -eq $version } | Select-Object -First 1
    $notes = "## Black Mesa Hub v$version`n`n" + (($cl.notes | ForEach-Object { "- $_" }) -join "`n") + "`n`nDescarga **BlackMesaHub.exe** y ejecútalo con Steam abierto (Windows puede avisar: *Más información → Ejecutar de todas formas*)."
    $nf = Join-Path ([IO.Path]::GetTempPath()) "bmhub-notes-$version.md"; [IO.File]::WriteAllText($nf, $notes, $utf8)
    $ErrorActionPreference = 'Continue'
    & gh release view "v$version" --repo $Repo 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        & gh release upload "v$version" $exe $zip --clobber --repo $Repo 2>&1 | Out-Null
        & gh release edit "v$version" --notes-file $nf --repo $Repo 2>&1 | Out-Null
    }
    else { & gh release create "v$version" $exe $zip --title "Black Mesa Hub v$version" --notes-file $nf --latest --target $sha --repo $Repo 2>&1 | Out-Null }
    if ($LASTEXITCODE -ne 0) { throw 'gh release fallo.' }
    Remove-Item $nf -Force -ErrorAction SilentlyContinue
    Write-Host "Release v$version  ->  https://github.com/$Repo/releases" -ForegroundColor Green
}
