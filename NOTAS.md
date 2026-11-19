# Black Mesa Hub: estado (19-nov-2026)

**Abrir:** `BlackMesaHub.exe` (o `Abrir Black Mesa Hub.vbs` desde el código), con Steam abierto.

## Qué funciona (probado)
- Instala Metamod, SourceMod y SourceCoop en el servidor dedicado y compila el plugin de comandos (`plugins\HubCmds.sp`).
- Arranca el servidor, abre Black Mesa, te mete dentro y **spawneas en la campaña**.
- Invitación con IP:puerto (Tailscale / VPN / red local / IP pública). Si el 27015 está ocupado usa el siguiente puerto libre.
- Botones de la pestaña Comandos (se mandan al servidor por una cola de archivo que lee el plugin).

## Pendiente de probar
1. Comandos de chat dentro de la partida: `/tp`, `/s`, `/p`, `/kill`, `/jugadores`, `/ayuda`; y los de anfitrión `/god`, `/noclip`, `/notarget`, `/armas`, `/give`, `/map`, `/restart`, `/gravedad`, `/velocidad`, `/respawn`.
2. Botones de Comandos y Reglas (fuego amigo, supervivencia, reaparición).
3. Un amigo entrando por IP.
4. El reinicio automático del servidor tras la primera instalación (ver abajo).

## Cosas aprendidas
- La actualización de Black Mesa del 16-nov rompió SourceCoop 1.6 (issue #374). El arreglo es un archivo de datos (`gamedata/srccoop.games.txt`, PR #375) y el Hub lo aplica solo si el instalado es el de la v1.6.
- SourceMod necesita su Updater: baja el gamedata nuevo de Black Mesa y pide reiniciar. Con las builds antiguas o sin el Updater, SourceCoop se cae al entrar el primer jugador o Spawn se queda en «Spawning…». El Hub reinicia el servidor una vez cuando detecta ese aviso.
- El servidor no contesta a 127.0.0.1: el propio PC entra por su IP de red.
- El SteamID en `hub_do` va entre comillas (la consola de Source parte los tokens en los dos puntos).
- No se cierra el servidor a la fuerza si se puede evitar: Steam se confunde con el estado del juego.