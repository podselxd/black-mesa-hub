# Black Mesa Hub

Lanzador para jugar la **campaña de Black Mesa en cooperativo** con amigos: creas la partida, compartes una invitación (IP) y entran. Se apoya en [SourceCoop](https://github.com/ampreeT/SourceCoop), el mod que convierte la campaña en co-op, y en el servidor dedicado de Black Mesa.

**[⬇ Descargar](https://github.com/podselxd/black-mesa-hub/releases)** (`BlackMesaHub.exe`, un solo archivo)

> Windows puede avisar al abrirlo (no está firmado con certificado de pago): **Más información → Ejecutar de todas formas**.

## ⚠ Estado actual

Black Mesa se actualizó el 16 de noviembre de 2026 y **rompió SourceCoop 1.6** ([issue #374](https://github.com/ampreeT/SourceCoop/issues/374)). Con el arreglo en revisión ([PR #375](https://github.com/ampreeT/SourceCoop/pull/375)), que el Hub aplica solo, el servidor ya no se cae y se entra a él, pero al pulsar *Spawn* el juego se queda en «Spawning…». Hasta que SourceCoop publique una versión nueva no se puede jugar la campaña.

El Hub consulta GitHub al abrirse: cuando salga una versión nueva de SourceCoop muestra una tarjeta «Hay una versión nueva» con un botón **Actualizar SourceCoop**.

Detalles y lo pendiente de probar: [NOTAS.md](NOTAS.md).

## Qué hace

- **Crear partida** — eliges capítulo y pulsas *Iniciar partida*: el Hub arranca el servidor dedicado, abre Black Mesa y entra por ti. Muestra quién está dentro.
- **Invitación** — copia `connect IP:puerto` (con contraseña si la pones). Detecta Tailscale, otras VPN (Radmin, Hamachi…), la red local, y con un botón consulta tu IP pública. Si el puerto 27015 está ocupado usa el siguiente libre.
- **Unirme** — pegas la invitación (o la IP) de tu amigo y entras.
- **Reglas** — trucos, fuego amigo, supervivencia (On/Off), reaparición, jugadores máximos, contraseña, nombre del servidor, pantalla, gráficos y comandos extra.
- **Comandos** — comandos de chat y botones que se mandan al servidor.
- **Mods** — enlaces útiles (Workshop, SourceCoop, SourceMod) y los componentes esenciales, que no se pueden borrar desde el Hub.
- **Ajustes** — salud del Hub, *Reparar todo*, deshacer cambios en el servidor y copiar diagnóstico.

## Requisitos

- Windows 10/11
- Steam con **Black Mesa** y **Black Mesa Dedicated Server** (gratis, en *Herramientas*)

La primera vez, *Instalar ahora* descarga Metamod:Source y SourceMod (de alliedmods.net) y SourceCoop (de su GitHub) dentro de la carpeta `bms\addons` del servidor dedicado. Tu Black Mesa normal no se toca.

## Cómo jugar

**Anfitrión:** Steam abierto → `BlackMesaHub.exe` → *Crear partida* → capítulo → **Iniciar partida**. Pasa la invitación a tus amigos.

**Invitados:** Steam abierto → `BlackMesaHub.exe` → *Unirme* → pega la invitación.

Para que entren por internet necesitan estar en tu red (Tailscale o una VPN) o que abras el puerto UDP 27015 hacia tu PC y uses tu IP pública. Si el mapa es del Workshop, deben suscribirse antes.

## Comandos de chat

Los instala un plugin de SourceMod (`plugins/HubCmds.sp`), que el Hub compila al instalar.

| Para todos | |
|---|---|
| `/tp <nombre>` · `/tp lista` | Ir con otra persona / ver la lista |
| `/s` · `/p` | Guardar la posición / volver a ella |
| `/kill` | Morir |
| `/jugadores` | Quién está dentro |
| `/ayuda` | Lista de comandos |

| Solo el anfitrión | |
|---|---|
| `/god` · `/noclip` · `/notarget` | Alternar inmortalidad, atravesar paredes, enemigos te ignoran |
| `/armas` | Todas las armas |
| `/give <objeto>` (`/dar`) | Un arma o ítem (`escopeta`, `mp5`, `botiquin`, `bateria`…) |
| `/map <mapa>` (`/mapa`) | Cambiar de mapa (solo si existe) |
| `/restart` (`/reiniciar`) | Reiniciar el mapa |
| `/gravedad baja\|normal` | Gravedad |
| `/velocidad rapida\|normal` | Velocidad |
| `/respawn <0-60>` | Segundos de reaparición |

SourceCoop trae además los suyos: `/coopmenu`, `/skipintro`, `/restartmap`, `/changemap`, `/survival` y `/stuck`.

## Seguridad y privacidad

- El servidor del Hub solo escucha en `127.0.0.1` y exige un token. No hay telemetría.
- Las órdenes al servidor de juego no usan RCON: van por un archivo que lee el plugin, así que no hay nada extra expuesto a internet.
- Internet solo se usa para: bajar los componentes al instalar, preguntar a GitHub la última versión de SourceCoop, y —solo si pulsas **Mi IP pública**— preguntar tu IP a api.ipify.org.
- Los zip se extraen sin salirse de su carpeta y no se aceptan `.bat`, `.ps1`, `.vbs`, etc.
- Se quita el *Updater* de SourceMod: sustituía el gamedata por el de otra versión y SourceCoop dejaba de funcionar.

## Estructura

| Ruta | Qué es |
|---|---|
| `hub.ps1`, `lib.ps1`, `install.ps1` | El Hub (PowerShell 5.1, servidor local `HttpListener`) y el instalador |
| `web/index.html` | La interfaz (se abre en una ventana de Edge `--app`) |
| `plugins/HubCmds.sp` | Plugin de SourceMod: comandos de chat y cola de órdenes |
| `build/` | Compilación del `.exe` (`Stub.cs`, `build.ps1`) |

## Compilarlo

```powershell
build\build.ps1          # comprobaciones + Compartir\BlackMesaHub.exe
build\build.ps1 -Smoke   # además arranca el Hub desde una copia temporal y prueba su API
```

Los `.ps1` deben guardarse como UTF-8 **con BOM** (PowerShell 5.1 los lee como ANSI si no); `build.ps1` lo comprueba.

## Licencia

[MIT](LICENSE). Black Mesa pertenece a Crowbar Collective; este proyecto no está afiliado a ellos ni a SourceCoop.
