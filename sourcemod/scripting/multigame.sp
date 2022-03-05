/*
 * Copyright (C) 2022 SirGreenman. All Rights reserved.
 * ======================================================================
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

#include <sourcemod>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.0.0"
#define CONFIG_PATH "configs/multigame.cfg"
#define MULTI_TAG "\x07375E97[\x07FB6542MultiGame\x07375E97]\x01"

public Plugin myinfo =
{
	name             = "Multigame",
	author           = "SirGreenman",
	description      = "Multiple gamemodes",
	version          = PLUGIN_VERSION,
	url              = "https://github.com/SirGreenman/Multigame"
};

bool g_pVoted[MAXPLAYERS+1] = false;
int g_gameindex[2]; //current & new

ConVar cv_EnableVoting;

enum struct MultiGameConfig
{
	char pluginName[64];
	char map[64];
	
	void ReadFromKv(KeyValues kv)
	{
		char section[256];
		if (!kv.GetSectionName(section, sizeof(section)))
			return;
		
		kv.GetString("plugin", this.pluginName, PLATFORM_MAX_PATH);
		kv.GetString("map", this.map, PLATFORM_MAX_PATH);
	}
}
ArrayList g_MultiGameConfig;

public void OnPluginStart()
{
	g_MultiGameConfig = new ArrayList(sizeof(MultiGameConfig));
	cv_EnableVoting = CreateConVar("multi_enable_voting", "1", "allows players to vote to switch gamemode");
	AutoExecConfig(true, "multigame");

	RegConsoleCmd("sm_gamemode", Command_Gamemode);
	RegAdminCmd("sm_forcegame", Command_Force, ADMFLAG_CONFIG);
	RegAdminCmd("sm_reloadgamecfg", Command_ReloadConfig, ADMFLAG_CONFIG, "Reloads multigame cfg");
	
	LoadConfig();
	g_gameindex[0] = 0;
}

void LoadConfig()
{
	g_MultiGameConfig.Clear();

	char file[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, file, sizeof(file), CONFIG_PATH);

	KeyValues kv = new KeyValues("multigame");
	if (kv.ImportFromFile(file))
	{
		if (kv.GotoFirstSubKey(false))
		{
			do
			{
				MultiGameConfig cfg;
				cfg.ReadFromKv(kv);
				g_MultiGameConfig.PushArray(cfg);
			}
			while (kv.GotoNextKey(false));
			kv.GoBack();
		}
	}
	delete kv;
}

public void OnClientPutInServer(int client)
{
	g_pVoted[client] = false;
}

public Action Command_ReloadConfig(int client, int argc)
{
	LoadConfig();
	ReplyToCommand(client, "[MultiGame] reloaded cfg");
	return Plugin_Handled;
}

public Action Command_Force(int client, int argc)
{
	Menu menu = new Menu(Menu_AdminHandler);
	menu.SetTitle("Vote NextGame");
	for (int i=0; i < g_MultiGameConfig.Length; i++)
	{
		char name[64];
		g_MultiGameConfig.GetString(i, name, sizeof(name));
		menu.AddItem(name, name);
	}
	menu.ExitButton = false;
	menu.Display(client, 5);
}

public Action Command_Gamemode(int client, int argc)
{
	if (g_pVoted[client] || !cv_EnableVoting.BoolValue)
		return Plugin_Continue;
	
	g_pVoted[client] = true;
	
	int votes, voters;
	for (int i=1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i))
		{
			voters++;
			if (g_pVoted[i]) votes++;
		}
	}

	int required = RoundToCeil(float(voters) * 0.25);
	if (votes >= required)
		Menu_DisplayVote();
	else
		PrintToChatAll("%s %i required to change gamemode", MULTI_TAG, required);
	
	return Plugin_Handled;
}

void Menu_DisplayVote()
{
	Menu menu = new Menu(Menu_VoteHandler, MENU_ACTIONS_ALL);
	menu.SetTitle("Vote NextGame");
	for (int i=0; i < g_MultiGameConfig.Length; i++)
	{
		char name[64];
		g_MultiGameConfig.GetString(i, name, sizeof(name));
		menu.AddItem(name, name);
	}
	menu.ExitButton = false;
	menu.DisplayVoteToAll(5);
}

public int Menu_AdminHandler(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select: SelectGame(menu, param2);
		case MenuAction_End: delete menu;
	}
}

public int Menu_VoteHandler(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_VoteEnd: SelectGame(menu, param1);
		case MenuAction_End: delete menu;
	}
	return 0;
}

void SelectGame(Menu menu, int selected)
{
	char item[64]; menu.GetItem(selected, item, sizeof(item));
	PrintToChatAll("%s Next Gamemode: %s", MULTI_TAG, item);
	g_gameindex[1] = selected;
	CreateTimer(5.0, Timer_ChangeGamemode);
}

public Action Timer_ChangeGamemode(Handle hTimer)
{
	char disablePlugin[64];
	g_MultiGameConfig.GetString(g_gameindex[0], disablePlugin, sizeof(disablePlugin));
	MovePluginFile(disablePlugin, false);

	char enablePlugin[64];
	g_MultiGameConfig.GetString(g_gameindex[1], enablePlugin, sizeof(enablePlugin));
	MovePluginFile(enablePlugin, true);

	MultiGameConfig cfg;
	g_MultiGameConfig.GetArray(g_gameindex[1], cfg);
	ServerCommand("changelevel %s", cfg.map);

	g_gameindex[0] = g_gameindex[1];
	return Plugin_Handled;
}

void MovePluginFile(char[] fileName, bool enable)
{
	char disabledPath[PLATFORM_MAX_PATH], enabledPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, disabledPath, sizeof(disabledPath), "plugins/disabled/%s.smx", fileName);	
	BuildPath(Path_SM, enabledPath, sizeof(enabledPath), "plugins/%s.smx", fileName);
	switch (enable)
	{
		case true:
		{
			if (!FileExists(disabledPath) || FileExists(enabledPath)) return;
			RenameFile(enabledPath, disabledPath);
		}
		case false:
		{
			if (!FileExists(enabledPath) || FileExists(disabledPath)) return;
			RenameFile(disabledPath, enabledPath);
		}
	}
}