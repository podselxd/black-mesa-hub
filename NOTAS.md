# Black Mesa Hub: estado (18-nov-2026)

**Abrir:** doble clic en `Abrir Black Mesa Hub.vbs` (con Steam abierto).

## Qué funciona
- Instala Metamod, SourceMod y SourceCoop en el servidor dedicado de Black Mesa y compila el plugin de comandos (`plugins\HubCmds.sp`).
- Arranca el servidor, abre Black Mesa, te mete dentro y muestra quién está en la sala.
- Invitación con IP:puerto (Tailscale / VPN / red local / IP pública). Si el 27015 está ocupado usa el siguiente puerto libre.
- Botones de la pestaña Comandos (se mandan al servidor por una cola de archivo que lee el plugin).

## Qué falta (bloqueo de fuera)
Black Mesa se actualizó el 16-nov y rompió SourceCoop 1.6 ([issue #374](https://github.com/ampreeT/SourceCoop/issues/374)).
El Hub aplica el gamedata del [PR #375](https://github.com/ampreeT/SourceCoop/pull/375) (commit fijo, SHA-256 comprobado):
con eso el servidor ya no se cae y entras, pero **Spawn se queda en «Spawning…»**.

El Hub consulta GitHub al abrirse. Cuando salga una release nueva de SourceCoop aparece en «Crear partida» una tarjeta
«Hay una versión nueva»: pulsa **Actualizar SourceCoop** (con el servidor detenido) y vuelve a probar.

## Pendiente de probar cuando haya arreglo
1. Iniciar partida → Spawn → que entres jugando en la campaña.
2. Comandos de chat: `/tp`, `/s`, `/p`, `/kill`, `/jugadores`, `/ayuda`; y los de anfitrión `/god`, `/noclip`, `/notarget`, `/armas`, `/give`, `/map`, `/restart`, `/gravedad`, `/velocidad`, `/respawn`.
3. Botones de Comandos y Reglas (fuego amigo, supervivencia, reaparición).
4. Un amigo entrando por IP.

## Cosas aprendidas
- SourceMod 7260 rompe SourceCoop: el instalador usa la build más antigua publicada (≥ 7228).
- Se quita `updater.ext.dll`: reemplaza el gamedata por el de otra versión.
- El servidor no contesta a 127.0.0.1: el propio PC entra por su IP de red.
- El SteamID en `hub_do` va entre comillas (la consola de Source parte los tokens en los dos puntos).
- No se cierra el servidor a la fuerza si se puede evitar: Steam se confunde con el estado del juego.

Sin publicar, sin `.exe` y sin auto-actualización del Hub.
