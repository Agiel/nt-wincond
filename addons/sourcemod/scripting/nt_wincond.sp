// # Changelog
//
// ## 0.0.2
// * Announce ghost capper.
// * Consider players who haven't spawned in yet as alive for the purpose of rewarding points.
//
// ## 0.0.1
// * Initial release

#include <sourcemod>
#include <dhooks>
#include <neotokyo>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "0.0.2"

#define TIEBREAKER_ENABLED false

#define GAMEHUD_TIE 3
#define GAMEHUD_JINRAI 4
#define GAMEHUD_NSF 5

#define GAMETYPE_TDM 0
#define GAMETYPE_CTG 1
#define GAMETYPE_VIP 2

public Plugin myinfo = {
    name = "NT Win Condition",
    description = "Overloads the win condition checks to allow modding",
    author = "Agiel",
    version = PLUGIN_VERSION,
    url = "https://github.com/Agiel/nt-wincond"
};

int g_ghostEntity = -1;

public void OnPluginStart() {
	Handle gd = LoadGameConfigFile("neotokyo/wincond");
	if (gd == INVALID_HANDLE) {
		SetFailState("Failed to load GameData");
	}
	DynamicDetour dd = DynamicDetour.FromConf(gd, "Fn_CheckWinCondition");
	if (!dd) {
		SetFailState("Failed to create dynamic detour");
	}
	if (!dd.Enable(Hook_Pre, CheckWinCondition)) {
		SetFailState("Failed to detour");
	}
	delete dd;
	CloseHandle(gd);
}

public void OnEntityCreated(int entity, const char[] classname) {
    if (StrEqual(classname, "weapon_ghost")) {
        g_ghostEntity = EntIndexToEntRef(entity);
    }
}

void EndRound(int gameHud) {
    if (gameHud < 3 || gameHud > 5) {
        return;
    }

    GameRules_SetProp("m_iGameHud", gameHud);
    GameRules_SetProp("m_iGameState", GAMESTATE_ROUND_OVER);
    GameRules_SetPropFloat("m_fRoundTimeLeft", 15.0);
}

int RankUp(int xp) {
    if (xp < 0) {
        return 0;
    }
    if (xp < 4) {
        return 4;
    }
    if (xp < 10) {
        return 10;
    }
    if (xp < 20) {
        return 20;
    }
    return xp;
}

void RewardWin(int team, bool ghostCapped = false) {
    int score = GetTeamScore(team);
    SetTeamScore(team, score + 1);

    for (int i = 1; i <= MaxClients; i++) {
        if (IsValidClient(i)) {
            int playerTeam = GetClientTeam(i);
            if (playerTeam == team) {
                int xp = GetPlayerXP(i);
                if (ghostCapped) {
                    if (!IsPlayerDead(i)) {
                        xp = RankUp(xp); // Everyone alive goes up a rank
                    } else {
                        xp++; // Consolation prize for the rest
                    }
                } else {
                    xp++; // +1 for winning
                    if (!IsPlayerDead(i)) {
                        xp++; // +1 for staying alive
                    }
                    if (IsPlayerCarryingGhost(i)) {
                        xp++; // +1 for carrying ghost
                    }
                }
                SetPlayerXP(i, xp);
            }
        }
    }
}

bool IsPlayerDead(int client) {
    // None of the normal ways seemed to handle the case when players are still selecting weapon.
    // This is the address the game checks internally which seems to work better.
    Address player = GetEntityAddress(client);
    int isAlive = LoadFromAddress(player + view_as<Address>(0xDC4), NumberType_Int32);
    return isAlive == 0;
}

bool IsPlayerCarryingGhost(int client) {
    int weapon = GetPlayerWeaponSlot(client, SLOT_PRIMARY);
    if (!IsValidEntity(weapon)) {
        return false;
    }
    char classname[13];
    if (!GetEntityClassname(weapon, classname, sizeof(classname))) {
        return false;
    }
    return StrEqual(classname, "weapon_ghost");
}

bool CheckEliminationOrTimeout() {
    int aliveJinrai = 0;
    int aliveNsf = 0;
    for (int i = 1; i <= MaxClients; i++) {
        if (IsValidClient(i) && !IsPlayerDead(i)) {
            int team = GetClientTeam(i);
            if (team == TEAM_JINRAI) {
                aliveJinrai++;
            } else if (team == TEAM_NSF) {
                aliveNsf++;
            }
        }
    }

    // Check elimination
    if (aliveNsf == 0) {
        RewardWin(TEAM_JINRAI);
        EndRound(GAMEHUD_JINRAI);
        return true;
    }
    if (aliveJinrai == 0) {
        RewardWin(TEAM_NSF);
        EndRound(GAMEHUD_NSF);
        return true;
    }

    // Check timeout
    float roundTimeLeft = GameRules_GetPropFloat("m_fRoundTimeLeft");
    if (roundTimeLeft == 0.0) {
        if (TIEBREAKER_ENABLED) {
            if (aliveNsf < aliveJinrai) {
                RewardWin(TEAM_JINRAI);
                EndRound(GAMEHUD_JINRAI);
            }
            if (aliveJinrai < aliveNsf) {
                RewardWin(TEAM_NSF);
                EndRound(GAMEHUD_NSF);
            }
            return true;
        }
        EndRound(GAMEHUD_TIE);
        return true;
    }

    return false;
}

bool CheckGhostCap() {
    int numGhosts = LoadFromAddress(view_as<Address>(0x225443B8), NumberType_Int32);
    int numCapZones = LoadFromAddress(view_as<Address>(0x22542740), NumberType_Int32);

    if (numGhosts && IsValidEdict(g_ghostEntity)) {
        // TODO: NT only cares about the first ghost but we can add a loop here if we want to improve that

        // TODO: Couldn't figure out how to get carrier's team from memory, so storing ghost index in OnCreateEntity
        // Address ghostList = view_as<Address>(LoadFromAddress(view_as<Address>(0x225443AC), NumberType_Int32));
        // Address p_ghost = LoadFromAddress(ghostList, NumberType_Int32);
        // Address p_owner = LoadFromAddress(p_ghost + view_as<Address>(0x1EC), NumberType_Int32);
        // if (p_owner > -1) {
        //     int team = LoadFromAddress(p_owner + view_as<Address>(0x208), NumberType_Int32);
        //     PrintToServer("owner: %d, team: %d", p_owner, team);  // Garbage?
        // }

        int carrier = GetEntPropEnt(g_ghostEntity, Prop_Data, "m_hOwnerEntity");
        if (IsValidClient(carrier)) {
            int carryingTeam = GetClientTeam(carrier);
            float ghostOrigin[3];
            GetClientAbsOrigin(carrier, ghostOrigin);

            Address capZoneList = view_as<Address>(LoadFromAddress(view_as<Address>(0x22542734), NumberType_Int32));
            for (int i = 0; i < numCapZones; i++) {
                Address capZone = view_as<Address>(LoadFromAddress(capZoneList + view_as<Address>(i * 4), NumberType_Int32));
                int m_OwningTeamNumber = LoadFromAddress(capZone + view_as<Address>(0x360), NumberType_Int32);
                if (carryingTeam == m_OwningTeamNumber) {
                    float x = view_as<float>(LoadFromAddress(capZone + view_as<Address>(0x354), NumberType_Int32));
                    float y = view_as<float>(LoadFromAddress(capZone + view_as<Address>(0x358), NumberType_Int32));
                    float z = view_as<float>(LoadFromAddress(capZone + view_as<Address>(0x35C), NumberType_Int32));
                    x = x - ghostOrigin[0];
                    y = y - ghostOrigin[1];
                    z = z - ghostOrigin[2];
                    float distance = SquareRoot(x*x + y*y + z*z);
                    int m_Radius = LoadFromAddress(capZone + view_as<Address>(0x364), NumberType_Int32);
                    if (distance <= m_Radius) {
                        // Announce capper
                        GameRules_SetProp("m_iMVP", carrier);
                        RewardWin(carryingTeam, true);
                        if (carryingTeam == TEAM_JINRAI) {
                            EndRound(GAMEHUD_JINRAI);
                        } else {
                            EndRound(GAMEHUD_NSF);
                        }
                        return true;
                    }
                }
            }
        }
    }
    return false;
}

MRESReturn CheckWinCondition(Address pThis, DHookReturn hReturn) {
    if (CheckEliminationOrTimeout()) {
        return MRES_Supercede;
    }

    int m_iGameType = GameRules_GetProp("m_iGameType");
    if (m_iGameType == GAMETYPE_CTG) {
        if (CheckGhostCap()) {
            return MRES_Supercede;
        }
    }

    return MRES_Supercede;
}
