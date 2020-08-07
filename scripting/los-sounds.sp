/*  SM Franug Hear Shots By Area
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
#include <sdktools>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.1"

#define MAX_CACHE_LIFE 0.5

ConVar cv_distance;

float g_fEyeOffset[3] = { 0.0, 0.0, 64.0 }; /* CSGO offset. */
float g_fLastShot[MAXPLAYERS];
float g_fLastComputed[MAXPLAYERS];
bool g_bCanSee[MAXPLAYERS][MAXPLAYERS];

public Plugin myinfo =
{
	name = "SM Franug Hear Shots By Area and LOS",
	author = "de_nerd, Franc1sco franug",
	description = "",
	version = PLUGIN_VERSION,
	url = "http://steamcommunity.com/id/franug"
};

public void OnPluginStart()
{
	CreateConVar("sm_franugshotsbyarea_version", PLUGIN_VERSION, "", FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
	
	cv_distance = CreateConVar("sm_franugshotsbyarea_distance", "2000.0", "Max distance from the shooter for don't hear him when the listener dont are in the same map place that shooter. 0.0 = use only map places");
	
	// weapon sounds
	AddTempEntHook("Shotgun Shot", Hook_ShotgunShot);
}

public bool IsValidClient( int client ) 
{ 
	if ( !( 1 <= client <= MaxClients ) || !IsClientInGame(client) ) 
		return false; 
	 
	return true; 
}

public Action Hook_ShotgunShot(const char[] te_name, const int[] players, int numClients, float delay) {

	int shooterIndex = TE_ReadNum("m_iPlayer") + 1;

	// Check which clients need to be excluded.
	int[] newClients = new int[MaxClients];
	int newTotal = 0;

	for (int i = 0; i < numClients; i++) {
		int client = players[i];

		bool rebroadcast = true;
		if (IsValidClient(client)) {
			rebroadcast = CanHear(shooterIndex, client);
		}

		if (rebroadcast) {
			// This Client should be able to hear it.
			newClients[newTotal] = client;
			newTotal++;
		}
	}

	g_fLastShot[shooterIndex] = GetEngineTime();

	// No clients were excluded.
	if (newTotal == numClients) {
		return Plugin_Continue;
	}

	// All clients were excluded and there is no need to broadcast.
	if (newTotal == 0) {
		return Plugin_Stop;
	}

	// Re-broadcast to clients that still need it.
	float vTemp[3];
	TE_Start("Shotgun Shot");
	TE_ReadVector("m_vecOrigin", vTemp);
	TE_WriteVector("m_vecOrigin", vTemp);
	TE_WriteFloat("m_vecAngles[0]", TE_ReadFloat("m_vecAngles[0]"));
	TE_WriteFloat("m_vecAngles[1]", TE_ReadFloat("m_vecAngles[1]"));
	TE_WriteNum("m_weapon", TE_ReadNum("m_weapon"));
	TE_WriteNum("m_iMode", TE_ReadNum("m_iMode"));
	TE_WriteNum("m_iSeed", TE_ReadNum("m_iSeed"));
	TE_WriteNum("m_iPlayer", TE_ReadNum("m_iPlayer"));
	TE_WriteFloat("m_fInaccuracy", TE_ReadFloat("m_fInaccuracy"));
	TE_WriteFloat("m_fSpread", TE_ReadFloat("m_fSpread"));
	TE_Send(newClients, newTotal, delay);

	return Plugin_Stop;
}

//
// The next code was taken from splewis multi1v1 plugin 
// with small editions to use on this plugin
//

public bool ShouldUpdate(int shooter) {
	float lastShot = g_fLastShot[shooter];
	float lastComputed = g_fLastComputed[shooter];

	PrintToConsole(shooter, "Last shot: %f", lastShot);
	float now = GetEngineTime();

	return (now - lastShot) > MAX_CACHE_LIFE || (now - lastComputed) > MAX_CACHE_LIFE * 2;
}

public bool UpdateVisibility(int shooter) {
	float shooterPos[3];
	GetClientAbsOrigin(shooter, shooterPos);

	float shooterEye[3];
	AddVectors(shooterPos, g_fEyeOffset, shooterEye);

	g_fLastComputed[shooter] = GetEngineTime();

	for (int client = 1; client < MaxClients; client++) {
		if (
			!IsValidClient(client) || 
			IsFakeClient(client) ||
			shooter == client
			) continue;

		float clientPos[3];
		GetClientAbsOrigin(client, clientPos);

		float clientEye[3];
		AddVectors(clientPos, g_fEyeOffset, clientEye);

		TR_TraceRayFilter(shooterEye, clientEye, MASK_PLAYERSOLID_BRUSHONLY, RayType_EndPoint, TraceEntityFilterPlayer);
		
		// If ray hit, then players can see each other
		g_bCanSee[shooter][client] = !TR_DidHit(INVALID_HANDLE);

		PrintToConsole(shooter, "Can see %N: %b", client, g_bCanSee[shooter][client]);
	}
}

public bool CanHear(int shooter, int client) {
	if (!IsValidClient(shooter) || !IsValidClient(client) || shooter == client) {
		return true;
	}

	char area1[128], area2[128];
	GetEntPropString(shooter, Prop_Send, "m_szLastPlaceName", area1, sizeof(area1)); 
	GetEntPropString(client, Prop_Send, "m_szLastPlaceName", area2, sizeof(area2)); 

	// If in the same area, always transmit
	if (StrEqual(area1, area2)) {
		// PrintToConsole(shooter, "Shot transmitted to %N. Same area %s", client, area1);

		return true;	
	}

	float shooterPos[3];
	float clientPos[3];
	GetClientAbsOrigin(shooter, shooterPos);
	GetClientAbsOrigin(client, clientPos);
	float distance = GetVectorDistance(shooterPos, clientPos);
	
	// If too far away, never transmit
	if (distance >= cv_distance.FloatValue) {
		// PrintToConsole(shooter, "Shot muted to %N. Too far away: %f", client, distance);

		return false;
	}

	if (ShouldUpdate(shooter)) {
		PrintToConsole(shooter, "Updating your visibility!");
		UpdateVisibility(shooter);
	} else {
		PrintToConsole(shooter, "Visibility CACHED!");
	}

	return g_bCanSee[shooter][client];
}

public bool TraceEntityFilterPlayer(int entity, int contentsMask)
{
	if ((entity > 0) && (entity <= MaxClients)) return false;
	return true;
}