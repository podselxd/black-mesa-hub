// HubCmds.sp - comandos de chat y control del servidor para Black Mesa Hub (SourceMod).
// Chat para todos: /tp /s /p /kill /jugadores /ayuda
// Chat solo anfitrion (admin con flag z): /god /noclip /notarget /armas /give /dar /restart /map /gravedad /velocidad /respawn
// El Hub manda ordenes al servidor escribiendo data/hubcmd.txt (esta cola se lee cada 0.5 s) y lee data/hubstate.txt.
#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

public Plugin myinfo =
{
	name = "Black Mesa Hub",
	author = "Black Mesa Hub",
	description = "Comandos de chat y cola de ordenes del Hub",
	version = "1.0.0",
	url = ""
};

char g_szQueue[PLATFORM_MAX_PATH];
char g_szAck[PLATFORM_MAX_PATH];
char g_szState[PLATFORM_MAX_PATH];

float g_vSaved[MAXPLAYERS + 1][3];
bool g_bSaved[MAXPLAYERS + 1];
float g_fSpeed = 1.0;

public void OnPluginStart()
{
	BuildPath(Path_SM, g_szQueue, sizeof(g_szQueue), "data/hubcmd.txt");
	BuildPath(Path_SM, g_szAck, sizeof(g_szAck), "data/hubcmd.ack");
	BuildPath(Path_SM, g_szState, sizeof(g_szState), "data/hubstate.txt");

	AddCommandListener(OnSay, "say");
	AddCommandListener(OnSay, "say_team");

	RegServerCmd("hub_do", Cmd_HubDo, "hub_do <steamid> <accion> [argumento]");
	RegServerCmd("hub_speed", Cmd_HubSpeed, "hub_speed <multiplicador>");

	HookEventEx("player_spawn", Event_Spawn);

	CreateTimer(0.5, Timer_Queue, _, TIMER_REPEAT);
	CreateTimer(2.0, Timer_State, _, TIMER_REPEAT);
}

public void OnClientPutInServer(int client)
{
	g_bSaved[client] = false;
}

public void Event_Spawn(Event event, const char[] name, bool dontBroadcast)
{
	if (g_fSpeed == 1.0)
		return;
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client > 0)
		CreateTimer(0.2, Timer_ApplySpeed, GetClientUserId(client));
}

public Action Timer_ApplySpeed(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);
	if (client > 0 && IsClientInGame(client) && IsPlayerAlive(client))
		SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", g_fSpeed);
	return Plugin_Stop;
}

// ---------- cola de ordenes del Hub ----------

public Action Timer_Queue(Handle timer)
{
	if (!FileExists(g_szQueue))
		return Plugin_Continue;

	File f = OpenFile(g_szQueue, "r");
	if (f == null)
		return Plugin_Continue;

	char lines[48][256];
	char line[256];
	int n = 0;
	while (n < 48 && !f.EndOfFile() && f.ReadLine(line, sizeof(line)))
	{
		TrimString(line);
		if (line[0] != '\0')
			strcopy(lines[n++], 256, line);
	}
	delete f;
	DeleteFile(g_szQueue);

	char id[32];
	id[0] = '\0';
	for (int i = 0; i < n; i++)
	{
		if (strncmp(lines[i], "#id ", 4) == 0)
		{
			strcopy(id, sizeof(id), lines[i][4]);
			continue;
		}
		if (lines[i][0] == '/' && lines[i][1] == '/')
			continue;
		ServerCommand("%s", lines[i]);
	}
	ServerExecute();

	if (id[0] != '\0')
	{
		File a = OpenFile(g_szAck, "w");
		if (a != null)
		{
			a.WriteLine("%s", id);
			delete a;
		}
	}
	return Plugin_Continue;
}

public Action Timer_State(Handle timer)
{
	char map[64];
	GetCurrentMap(map, sizeof(map));

	char names[512];
	names[0] = '\0';
	int count = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
			continue;
		char nm[MAX_NAME_LENGTH];
		GetClientName(i, nm, sizeof(nm));
		ReplaceString(nm, sizeof(nm), ";", " ");
		ReplaceString(nm, sizeof(nm), "=", " ");
		if (count > 0)
			StrCat(names, sizeof(names), ";");
		StrCat(names, sizeof(names), nm);
		count++;
	}

	File f = OpenFile(g_szState, "w");
	if (f == null)
		return Plugin_Continue;
	f.WriteLine("map=%s", map);
	f.WriteLine("players=%d", count);
	f.WriteLine("max=%d", GetMaxHumanPlayers());
	f.WriteLine("names=%s", names);
	f.WriteLine("coop=%d", FindConVar("sourcecoop_respawntime") != null ? 1 : 0);
	f.WriteLine("time=%d", GetTime());
	delete f;
	return Plugin_Continue;
}

// ---------- utilidades ----------

void Reply(int client, const char[] fmt, any ...)
{
	char buffer[256];
	VFormat(buffer, sizeof(buffer), fmt, 3);
	PrintToChat(client, "[Hub] %s", buffer);
}

bool IsHost(int client)
{
	return (GetUserFlagBits(client) & ADMFLAG_ROOT) != 0;
}

// Compara STEAM_0:Y:Z con STEAM_1:Y:Z (segun el juego el primer numero cambia)
bool SameSteam(const char[] a, const char[] b)
{
	if (strlen(a) < 9 || strlen(b) < 9)
		return false;
	return StrEqual(a[8], b[8]);
}

int FindBySteam(const char[] steam)
{
	char auth[64];
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
			continue;
		if (GetClientAuthId(i, AuthId_Steam2, auth, sizeof(auth)) && SameSteam(auth, steam))
			return i;
	}
	return -1;
}

int FindByName(const char[] name)
{
	int found = -1;
	char nm[MAX_NAME_LENGTH];
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
			continue;
		GetClientName(i, nm, sizeof(nm));
		if (StrEqual(nm, name, false))
			return i;
		if (found == -1 && StrContains(nm, name, false) != -1)
			found = i;
	}
	return found;
}

bool ResolveItem(const char[] name, char[] out, int len)
{
	char n[64];
	strcopy(n, sizeof(n), name);
	StringToLower(n);

	if (StrEqual(n, "crowbar") || StrEqual(n, "palanca")) strcopy(out, len, "weapon_crowbar");
	else if (StrEqual(n, "pistola") || StrEqual(n, "glock")) strcopy(out, len, "weapon_glock");
	else if (StrEqual(n, "magnum") || StrEqual(n, "357")) strcopy(out, len, "weapon_357");
	else if (StrEqual(n, "mp5") || StrEqual(n, "subfusil")) strcopy(out, len, "weapon_mp5");
	else if (StrEqual(n, "escopeta") || StrEqual(n, "shotgun")) strcopy(out, len, "weapon_shotgun");
	else if (StrEqual(n, "ballesta") || StrEqual(n, "crossbow")) strcopy(out, len, "weapon_crossbow");
	else if (StrEqual(n, "rpg") || StrEqual(n, "cohete")) strcopy(out, len, "weapon_rpg");
	else if (StrEqual(n, "tau") || StrEqual(n, "gauss")) strcopy(out, len, "weapon_tau");
	else if (StrEqual(n, "gluon") || StrEqual(n, "egon")) strcopy(out, len, "weapon_gluon");
	else if (StrEqual(n, "hornet") || StrEqual(n, "hivehand") || StrEqual(n, "avispas")) strcopy(out, len, "weapon_hivehand");
	else if (StrEqual(n, "granadas") || StrEqual(n, "frag")) strcopy(out, len, "weapon_frag");
	else if (StrEqual(n, "satchel")) strcopy(out, len, "weapon_satchel");
	else if (StrEqual(n, "tripmine") || StrEqual(n, "mina")) strcopy(out, len, "weapon_tripmine");
	else if (StrEqual(n, "snark") || StrEqual(n, "snarks")) strcopy(out, len, "weapon_snark");
	else if (StrEqual(n, "botiquin")) strcopy(out, len, "item_healthkit");
	else if (StrEqual(n, "bateria")) strcopy(out, len, "item_battery");
	else if ((strncmp(n, "weapon_", 7) == 0 || strncmp(n, "item_", 5) == 0) && SafeToken(n)) strcopy(out, len, n);
	else return false;
	return true;
}

bool SafeToken(const char[] s)
{
	int l = strlen(s);
	if (l == 0 || l > 48)
		return false;
	for (int i = 0; i < l; i++)
	{
		if (!(IsCharAlpha(s[i]) || IsCharNumeric(s[i]) || s[i] == '_'))
			return false;
	}
	return true;
}

void StringToLower(char[] s)
{
	int l = strlen(s);
	for (int i = 0; i < l; i++)
		s[i] = CharToLower(s[i]);
}

// ---------- acciones sobre un jugador (las usan el chat y el Hub) ----------

void ToggleFlag(int client, int flag, const char[] label)
{
	SetEntityFlags(client, GetEntityFlags(client) ^ flag);
	Reply(client, "%s %s", label, (GetEntityFlags(client) & flag) ? "activado" : "desactivado");
}

void DoAction(int client, const char[] action, const char[] arg)
{
	if (StrEqual(action, "god"))
	{
		bool on = GetEntProp(client, Prop_Data, "m_takedamage") == 0;
		SetEntProp(client, Prop_Data, "m_takedamage", on ? 2 : 0);
		Reply(client, "God %s", on ? "desactivado" : "activado");
	}
	else if (StrEqual(action, "noclip"))
	{
		if (GetEntityMoveType(client) == MOVETYPE_NOCLIP)
		{
			SetEntityMoveType(client, MOVETYPE_WALK);
			Reply(client, "Noclip desactivado");
		}
		else
		{
			SetEntityMoveType(client, MOVETYPE_NOCLIP);
			Reply(client, "Noclip activado");
		}
	}
	else if (StrEqual(action, "notarget"))
	{
		ToggleFlag(client, FL_NOTARGET, "Notarget");
	}
	else if (StrEqual(action, "armas"))
	{
		static const char all[][] = { "weapon_crowbar", "weapon_glock", "weapon_357", "weapon_mp5", "weapon_shotgun", "weapon_crossbow",
			"weapon_rpg", "weapon_tau", "weapon_gluon", "weapon_hivehand", "weapon_frag", "weapon_satchel", "weapon_tripmine", "weapon_snark" };
		int ok = 0;
		for (int i = 0; i < sizeof(all); i++)
		{
			if (GivePlayerItem(client, all[i]) != -1)
				ok++;
		}
		Reply(client, "Armas: %d de %d", ok, sizeof(all));
	}
	else if (StrEqual(action, "give"))
	{
		char item[64];
		if (arg[0] == '\0' || !ResolveItem(arg, item, sizeof(item)))
		{
			Reply(client, "Uso: /give escopeta (crowbar pistola magnum mp5 escopeta ballesta rpg tau gluon hornet granadas satchel tripmine snarks botiquin bateria)");
			return;
		}
		if (GivePlayerItem(client, item) == -1)
			Reply(client, "Este juego no tiene %s", item);
		else
			Reply(client, "Te di %s", item);
	}
	else if (StrEqual(action, "strip"))
	{
		for (int i = 0; i < 48; i++)
		{
			int w = GetEntPropEnt(client, Prop_Send, "m_hMyWeapons", i);
			if (w > 0 && IsValidEntity(w))
			{
				RemovePlayerItem(client, w);
				RemoveEntity(w);
			}
		}
		Reply(client, "Sin armas");
	}
	else if (StrEqual(action, "kill"))
	{
		if (IsPlayerAlive(client))
			ForcePlayerSuicide(client);
	}
	else if (StrEqual(action, "heal"))
	{
		SetEntityHealth(client, 100);
		Reply(client, "Vida al maximo");
	}
	else if (StrEqual(action, "tp"))
	{
		TeleportToPlayer(client, arg);
	}
	else if (StrEqual(action, "savepos") || StrEqual(action, "loadpos"))
	{
		HandleChat(client, StrEqual(action, "savepos") ? "s" : "p", "");
	}
}

void TeleportToPlayer(int client, const char[] name)
{
	if (name[0] == '\0' || StrEqual(name, "lista"))
	{
		char nm[MAX_NAME_LENGTH];
		char list[256];
		list[0] = '\0';
		for (int i = 1; i <= MaxClients; i++)
		{
			if (i == client || !IsClientInGame(i) || IsFakeClient(i))
				continue;
			GetClientName(i, nm, sizeof(nm));
			if (list[0] != '\0')
				StrCat(list, sizeof(list), ", ");
			StrCat(list, sizeof(list), nm);
		}
		Reply(client, list[0] != '\0' ? "Usa /tp nombre. Jugadores: %s" : "Usa /tp nombre. No hay nadie mas.", list);
		return;
	}
	int target = FindByName(name);
	if (target == -1)
	{
		Reply(client, "No encontre a %s.", name);
		return;
	}
	if (target == client)
	{
		Reply(client, "Ese eres tu.");
		return;
	}
	if (!IsPlayerAlive(client) || !IsPlayerAlive(target))
	{
		Reply(client, "Los dos deben estar vivos.");
		return;
	}
	float pos[3];
	GetClientAbsOrigin(target, pos);
	pos[2] += 8.0;
	TeleportEntity(client, pos, NULL_VECTOR, NULL_VECTOR);
	char nm2[MAX_NAME_LENGTH];
	GetClientName(target, nm2, sizeof(nm2));
	Reply(client, "Con %s", nm2);
}

// ---------- chat ----------

public Action OnSay(int client, const char[] command, int argc)
{
	if (client < 1 || client > MaxClients || !IsClientInGame(client))
		return Plugin_Continue;

	char text[192];
	GetCmdArgString(text, sizeof(text));
	StripQuotes(text);
	TrimString(text);
	if (text[0] != '/' && text[0] != '!')
		return Plugin_Continue;

	char cmd[32];
	char rest[160];
	rest[0] = '\0';
	int pos = BreakString(text[1], cmd, sizeof(cmd));
	if (pos != -1)
		strcopy(rest, sizeof(rest), text[1 + pos]);
	TrimString(rest);
	StringToLower(cmd);

	if (HandleChat(client, cmd, rest))
		return Plugin_Handled;
	return Plugin_Continue;
}

bool HandleChat(int client, const char[] cmd, const char[] rest)
{
	// ----- para todos
	if (StrEqual(cmd, "tp")) { TeleportToPlayer(client, rest); return true; }
	if (StrEqual(cmd, "s"))
	{
		if (!IsPlayerAlive(client)) { Reply(client, "Estas muerto."); return true; }
		GetClientAbsOrigin(client, g_vSaved[client]);
		g_bSaved[client] = true;
		Reply(client, "Posicion guardada. /p para volver.");
		return true;
	}
	if (StrEqual(cmd, "p"))
	{
		if (!g_bSaved[client]) { Reply(client, "Primero guarda una posicion con /s."); return true; }
		if (!IsPlayerAlive(client)) { Reply(client, "Estas muerto."); return true; }
		TeleportEntity(client, g_vSaved[client], NULL_VECTOR, NULL_VECTOR);
		return true;
	}
	if (StrEqual(cmd, "kill")) { DoAction(client, "kill", ""); return true; }
	if (StrEqual(cmd, "jugadores"))
	{
		TeleportToPlayer(client, "lista");
		return true;
	}
	if (StrEqual(cmd, "ayuda") || StrEqual(cmd, "hubayuda"))
	{
		Reply(client, "Todos: /tp nombre  /s  /p  /kill  /jugadores");
		if (IsHost(client))
			Reply(client, "Anfitrion: /god /noclip /notarget /armas /give x /restart /map x /gravedad baja|normal /velocidad rapida|normal /respawn n");
		return true;
	}

	// ----- solo anfitrion
	bool admin = StrEqual(cmd, "god") || StrEqual(cmd, "noclip") || StrEqual(cmd, "notarget") || StrEqual(cmd, "armas") || StrEqual(cmd, "give")
		|| StrEqual(cmd, "dar") || StrEqual(cmd, "restart") || StrEqual(cmd, "reiniciar") || StrEqual(cmd, "map") || StrEqual(cmd, "mapa")
		|| StrEqual(cmd, "gravedad") || StrEqual(cmd, "velocidad") || StrEqual(cmd, "respawn");
	if (!admin)
		return false;

	if (!IsHost(client))
	{
		Reply(client, "/%s es solo del anfitrion.", cmd);
		return true;
	}

	if (StrEqual(cmd, "god") || StrEqual(cmd, "noclip") || StrEqual(cmd, "notarget") || StrEqual(cmd, "armas"))
	{
		DoAction(client, cmd, "");
		return true;
	}
	if (StrEqual(cmd, "give") || StrEqual(cmd, "dar"))
	{
		DoAction(client, "give", rest);
		return true;
	}
	if (StrEqual(cmd, "restart") || StrEqual(cmd, "reiniciar"))
	{
		char cur[64];
		GetCurrentMap(cur, sizeof(cur));
		PrintToChatAll("[Hub] Reiniciando el mapa...");
		ForceChangeLevel(cur, "Hub: reiniciar");
		return true;
	}
	if (StrEqual(cmd, "map") || StrEqual(cmd, "mapa"))
	{
		if (rest[0] == '\0' || !SafeToken(rest) || !IsMapValid(rest))
		{
			Reply(client, "Uso: /map bm_c1a1a  (ese mapa no existe o el nombre no es valido)");
			return true;
		}
		PrintToChatAll("[Hub] Cambiando a %s...", rest);
		ForceChangeLevel(rest, "Hub: cambio de mapa");
		return true;
	}
	if (StrEqual(cmd, "gravedad"))
	{
		ConVar g = FindConVar("sv_gravity");
		if (g == null) { Reply(client, "Este juego no tiene sv_gravity."); return true; }
		if (StrEqual(rest, "baja")) { g.IntValue = 200; Reply(client, "Gravedad baja"); }
		else if (StrEqual(rest, "normal")) { g.RestoreDefault(); Reply(client, "Gravedad normal"); }
		else Reply(client, "Uso: /gravedad baja | normal");
		return true;
	}
	if (StrEqual(cmd, "velocidad"))
	{
		if (StrEqual(rest, "rapida")) { SetSpeedAll(2.0); Reply(client, "Velocidad x2"); }
		else if (StrEqual(rest, "normal")) { SetSpeedAll(1.0); Reply(client, "Velocidad normal"); }
		else Reply(client, "Uso: /velocidad rapida | normal");
		return true;
	}
	if (StrEqual(cmd, "respawn"))
	{
		int s = StringToInt(rest);
		ConVar r = FindConVar("sourcecoop_respawntime");
		if (rest[0] == '\0' || s < 0 || s > 60) { Reply(client, "Uso: /respawn 5  (segundos, de 0 a 60)"); return true; }
		if (r == null) { Reply(client, "SourceCoop no esta cargado."); return true; }
		r.FloatValue = s < 1 ? 0.1 : float(s);
		Reply(client, "Reaparicion: %d s", s);
		return true;
	}
	return false;
}

void SetSpeedAll(float mult)
{
	g_fSpeed = mult;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsPlayerAlive(i))
			SetEntPropFloat(i, Prop_Send, "m_flLaggedMovementValue", mult);
	}
}

// ---------- ordenes del Hub: hub_do <steamid> <accion> [arg] ----------

public Action Cmd_HubDo(int args)
{
	if (args < 2)
	{
		PrintToServer("[Hub] uso: hub_do <steamid> <accion> [arg]");
		return Plugin_Handled;
	}
	char steam[64], action[32], arg[64];
	GetCmdArg(1, steam, sizeof(steam));
	GetCmdArg(2, action, sizeof(action));
	arg[0] = '\0';
	if (args >= 3)
		GetCmdArg(3, arg, sizeof(arg));

	int client = FindBySteam(steam);
	if (client == -1)
	{
		PrintToServer("[Hub] %s no esta dentro de la partida.", steam);
		return Plugin_Handled;
	}
	if (!IsPlayerAlive(client) && !StrEqual(action, "kill"))
	{
		PrintToServer("[Hub] %s esta muerto.", steam);
		return Plugin_Handled;
	}
	DoAction(client, action, arg);
	return Plugin_Handled;
}

public Action Cmd_HubSpeed(int args)
{
	char a[16];
	GetCmdArg(1, a, sizeof(a));
	float m = StringToFloat(a);
	if (m < 0.5 || m > 4.0)
		m = 1.0;
	SetSpeedAll(m);
	return Plugin_Handled;
}
