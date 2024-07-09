#include <sourcemod>
#include <dhooks>
#include <neotokyo>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "0.0.5"

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

ConVar g_cvTieBreaker;
ConVar g_cvSwapAttackers;
ConVar g_cvCapTime;

float g_fCapCompleteTime = -1.0;

public void OnPluginStart() {
    CreateDetour();

    HookEvent("game_round_start", Event_RoundStart);

    CreateConVar("sm_nt_wincond_version", PLUGIN_VERSION, "NT Win Condition version", FCVAR_DONTRECORD);
    g_cvTieBreaker = CreateConVar("sm_nt_wincond_tiebreaker", "0", "Tie breaker. 0 = disabled, 1 = team with most players alive wins, 2 = defending team wins", _, true, 0.0, true, 2.0);
    g_cvSwapAttackers = CreateConVar("sm_nt_wincond_swapattackers", "0", "When tie breaker is set to defending team, swap attackers/defenders. Might make some maps more playable.", _, true, 0.0, true, 1.0);
    g_cvCapTime = CreateConVar("sm_nt_wincond_captime", "0", "How long it takes to capture the ghost", _, true, 0.0);
}

void CreateDetour() {
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

Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast) {
    if (g_cvTieBreaker.IntValue == 2) {
        CreateTimer(10.0, AnnounceAttacker);
    }

    return Plugin_Continue;
}

Action AnnounceAttacker(Handle timer) {
    int m_iAttackingTeam = GameRules_GetProp("m_iAttackingTeam");
    if (m_iAttackingTeam == TEAM_JINRAI || (g_cvSwapAttackers.IntValue && m_iAttackingTeam == TEAM_NSF)) {
        PrintCenterTextAll("- Jinrai are attacking -");
    } else {
        PrintCenterTextAll("- NSF are attacking -");
    }

    return Plugin_Stop;
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
    static Handle call = INVALID_HANDLE;
    if (call == INVALID_HANDLE) {
        StartPrepSDKCall(SDKCall_Player);
        PrepSDKCall_SetReturnInfo(SDKType_Bool, SDKPass_Plain);
        PrepSDKCall_SetAddress(view_as<Address>(0x222F25C0));
        call = EndPrepSDKCall();
        if (call == INVALID_HANDLE) {
            SetFailState("Failed to prepare SDK call");
        }
    }
    return SDKCall(call, client);
}

bool GetOwner(Address ghost) {
    static Handle call = INVALID_HANDLE;
    if (call == INVALID_HANDLE) {
        StartPrepSDKCall(SDKCall_Raw);
        PrepSDKCall_SetReturnInfo(SDKType_CBasePlayer, SDKPass_Pointer);
        PrepSDKCall_SetAddress(view_as<Address>(0x223197E0));
        call = EndPrepSDKCall();
        if (call == INVALID_HANDLE) {
            SetFailState("Failed to prepare SDK call");
        }
    }
    return SDKCall(call, ghost);
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
    if (aliveNsf == 0 && aliveJinrai == 0) {
        EndRound(GAMEHUD_TIE);
        return true;
    }
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

    // Don't timeout if capping the ghost
    if (g_fCapCompleteTime > 0.0) {
        return false;
    }

    // Check timeout
    float roundTimeLeft = GameRules_GetPropFloat("m_fRoundTimeLeft");
    if (roundTimeLeft == 0.0) {
        if (g_cvTieBreaker.IntValue == 1) {
            // Reward team with most players alive
            if (aliveNsf < aliveJinrai) {
                RewardWin(TEAM_JINRAI);
                EndRound(GAMEHUD_JINRAI);
            } else if (aliveJinrai < aliveNsf) {
                RewardWin(TEAM_NSF);
                EndRound(GAMEHUD_NSF);
            } else {
                EndRound(GAMEHUD_TIE);
            }
            return true;
        }
        
        if (g_cvTieBreaker.IntValue == 2 || g_cvTieBreaker.IntValue == 3) {
            // Reward defending team
            int m_iAttackingTeam = GameRules_GetProp("m_iAttackingTeam");
            if (m_iAttackingTeam == TEAM_NSF || (g_cvSwapAttackers && m_iAttackingTeam == TEAM_JINRAI)) {
                RewardWin(TEAM_JINRAI);
                EndRound(GAMEHUD_JINRAI);
            } else {
                RewardWin(TEAM_NSF);
                EndRound(GAMEHUD_NSF);
            }
            return true;
        }

        // Always tie
        EndRound(GAMEHUD_TIE);
        return true;
    }

    return false;
}

bool CheckGhostCap() {
    int m_bFreezePeriod = GameRules_GetProp("m_bFreezePeriod");
    if (m_bFreezePeriod) {
        // Don't cap during freeze period, fixes the double cap bug.
        return false;
    }

    int numCapZones = LoadFromAddress(view_as<Address>(0x22542740), NumberType_Int32);
    Address capZoneList = view_as<Address>(LoadFromAddress(view_as<Address>(0x22542734), NumberType_Int32));
    int numGhosts = LoadFromAddress(view_as<Address>(0x225443B8), NumberType_Int32);
    Address ghostList = view_as<Address>(LoadFromAddress(view_as<Address>(0x225443AC), NumberType_Int32));
    for (int ghost = 0; ghost < numGhosts; ghost++) {
        Address p_ghost = view_as<Address>(LoadFromAddress(ghostList + view_as<Address>(ghost * 4), NumberType_Int32));
        int carrier = GetOwner(p_ghost);
        if (!IsValidClient(carrier)) {
            continue;
        }

        int carryingTeam = GetClientTeam(carrier);
        float ghostOrigin[3];
        GetClientAbsOrigin(carrier, ghostOrigin);

        for (int capZone = 0; capZone < numCapZones; capZone++) {
            Address p_capZone = view_as<Address>(LoadFromAddress(capZoneList + view_as<Address>(capZone * 4), NumberType_Int32));
            int m_OwningTeamNumber = LoadFromAddress(p_capZone + view_as<Address>(0x360), NumberType_Int32);
            if (carryingTeam == m_OwningTeamNumber) {
                float x = view_as<float>(LoadFromAddress(p_capZone + view_as<Address>(0x354), NumberType_Int32));
                float y = view_as<float>(LoadFromAddress(p_capZone + view_as<Address>(0x358), NumberType_Int32));
                float z = view_as<float>(LoadFromAddress(p_capZone + view_as<Address>(0x35C), NumberType_Int32));
                x = x - ghostOrigin[0];
                y = y - ghostOrigin[1];
                z = z - ghostOrigin[2];
                float distance = SquareRoot(x*x + y*y + z*z);
                int m_Radius = LoadFromAddress(p_capZone + view_as<Address>(0x364), NumberType_Int32);
                if (distance <= m_Radius) {
                    if (g_cvCapTime.FloatValue > 0.0) {
                        if (g_fCapCompleteTime < 0.0) {
                            g_fCapCompleteTime = GetGameTime() + g_cvCapTime.FloatValue;
                        }

                        if (GetGameTime() < g_fCapCompleteTime) {
                            PrintCenterTextAll("- %N is capturing the ghost! %.2f -", carrier, g_fCapCompleteTime - GetGameTime());
                            return false;
                        }
                    }

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
    g_fCapCompleteTime = -1.0;
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
