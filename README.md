# Black Mesa Hub

Lanzador para jugar la **campaña de Black Mesa en cooperativo** con amigos: creas la partida, compartes una invitación (IP) y entran. Se apoya en [SourceCoop](https://github.com/ampreeT/SourceCoop), el mod que convierte la campaña en co-op, y en el servidor dedicado de Black Mesa.

**[⬇ Descargar](https://github.com/podselxd/black-mesa-hub/releases)** (`BlackMesaHub.exe`, un solo archivo)

> Windows puede avisar al abrirlo (no está firmado con certificado de pago): **Más información → Ejecutar de todas formas**.

## Estado

La campaña **ya se puede jugar** (probado el 18-nov-2026 con SourceMod 7260, SourceCoop 1.6 y el archivo de datos arreglado). La actualización de Black Mesa del 16 de noviembre había roto SourceCoop 1.6 ([issue #374](https://github.com/ampreeT/SourceCoop/issues/374)); su autor la arregló en la rama principal ([PR #375](https://github.com/ampreeT/SourceCoop/pull/375)) y pasó a recomendar la última build de SourceMod. Como todavía no hay una versión numerada nueva de SourceCoop, el Hub instala la v1.6 y le aplica ese archivo de datos (de un commit fijo, comprobando su SHA-256). Cuando salga una versión nueva, el Hub la ofrece con un botón **Actualizar SourceCoop**.

Lo que falta por probar a fondo: los comandos de chat dentro de una partida y entrar con un amigo. Detalles en [NOTAS.md](NOTAS.md).
## Qué hace

- **Crear partida** — eliges capítulo y pulsas *Iniciar partida*: el Hub arranca el servidor dedicado (sin ventana de consola), abre Black Mesa sin su consola y entras **directo a la partida**, sin pasar por el panel Spawn/Spectate. Muestra quién está dentro.
- **Invitación** — copia `connect IP:puerto` (con contraseña si la pones). Detecta Tailscale, otras VPN (Radmin, Hamachi…), la red local, y con un botón consulta tu IP pública. Si el puerto 27015 está ocupado usa el siguiente libre.
- **Radmin VPN** — es lo que une tu PC con la de tus amigos sin abrir puertos del router. El Hub lo exige para jugar, avisa si falta (con el botón para descargarlo) y lo abre solo en segundo plano cada vez que lo usas. La primera vez pregunta si es tu primera vez jugando y enseña un **tutorial** (para el anfitrión y para el que se une). La tarjeta «Radmin VPN» guarda el nombre y la contraseña de tu red y copia una **guía para amigos** lista para pegar en Discord. Se puede desactivar en Reglas → *Usar Radmin VPN*.
- **Invitar por Steam** — copia la invitación y abre tu lista de amigos de Steam para pegarla en su chat. Además, el anfitrión entra al servidor por la misma dirección que eliges para la invitación: si tus amigos pueden alcanzarla (VPN, Tailscale o IP pública) y no hay contraseña, Steam puede mostrarles «Unirse a la partida» en tu perfil (no lo he podido comprobar).
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

Para que entren por internet, todos usan **Radmin VPN** y están en la misma red de Radmin (el tutorial del Hub lo explica paso a paso). Alternativas: Tailscale u otra VPN, o abrir el puerto UDP 27015 en tu router y usar tu IP pública. Si el mapa es del Workshop, deben suscribirse antes.

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
- SourceMod trae su *Updater*, que baja datos nuevos de Black Mesa al arrancar el servidor. Tras instalar, el Hub reinicia el servidor una vez para aplicarlos (sin eso, SourceCoop se cae o no deja spawnear).

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
