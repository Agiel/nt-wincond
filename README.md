# nt-wincond

Neotokyo SourceMod plugin that overrides and reimplements the win condition checks to allow modding.

## ConVars
_sm_nt_wincond_tiebreaker_  
0 = Disabled  
1 = Team with most players alive wins. I.e. vanilla NT.  
2 = Defending team wins

_sm_nt_wincond_swapattackers_  
When tie breaker is set to 2, swap attackers/defenders. Might make some maps more playable.  
0 = Disabled  
1 = Enabled

_sm_nt_wincond_captime_  
How many seconds should it take to capture the ghost.

## Changelog

### 0.0.5
* Add cvar for cap timer

### 0.0.4
* Fix double cap bug
* Add tiebreaker cvar

### 0.0.3
* Support multiple ghosts

### 0.0.2
* Announce ghost capper
* Consider players who haven't spawned in yet as alive for the purpose of rewarding points

### 0.0.1
* Initial release
