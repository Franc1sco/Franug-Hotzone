/*  SM Franug HotZone
 *
 *  Copyright (C) 2020 Francisco 'Franc1sco' García
 * 
 * This program is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the Free
 * Software Foundation, either version 3 of the License, or (at your option) 
 * any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT 
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS 
 * FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along with 
 * this program. If not, see http://www.gnu.org/licenses/.
 */

#include <sourcemod>
#include <cstrike>
#include <sdkhooks>
#include <sdktools>
#include <devzones>
#include <colorvariables>

//SQL Locking System

Database g_hDatabase;

float g_Best;
int g_BestMinute;
float g_BestSecond;
char g_BestName[128];

char _currentZone[64];

Handle g_TimerHandle[MAXPLAYERS + 1];

Handle _timerChangeZone;

Handle g_Zones, g_usedZones;

float g_TimerPoint[MAXPLAYERS + 1][2];
char g_TimerEnabled[MAXPLAYERS + 1] = { 0 }; // 0 on ing 1 on after reaching end zone 2 on being at start zone 3 on being at end zone

int g_BeamSprite = -1, g_HaloSprite = -1;

int ga_iRedColor[4] = {255, 75, 75, 255};

//SQL Queries

char sql_createTables1[] = "CREATE TABLE IF NOT EXISTS `devzones_hotzones` ( \
  `ID` int(11) NOT NULL AUTO_INCREMENT, \
  `TimeStamp` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, \
  `MapName` varchar(32) NOT NULL, \
  `UserName` varchar(32) DEFAULT NULL, \
  `UserID` int(11) NOT NULL, \
  `Score` float NOT NULL, \
  PRIMARY KEY (`ID`) \
);";

char sql_selectBestByMap[] = "SELECT `Score`, `UserName` FROM `devzones_hotzones` WHERE `MapName`='%s' ORDER BY `Score` DESC LIMIT 1;";
char sql_insertScore[] = "INSERT INTO `devzones_hotzones` SET `MapName`='%s', `UserName`= '%s', `UserID`='%d', `Score`='%.3f';"; 

#pragma semicolon 1

#define PLUGIN_VERSION "0.1"

public Plugin myinfo = {
	name = "SM Franug HotZone",
	author = "Franc1sco franug",
	description = "",
	version = PLUGIN_VERSION,
	url = "http://steamcommunity.com/id/franug"
};

public void OnPluginStart() 
{
	g_Zones = CreateArray(128);
	g_usedZones = CreateArray(128);
	
	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("player_death", Event_PlayerDeath);
	
	HookEvent("round_prestart", Event_Start);
	
	HookEvent("round_poststart", Event_FirstSelection);
	
	if(SQL_CheckConfig("devzones_hotzone"))
	{
		Database.Connect(OnDatabaseConnect, "devzones_hotzone");
	} else {
		SetFailState("No found database entry devzones_hotzone on databases.cfg");
	}
}

public void OnMapStart()
{
	//g_BeamSprite = PrecacheModel("materials/sprites/bomb_planted_ring.vmt");
	//g_HaloSprite = PrecacheModel("materials/sprites/halo.vtf");
	
	g_BeamSprite = PrecacheModel("sprites/laserbeam.vmt");
	g_HaloSprite = PrecacheModel("materials/sprites/halo.vmt");
	
	delete _timerChangeZone;
	
	CreateTimer(0.1, Timer_Hud, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	
	CreateTimer(2.0, Timer_Box, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_Box(Handle timer)
{
	if (strlen(_currentZone) < 2)return;
	
	float zoneCo[2][3];
	
	Zone_GetZoneCord(_currentZone, true, zoneCo[0], zoneCo[1]);
	
	for (int p = 1; p <= MaxClients; p++)
	{
		if (IsClientInGame(p) && !IsFakeClient(p))
		{
			TE_SendBeamBoxToClient(p, zoneCo[0], zoneCo[1], g_BeamSprite, g_HaloSprite, 0, 0, 2.1, 5.0, 5.0, 2, 1.0, ga_iRedColor, 0);
		}
	}
	
}

public Action Timer_Hud(Handle timer)
{
	if (strlen(_currentZone) < 2)return;
	
	
	int minute;
	float second;
	char inZone[512];
	
	if(g_BestSecond > 0.0 || g_BestMinute > 0)
	{
		SetHudTextParams(0.03, 0.03, 0.3, 0, 255, 0, 255, 0, 0.0, 0.0, 0.0);
		
		for (int p = 1; p <= MaxClients; p++)
		{
			if (IsClientInGame(p))
			{
				ShowHudText(p, 9, "Current Record:\n%.1f by %s", g_BestSecond, g_BestName);
			}
		}
	}
	
	SetHudTextParams(0.03, 0.12, 0.3, 255, 0, 0, 255, 0, 0.0, 0.0, 0.0);
	
			
	for (int p = 1; p <= MaxClients; p++)
	{
		if (IsClientInGame(p) && IsPlayerAlive(p) && g_TimerEnabled[p] == 0)
		{
			GetCurrentElapsedTime(p, minute, second);
			Format(inZone, sizeof(inZone), "%s%0.1f by %N\n", inZone, second, p);
		}
	}
			
	for (int p = 1; p <= MaxClients; p++)
	{
		if (IsClientInGame(p))
		{
			ShowHudText(p, 8, "Currently in Hotzone:\n%s", inZone);
		}
	}
	
}

public void Event_FirstSelection(Event event, const char[] name, bool dontBroadcast)
{
	delete _timerChangeZone;
	
	if (GetArraySize(g_Zones) == 0)return;
	
	g_usedZones = CloneArray(g_Zones);
	
	int index = GetRandomInt(0, GetArraySize(g_usedZones) - 1);
	
	GetArrayString(g_usedZones, index, _currentZone, 64);
	
	RemoveFromArray(g_usedZones, index);
	
	_timerChangeZone = CreateTimer(120.0, Timer_ChangeZone);
	
	CPrintToChatAll("{lightgreen}[Franug-HotZone]{green} Hotzone position changed.");
}


public void Event_Start(Event event, const char[] name, bool dontBroadcast)
{
	ClearArray(g_Zones);
}

public Action Timer_ChangeZone(Handle timer)
{
	if (GetArraySize(g_Zones) == 0)return;
	
	if (GetArraySize(g_usedZones) == 0)
		g_usedZones = CloneArray(g_Zones);
		
	
	int index = GetRandomInt(0, GetArraySize(g_usedZones) - 1);
	
	GetArrayString(g_usedZones, index, _currentZone, 64);
	
	RemoveFromArray(g_usedZones, index);
	
	_timerChangeZone = CreateTimer(120.0, Timer_ChangeZone);
	
	CPrintToChatAll("{lightgreen}[Franug-HotZone]{green} Hotzone position changed.");
	
	float zoneCo[2][3];
	
	Zone_GetZoneCord(_currentZone, true, zoneCo[0], zoneCo[1]);
	
	// aqui
	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client) && IsPlayerAlive(client) && g_TimerEnabled[client] == 0)
		{
			delete g_TimerHandle[client];
			
			g_TimerPoint[client][1] = GetGameTime();
			float scoredTime = g_TimerPoint[client][1] - g_TimerPoint[client][0];
			CPrintToChat(client, "{lightgreen}[Franug-HotZone]{green} You've reached %.3fs on the hotzone", scoredTime);
			
			SetRecord(client, scoredTime);
			
			if(Zone_IsClientInZone(client, _currentZone, true, true))
			{
				g_TimerEnabled[client] = 2;
				
				g_TimerPoint[client][0] = GetGameTime();
				g_TimerEnabled[client] = 0;
				g_TimerHandle[client] = CreateTimer(0.1, ShowHint, client);
			}
		}
	}
}

public void OnDatabaseConnect(Database db, const char[] error, any data)
{
	/**
	 * See if the connection is valid.  If not, don't un-mark the caches
	 * as needing rebuilding, in case the next connection request works.
	 */
	if(db == null)
	{
		LogError("Database failure: %s", error);
	}
	else 
	{
		g_hDatabase = db;
	}
	db.Query(T_CreateTable, sql_createTables1, _, DBPrio_High);
	
	return;
}

public void T_CreateTable(Database db, DBResultSet results, const char[] error, any data)
{
	if(db == null || results == null || error[0] != '\0')
	{
		LogError("Query failed! %s", error);
		return;
	}
	
	GetBest();
}

void SetRecord(int client, float timeScored)
{
	char query[255];
	char unescapedMap[32];
	char Map[65];
	
	GetCurrentMap(unescapedMap, sizeof(unescapedMap));
	
	char Name[MAX_NAME_LENGTH+1];
	char SafeName[(sizeof(Name)*2)+1];
	if(!GetClientName(client, Name, sizeof(Name)))
		Format(SafeName, sizeof(SafeName), "<noname>");
	else
	{
		TrimString(Name);
		SQL_EscapeString(g_hDatabase, Name, SafeName, sizeof(SafeName));
	}
	
	if(!(SQL_EscapeString(g_hDatabase, unescapedMap, Map, sizeof(Map))))
	{
		LogError("Escape Error");
		return;
	}
	
	FormatEx(query, sizeof(query), sql_insertScore, Map, SafeName, GetSteamAccountID(client), timeScored);
	g_hDatabase.Query(T_SetRecord, query, GetClientSerial(client));
	
	return;
}

public void T_SetRecord(Database db, DBResultSet results, const char[] error, any data)
{
	if(GetClientFromSerial(data) == 0)
		return;
	
	if(db == null || results == null || error[0] != '\0')
	{
		LogError("Query failed! %s", error);
		return;
	}
	
	GetBest();
}

void GetBest()
{
	char query[255];
	char unescapedMap[32], Map[65];
	
	GetCurrentMap(unescapedMap, sizeof(unescapedMap));
	
	if(!(SQL_EscapeString(g_hDatabase, unescapedMap, Map, sizeof(Map))))
	{
		LogError("Escape Error");
		return;
	}
	
	FormatEx(query, sizeof(query), sql_selectBestByMap, Map);
	g_hDatabase.Query(T_GetBest, query);
	
	return;
}

public void T_GetBest(Database db, DBResultSet results, const char[] error, any data)
{
	
	g_Best = 0.0;
	
	if(db == null || results == null || error[0] != '\0')
	{
		LogError("Query failed! %s", error);
		return;
	}
	
	if(SQL_HasResultSet(results) && SQL_FetchRow(results))
	{
		g_Best = SQL_FetchFloat(results, 0);
		GetSecondToMinute(g_Best, g_BestMinute, g_BestSecond);
		
		SQL_FetchString(results, 1, g_BestName, sizeof(g_BestName));
	}
}


public void OnClientPutInServer(int client)
{
	if(IsInvalidClient(client)) 
		return;
	
	g_TimerEnabled[client] = 2;
	g_TimerPoint[client][0] = 0.0;
	g_TimerPoint[client][1] = 0.0;

}

public void OnClientDisconnect(int client)
{
	delete g_TimerHandle[client];
}

///////////////////
//  Event Hook Functions

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	
	g_TimerEnabled[client] = 2;
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	
	g_TimerEnabled[client] = 2;
}

public Action ShowHint(Handle timer, int client)
{
	g_TimerHandle[client] = null;
	//int minute;
	//float second;
	//char buffer[64];
	
	if(client == 0 || !IsClientInGame(client))
	{
		return;
	}
	
	if(g_TimerEnabled[client] != 0)
	{
		g_TimerPoint[client][1] = GetGameTime();
		float scoredTime = g_TimerPoint[client][1] - g_TimerPoint[client][0];
		CPrintToChat(client, "{lightgreen}[Franug-HotZone]{green} You've reached %.3fs on the hotzone", scoredTime);
			
		SetRecord(client, scoredTime);
		return;
	}
	if(!IsPlayerAlive(client))
	{
		g_TimerEnabled[client] = 2;
		return;
	}
	
	/*
	GetClientName(client, buffer, sizeof(buffer));
	GetCurrentElapsedTime(client, minute, second);
	
	if (g_Best != 0.0)
	{
		PrintHintText(client, "Time: %02d:%06.3fs\nWR: %02d:%06.3fs", minute, second, g_BestMinute, g_BestSecond);
	}
	else
	{
		PrintHintText(client, "Time: %02d:%06.3fs", minute, second);
	}
	*/
	g_TimerHandle[client] = CreateTimer(0.1, ShowHint, client);
}

public void Zone_OnClientEntry(int client, const char[] zone)
{
	if(IsInvalidClient(client)) 
		return;
	
	if(StrContains(zone, _currentZone, true) == 0)
	{
		g_TimerEnabled[client] = 2;
		delete g_TimerHandle[client];
		
		g_TimerPoint[client][0] = GetGameTime();
		g_TimerEnabled[client] = 0;
		g_TimerHandle[client] = CreateTimer(0.1, ShowHint, client);
		
		
		CPrintToChat(client, "{lightgreen}[Franug-HotZone]{green} Started timer for the current hotzone.");
	}
}

public void Zone_OnClientLeave(int client, const char[] zone)
{
	if(IsInvalidClient(client)) 
		return;
	
	if(StrContains(zone, _currentZone, true) == 0)
	{
		/*
		if(g_TimerEnabled[client] == 0)
		{	
			
			g_TimerPoint[client][1] = GetGameTime();
			float scoredTime = g_TimerPoint[client][1] - g_TimerPoint[client][0];
			CPrintToChat(client, "{lighgreen}[Franug-Timer]{green} You've reached %.3fs on the hotzone", scoredTime);
			
			SetRecord(client, scoredTime);
		}
		*/
		g_TimerEnabled[client] = 3;
	}
}

///////////////////////
// Own Functions

bool IsInvalidClient(int client)
{
	if(client < 1 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client)) 
		return true;
	else 
		return false;
}

void GetCurrentElapsedTime(int client, int &minute, float &second)
{
	if(g_TimerEnabled[client] != 0)
	{
		minute = 0;
		second = 0.0;
		
		return;
	}
	float delta = GetGameTime() - g_TimerPoint[client][0];
	
	GetSecondToMinute(delta, minute, second);
	
	return;
}

void GetSecondToMinute(float input, int &minute, float &second)
{	
	minute = RoundToFloor(input) / 60;
	second = input - minute * 60.0;
	
	return;
}

public void Zone_OnCreated(const char [] zone)
{
	if(StrContains(zone, "hotzone", true) == 0)
	{
		char zonename[128];
		strcopy(zonename, 128, zone);
		
		if(FindStringInArray(g_Zones, zonename) == -1)
			PushArrayString(g_Zones, zonename);
	}
}

stock void TE_SendBeamBoxToClient(int client, float uppercorner[3], const float bottomcorner[3], int ModelIndex, int HaloIndex, int StartFrame, int FrameRate, float Life, float Width, float EndWidth, int FadeLength, float Amplitude, const int Color[4], int Speed) 
{
	float tc1[3];
	AddVectors(tc1, uppercorner, tc1);
	tc1[0] = bottomcorner[0];
	
	float tc2[3];
	AddVectors(tc2, uppercorner, tc2);
	tc2[1] = bottomcorner[1];
	
	float tc3[3];
	AddVectors(tc3, uppercorner, tc3);
	tc3[2] = bottomcorner[2];
	
	float tc4[3];
	AddVectors(tc4, bottomcorner, tc4);
	tc4[0] = uppercorner[0];
	
	float tc5[3];
	AddVectors(tc5, bottomcorner, tc5);
	tc5[1] = uppercorner[1];
	
	float tc6[3];
	AddVectors(tc6, bottomcorner, tc6);
	tc6[2] = uppercorner[2];
	
	TE_SetupBeamPoints(uppercorner, tc1, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
	TE_SendToClient(client);
	TE_SetupBeamPoints(uppercorner, tc2, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
	TE_SendToClient(client);
	TE_SetupBeamPoints(uppercorner, tc3, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
	TE_SendToClient(client);
	TE_SetupBeamPoints(tc6, tc1, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
	TE_SendToClient(client);
	TE_SetupBeamPoints(tc6, tc2, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
	TE_SendToClient(client);
	TE_SetupBeamPoints(tc6, bottomcorner, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
	TE_SendToClient(client);
	TE_SetupBeamPoints(tc4, bottomcorner, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
	TE_SendToClient(client);
	TE_SetupBeamPoints(tc5, bottomcorner, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
	TE_SendToClient(client);
	TE_SetupBeamPoints(tc5, tc1, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
	TE_SendToClient(client);
	TE_SetupBeamPoints(tc5, tc3, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
	TE_SendToClient(client);
	TE_SetupBeamPoints(tc4, tc3, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
	TE_SendToClient(client);
	TE_SetupBeamPoints(tc4, tc2, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
	TE_SendToClient(client);
}