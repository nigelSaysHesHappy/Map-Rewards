#include <sourcemod>
#include <sdktools>
#include <string>
#include <sdkhooks>
#include <colors>
#include <strplus>

#define VERSION "0.188"

#define MAXSPAWNPOINT       128
#define MAXALIASES          128
#define MAXSCRIPTS          64
#define MAXINPUT            128

#define CLEAN_PLUG_END      1
#define CLEAN_MAP_START     2
#define CLEAN_ROUND_START   4
#define CLEAN_AUTO_LOAD     8
#define CLEAN_MAN_LOAD      16
#define CLEAN_KILL          4
#define CLEAN_RESET         3

#define LOAD_PLUG_START     1
#define LOAD_MAP_START      2
#define LOAD_ROUND_START    4

#define SAVE_PLUG_END       1
#define SAVE_MAP_START      2
#define SAVE_ROUND_START    4
#define SAVE_CLEANUP        8
#define SAVE_EDIT           16
#define SAVE_REMOVE         32
#define SAVE_BACKUP         64

#define HOOK_NOHOOK         0
#define HOOK_DEACTIVE       1
#define HOOK_TOUCH          2
#define HOOK_HURT           4
#define HOOK_STATIC         8
#define HOOK_CONSTANT       16
#define HOOK_KILL           32

public Plugin:myinfo =
{
    name = "Map Rewards",
    author = "NIGathan",
    description = "Setup custom rewards or pickups around the map. Or gmod, whatever.. I don't even know anymore.",
    version = VERSION,
    url = "http://sandvich.justca.me/"
};

/*    *    *    *    *    *    *    *\
\*                                  */
/*               TODO               *\
\*                                  */
/*          nothing to do!          */
/*                                  *\
\*    *    *    *    *    *    *    */

new Handle:c_enable = INVALID_HANDLE;
new Handle:c_respawnTime = INVALID_HANDLE;
new Handle:c_cleanUp = INVALID_HANDLE;
new Handle:c_autoLoad = INVALID_HANDLE;
new Handle:c_autoSave = INVALID_HANDLE;
new Handle:c_basicFlag = INVALID_HANDLE;
new Handle:c_createFlag = INVALID_HANDLE;
new Handle:c_extendedFlag = INVALID_HANDLE;

new Float:defSpawnCoords[MAXSPAWNPOINT][3];
new Float:defSpawnAngles[MAXSPAWNPOINT][3];
new spawnEnts[MAXSPAWNPOINT] = { -1, ... };
new String:rCommand[MAXSPAWNPOINT][2][MAXINPUT];
new String:model[MAXSPAWNPOINT][MAXINPUT];
new String:aliases[MAXALIASES][5][MAXINPUT];
new String:scripts[MAXSCRIPTS][2][MAXINPUT];
new String:script[MAXSPAWNPOINT][2][MAXINPUT];
new String:entType[MAXSPAWNPOINT][64];
new Float:respawnTime[MAXSPAWNPOINT] = { -1.0, ... };
new respawnMethod[MAXSPAWNPOINT];// = { -1, ... };
new String:entName[MAXSPAWNPOINT][32];
new Float:entSpin[MAXSPAWNPOINT][3];
new Float:entSpinInt[MAXSPAWNPOINT];
new Float:entSpinAngles[MAXSPAWNPOINT][3];
new Handle:entTimers[MAXSPAWNPOINT] = { INVALID_HANDLE, ... };
new rewardKiller[MAXSPAWNPOINT];
new Float:entHealth[MAXSPAWNPOINT];
new Float:entDamage[MAXSPAWNPOINT];
new aliasCount = 0;
new scriptCount = 0;
new newestReward = -1;

new g_enable;
new Float:g_respawnTime;
new g_cleanUp;
new g_autoLoad;
new g_autoSave;
new g_basicFlag = ADMFLAG_CONFIG;
new g_createFlag = ADMFLAG_RCON;
new g_extendedFlag = ADMFLAG_RCON;

public OnPluginStart()
{
    LoadTranslations("common.phrases");
    CreateConVar("sm_mrw_version", VERSION, "Map Rewards Version",FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD);
    
    c_enable = CreateConVar("sm_mrw_enable", "1.0", "0 = disabled. 1 = enabled", 0, true, 0.0, true, 1.0);
    c_respawnTime = CreateConVar("sm_mrw_respawn_time", "5.0", "Default seconds until a reward will respawn.", 0, true, 0.0);
    c_cleanUp = CreateConVar("sm_mrw_cleanup", "8", "When to release and kill all rewards. OR desired values together. 0: never, 1: plugin end, 2: map start, 4: round start, 8: on auto load, 16: on manual load", 0, true, 0.0, true, 31.0);
    c_autoLoad = CreateConVar("sm_mrw_autoload", "2", "When to auto load map or server cfg saves. OR desired values together. 0: never, 1: map start (maprewards/server.cfg), 2: map start (maprewards/<map>.cfg), 4: round start (maprewards/<map>.cfg)", 0, true, 0.0, true, 7.0);
    c_autoSave = CreateConVar("sm_mrw_autosave", "0", "When to auto save map cfg. OR desired values together. 0: never 1: plugin end, 2: map start (basically map end; internal data is still intact until cleanup), 4: round start (basically round end), 8: on clean up, 16: on every edit/addition that's not from the server, 32: on remove, 64: always backup first", 0, true, 0.0, true, 127.0);
    c_basicFlag = CreateConVar("sm_mrw_flag_basic", "i", "Admin flag required for basic mrw commands.", 0);
    c_createFlag = CreateConVar("sm_mrw_flag_create", "m", "Admin flag required for creating or modifying rewards.", 0);
    c_extendedFlag = CreateConVar("sm_mrw_flag_extended", "m", "Admin flag required for all sm_mrw_cfg_* commands except for load and list.", 0);

    RegConsoleCmd("sm_mrw_info", infoSpawnPoint, "Displays info about a specific reward spawn point.");
    RegConsoleCmd("sm_mrw_add", addSpawnPoint, "Sets a spawn point on the map for a reward.");
    RegConsoleCmd("sm_mrw_add_custom", addSpawnPointCustom, "DEPRECIATED! Sets a custom entity spawn point on the map for a reward.");
    RegConsoleCmd("sm_mrw_modify", modifySpawnPoint, "Modify a reward spawn point.");
    RegConsoleCmd("sm_mrw_remove", removeSpawnPoint, "Removes a reward on the map (starting with 0, not 1).");
    RegConsoleCmd("sm_mrw_removeall", removeSpawnPoints, "Removes all rewards on the map.");
    RegConsoleCmd("sm_mrw_model_reload", reloadAlias, "Reloads 'cfg/maprewards/aliases.cfg'.");
    RegConsoleCmd("sm_mrw_model_add", addAlias, "Adds a model alias. Does not save.");
    RegConsoleCmd("sm_mrw_model_save", saveAlias, "Saves the current model aliases to 'cfg/maprewards/aliases.cfg'.");
    RegConsoleCmd("sm_mrw_model_list", listAlias, "Lists all current model aliases.");
    RegConsoleCmd("sm_mrw_script_reload", reloadScript, "Reloads 'cfg/maprewards/scripts.cfg'.");
    RegConsoleCmd("sm_mrw_script_add", addScript, "Adds a script alias. Does not save.");
    RegConsoleCmd("sm_mrw_script_save", saveScript, "Saves the current scripts to 'cfg/maprewards/scripts.cfg'.");
    RegConsoleCmd("sm_mrw_script_list", listScript, "Lists all current scripts.");
    RegConsoleCmd("sm_mrw_cfg_save", writeCFG, "Saves current reward spawn points to a cfg file for later reuse.");
    RegConsoleCmd("sm_mrw_cfg_load", loadCFG, "Loads a saved maprewards cfg file.");
    RegConsoleCmd("sm_mrw_cfg_list", listSavedCFG, "Lists all saved maprewards cfg files.");
    RegConsoleCmd("sm_mrw_cfg_delete", deleteSavedCFG, "Deletes a saved maprewards cfg file.");
    RegConsoleCmd("sm_mrw_cfg_purge", purgeSavedCFG, "Deletes all auto-save backup maprewards cfg files.");
    RegConsoleCmd("sm_mrw_tp", tpPlayer, "Teleports you to the provided reward.");
    RegConsoleCmd("sm_mrw_move", moveReward, "Relatively moves a reward.");
    RegConsoleCmd("sm_mrw_turn", turnReward, "Relatively rotates a reward.");
    RegConsoleCmd("sm_mrw_copy", copyReward, "Creates an exact copy of a reward at the provided position.");
    RegConsoleCmd("sm_mrw_copy_here", copyRewardHere, "Creates an exact copy of a reward at your position.");
    RegConsoleCmd("sm_mrw_release", releaseReward, "Releases a reward from local memory. WARNING YOU WILL NOT BE ABLE TO ALTER OR SAVE ANY RELEASED ENTITIES.");
    RegConsoleCmd("sm_mrw_kill", killEntity, "Kills an entity by its edict ID. To be used with entities after releasing them.");
    RegConsoleCmd("sm_mrw_respawn", manuallyRespawnReward, "Respawn or reactivate a reward early.");
    RegAdminCmd("sm_exec2", exec2CFG, ADMFLAG_SLAY, "Executes a cfg file provided as the second argument. Accepts a first argument, but is ignored unless the third argument is '0'. If the third argument is anything else, it will be used instead of the player's name. Any additional arguments will be used instead of the default message.");
    RegAdminCmd("sm_teleplus", teleportCmd, ADMFLAG_SLAY, "Teleport a player to a set of coordinates with optional rotation and velocity. Relative coords, angles, and velocity are allowed.");
    
    HookEvent("teamplay_round_active", OnRoundStart, EventHookMode_PostNoCopy);

    HookConVarChange(c_enable, cvarEnableChange);
    HookConVarChange(c_respawnTime, cvarChange);
    HookConVarChange(c_cleanUp, cvarCleanChange);
    HookConVarChange(c_autoLoad, cvarLoadChange);
    HookConVarChange(c_autoSave, cvarSaveChange);
    HookConVarChange(c_basicFlag, cvarBasicFlagChange);
    HookConVarChange(c_createFlag, cvarCreateFlagChange);
    HookConVarChange(c_extendedFlag, cvarExtendedFlagChange);
    
    aliasCount = loadAliases();
    scriptCount = loadScripts();
}

stock RespondToCommand(client, const String:msg[], any:...)
{
    decl String:fmsg[250];
    VFormat(fmsg,250,msg,3);
    if (client != 0)
        ReplyToCommand(client,fmsg);
    else
        PrintToServer(fmsg);
}

stock CRespondToCommand(client, const String:msg[], any:...)
{
    decl String:fmsg[250];
    VFormat(fmsg,250,msg,3);
    if (client != 0)
        CPrintToChat(client,fmsg);
    else
    {
        ReplaceString(fmsg,250,"{default}","");
        ReplaceString(fmsg,250,"{green}","");
        ReplaceString(fmsg,250,"{lightgreen}","");
        ReplaceString(fmsg,250,"{red}","");
        ReplaceString(fmsg,250,"{blue}","");
        ReplaceString(fmsg,250,"{olive}","");
        ReplaceString(fmsg,250,"{teamcolor}","");
        PrintToServer(fmsg);
    }
}

stock CPrintToServer(const String:msg[], any:...)
{
    decl String:fmsg[1024];
    VFormat(fmsg,1024,msg,2);
    ReplaceString(fmsg,1024,"{default}","");
    ReplaceString(fmsg,1024,"{green}","");
    ReplaceString(fmsg,1024,"{lightgreen}","");
    ReplaceString(fmsg,1024,"{red}","");
    ReplaceString(fmsg,1024,"{blue}","");
    ReplaceString(fmsg,1024,"{olive}","");
    ReplaceString(fmsg,1024,"{teamcolor}","");
    PrintToServer(fmsg);
}

public cvarCleanChange(Handle:convar, const String:oldValue[], const String:newValue[])
{
    g_cleanUp = StringToInt(newValue);
}

public cvarLoadChange(Handle:convar, const String:oldValue[], const String:newValue[])
{
    g_autoLoad = StringToInt(newValue);
}

public cvarSaveChange(Handle:convar, const String:oldValue[], const String:newValue[])
{
    g_autoSave = StringToInt(newValue);
}

public Action:teleportCmd(client, args)
{
    if ((args != 4) && (args != 7) && (args != 10))
    {
        RespondToCommand(client,"[SM] Usage: sm_teleplus <#userid|name> <X Y Z> [RX RY RZ] [VX VY VZ]");
        return Plugin_Handled;
    }
    decl String:targetp[65];
    decl String:target_name[MAX_TARGET_LENGTH];
    decl target_list[MAXPLAYERS];
    decl bool:tn_is_ml;
    new target_count = 0;
    GetCmdArg(1,targetp,65);
    if ((target_count = ProcessTargetString(targetp,
                                     client,
                                     target_list,
                                     MAXPLAYERS,
                                     COMMAND_FILTER_ALIVE,
                                     target_name,
                                     sizeof(target_name),
                                     tn_is_ml)) <= 0)
    {
        ReplyToTargetError(client,target_count);
        return Plugin_Handled;
    }
    new nextArg = 2;
    new Float:coordsC[3][3];
    new Float:coordsO[3][3];
    new bool:relative[3][3];
    for (new h = 0;nextArg <= args;h++)
    {
        for (new i = 0;i < 3;i++)
        {
            GetCmdArg(nextArg++,targetp,16);
            if (targetp[0] == '~')
            {
                relative[h][i] = true;
                if (strlen(targetp) > 1)
                {
                    StrErase(targetp,0,1);
                    coordsC[h][i] += StringToFloat(targetp);
                }
            }
            else
                coordsC[h][i] = StringToFloat(targetp);
        }
    }
    for (new i = 0;i < target_count;i++)
    {
        GetClientAbsOrigin(target_list[i],coordsO[0]);
        GetClientEyeAngles(target_list[i],coordsO[1]);
        GetEntPropVector(target_list[i],Prop_Data,"m_vecVelocity",coordsO[2]);
        for (new h = 0;h < 3;h++)
            for (new o = 0;o < 3;o++)
                if (relative[h][o])
                    coordsC[h][o] += coordsO[h][o];
        TeleportEntity(target_list[i], coordsC[0], coordsC[1], coordsC[2]);
    }
    return Plugin_Handled;
}

/*public Action:execCFG(client, args)
{
    if (args < 1)
    {
        RespondToCommand(client,"[SM] Usage: sm_exec <cfg_file>");
        return Plugin_Handled;
    }
    decl String:temp0[32];
    decl String:temp1[36] = "cfg/";
    GetCmdArg(1,temp0,32);
    StrCat(temp1,32,temp0);
    StrCat(temp1,36,".cfg");
    if (FileSize(temp1) > 1)
    {
        ServerCommand("exec %s",temp0);
        RespondToCommand(client,"[SM] Executed '%s.cfg'.",temp0);
    }
    else
    {
        RespondToCommand(client,"[SM] Could not find cfg file '%s.cfg'",temp0);
    }
    return Plugin_Handled;
}*/

public Action:exec2CFG(client, args)
{
    if (args > 2)
    {
        decl String:targetp[65];
        decl String:target_name[MAX_TARGET_LENGTH];
        decl target_list[MAXPLAYERS];
        decl bool:tn_is_ml;
        GetCmdArg(1,targetp,65);
        decl String:opt_name[MAX_TARGET_LENGTH];
        GetCmdArg(3,opt_name,MAX_TARGET_LENGTH);
        new String:msg[128];
        if (args > 3)
        {
            decl String:buffer[128];
            for (new i = 4; i <= args; i++)
            {
                GetCmdArg(i,buffer,128);
                StrCat(msg,128,buffer);
                StrCat(msg,128," ");
            }
        }
        else
        {
            msg = "has earned a reward!";
        }
        if (strcmp(opt_name,"0") == 0)
        {
            if (ProcessTargetString(targetp,
                                    client,
                                    target_list,
                                    MAXPLAYERS,
                                    COMMAND_FILTER_ALIVE,
                                    target_name,
                                    sizeof(target_name),
                                    tn_is_ml) <= 0)
            {
                target_name = "Everyone";
            }
        }
        else
            target_name = opt_name;
        CPrintToChatAll("%c%s%c %s",0x04,target_name,0x01,msg);
        CPrintToServer("%s %s",target_name,msg);
        new Handle:fd = OpenFile("addons/sourcemod/halfbot/.chat-pipe","w+");
        if (fd != null)
        {
            new count = 0;
            count += ReplaceString(msg,128,"{default}","**");
            count += ReplaceString(msg,128,"{green}","**");
            count += ReplaceString(msg,128,"{lightgreen}","**");
            count += ReplaceString(msg,128,"{red}","**");
            count += ReplaceString(msg,128,"{blue}","**");
            count += ReplaceString(msg,128,"{olive}","**");
            count += ReplaceString(msg,128,"{teamcolor}","**");
            if ((count % 2) == 1)
                StrCat(msg,128,"**");
            WriteFileLine(fd,"**%s** %s",target_name,msg);
            CloseHandle(fd);
        }
    }
    if (args > 1)
    {
        decl String:cfg[32];
        GetCmdArg(2,cfg,32);
        ServerCommand("exec %s",cfg);
    }
    return Plugin_Handled;
}

public Action:listSavedCFG(client, args)
{
    if (client > 0)
    {
        new flagBits = GetUserFlagBits(client);
        if (((flagBits & ADMFLAG_ROOT) == 0) && ((flagBits & g_basicFlag) != g_basicFlag))
        {
            ReplyToCommand(client,"[SM] You do not have access to this command.");
            return Plugin_Handled;
        }
    }
    decl String:dir[128];
    new bool:topdir = true;
    dir = "cfg/maprewards/";
    if (args > 0)
    {
        decl String:buffer[112];
        GetCmdArg(1,buffer,112);
        while ((buffer[0] == '/') || (buffer[0] == '\\'))
            StrErase(buffer,0);
        if (StrFind(buffer,"..") > -1)
        {
            RespondToCommand(client,"[SM] Error: Illegal path.");
            return Plugin_Handled;
        }
        StrCat(dir,128,buffer);
        topdir = false;
    }
    new Handle:cfgs = OpenDirectory(dir);
    if (cfgs == INVALID_HANDLE)
    {
        RespondToCommand(client,"[SM] No saved CFG files found in '%s'.",dir);
        RespondToCommand(client,"[SM] Usage: sm_mrw_cfg_list [directory] - directory starts in 'cfg/maprewards/'.");
        return Plugin_Handled;
    }
    decl String:filename[128];
    decl FileType:filetype;
    new total = 0;
    while (ReadDirEntry(cfgs,filename,128,filetype))
    {
        if ((filetype != FileType_File) || (strcmp(filename,".") == 0) || (strcmp(filename,"..") == 0) || ((topdir) && ((strcmp(filename,"scripts.cfg") == 0) || (strcmp(filename,"aliases.cfg") == 0))))
            continue;
        RespondToCommand(client,"[SM] [%d] '%s'",++total,filename);
    }
    RespondToCommand(client,"[SM] Found %d saves in '%s'.",total,dir);
    return Plugin_Handled;
}

public Action:deleteSavedCFG(client, args)
{
    if (client > 0)
    {
        new flagBits = GetUserFlagBits(client);
        if (((flagBits & ADMFLAG_ROOT) == 0) && ((flagBits & g_extendedFlag) != g_extendedFlag))
        {
            ReplyToCommand(client,"[SM] You do not have access to this command.");
            return Plugin_Handled;
        }
    }
    decl String:filename[128];
    filename = "cfg/maprewards/";
    if (args < 1)
    {
        RespondToCommand(client,"[SM] Usage: sm_mrw_cfg_delete <cfg_file> - Path starts in 'cfg/maprewards/'.");
        return Plugin_Handled;
    }
    decl String:buffer[112];
    GetCmdArg(1,buffer,112);
    while ((buffer[0] == '/') || (buffer[0] == '\\'))
        StrErase(buffer,0);
    if (StrFind(buffer,"..") > -1)
    {
        RespondToCommand(client,"[SM] Error: Illegal path.");
        return Plugin_Handled;
    }
    StrCat(filename,128,buffer);
    if (!FileExists(filename))
    {
        RespondToCommand(client,"[SM] Error: '%s' file does not exist.",filename);
        return Plugin_Handled;
    }
    if (DeleteFile(filename))
        RespondToCommand(client,"[SM] Deleted '%s'.",filename);
    else
        RespondToCommand(client,"[SM] Error: Cannot delete file '%s'.",filename);
    return Plugin_Handled;
}

public Action:purgeSavedCFG(client, args)
{
    if (client > 0)
    {
        new flagBits = GetUserFlagBits(client);
        if (((flagBits & ADMFLAG_ROOT) == 0) && ((flagBits & g_extendedFlag) != g_extendedFlag))
        {
            ReplyToCommand(client,"[SM] You do not have access to this command.");
            return Plugin_Handled;
        }
    }
    if (DirExists("cfg/maprewards/backup"))
    {
        if (RemoveDir("cfg/maprewards/backup"))
            RespondToCommand(client,"[SM] Successfully purged all backup maprewards cfg files.");
        else
            RespondToCommand(client,"[SM] Error: Unable to delete 'cfg/maprewards/backup/'.");
    }
    else
        RespondToCommand(client,"[SM] No backups to purge.");
    return Plugin_Handled;
}

stock bool:isValidReward(id)
{
    if ((-1 < id) && (id < MAXSPAWNPOINT) && (strlen(entType[id]) > 0))
        return true;
    return false;
}

getNewestReward()
{
    if (!isValidReward(newestReward))
        for (newestReward = MAXSPAWNPOINT-1;newestReward > -1;newestReward--)
            if (isValidReward(newestReward))
                break;
    return newestReward;
}

public Action:releaseReward(client, args)
{
    if (client > 0)
    {
        new flagBits = GetUserFlagBits(client);
        if (((flagBits & ADMFLAG_ROOT) == 0) && ((flagBits & g_basicFlag) != g_basicFlag))
        {
            ReplyToCommand(client,"[SM] You do not have access to this command.");
            return Plugin_Handled;
        }
    }
    if (args < 1)
    {
        RespondToCommand(client,"[SM] Usage: sm_mrw_release <#id|name>");
        return Plugin_Handled;
    }
    decl String:buffer[32];
    GetCmdArg(1,buffer,32);
    new tempID = getRewardID(buffer,client);
    if (isValidReward(tempID))
    {
        decl String:cmdC[1024];
        buildRewardCmd(tempID,cmdC,1024);
        if (client == 0)
            PrintToServer("[MRW] %s",cmdC);
        else
            PrintToConsole(client, "[MRW] %s",cmdC);
        if (spawnEnts[tempID] == -1)
            spawnReward(tempID);
        new oldID = spawnEnts[tempID];
        resetReward(tempID);
        if (tempID == newestReward)
            getNewestReward();
        if (client != 0)
            autoSave(SAVE_EDIT,true);
        RespondToCommand(client,"[SM] Successfully released reward #%d. Hope you don't regret this!",tempID);
        RespondToCommand(client,"[SM] Check your console incase you need it back ;) If you need to remove it, the entity ID is #%d.",oldID);
    }
    else
        RespondToCommand(client, "[SM] Error: Unknown reward '%s'",buffer);
    return Plugin_Handled;
}

public Action:copyReward(client, args)
{
    if (client > 0)
    {
        new flagBits = GetUserFlagBits(client);
        if (((flagBits & ADMFLAG_ROOT) == 0) && ((flagBits & g_createFlag) != g_createFlag))
        {
            ReplyToCommand(client,"[SM] You do not have access to this command.");
            return Plugin_Handled;
        }
    }
    if ((args != 4) && (args != 7) && (args != 8) && (args != 9))
    {
        RespondToCommand(client,"[SM] Usage: sm_mrw_copy <#id|name> <X Y Z> [RX RY RZ] [new_name] [new_script]");
        return Plugin_Handled;
    }
    decl String:buffer[64];
    GetCmdArg(1,buffer,64);
    new tempID = getRewardID(buffer,client);
    if (!isValidReward(tempID))
    {
        RespondToCommand(client, "[SM] Error: Unknown reward '%s'",buffer);
        return Plugin_Handled;
    }
    new spawnPoints = newEnt();
    if (spawnPoints >= MAXSPAWNPOINT)
    {
        RespondToCommand(client, "[SM] No more room for rewards! :( Use sm_mrw_removeall to reset.");
        return Plugin_Handled;
    }
    new nextArg = 2;
    defSpawnAngles[spawnPoints] = defSpawnAngles[tempID];
    for (new i = 0;i < 3;i++)
    {
        GetCmdArg(nextArg++,buffer,64);
        defSpawnCoords[spawnPoints][i] = defSpawnCoords[tempID][i] + StringToInt(buffer);
    }
    if (nextArg < args)
    {
        for (new i = 0;i < 3;i++)
        {
            GetCmdArg(nextArg++,buffer,64);
            defSpawnAngles[spawnPoints][i] += StringToInt(buffer);
        }
    }
    model[spawnPoints] = model[tempID];
    rCommand[spawnPoints][0] = rCommand[tempID][0];
    rCommand[spawnPoints][1] = rCommand[tempID][1];
    entType[spawnPoints] = entType[tempID];
    script[spawnPoints][1] = script[tempID][1];
    respawnMethod[spawnPoints] = respawnMethod[tempID];
    respawnTime[spawnPoints] = respawnTime[tempID];
    entSpin[spawnPoints] = entSpin[tempID];
    entSpinInt[spawnPoints] = entSpinInt[spawnPoints];
    if (args > 7)
        GetCmdArg(8,entName[spawnPoints],32);
    else
        IntToString(spawnPoints,entName[spawnPoints],32);
    if (args > 8)
    {
        GetCmdArg(9,buffer,64);
        if (strcmp(buffer,"0") != 0)
        {
            for (new i = 0;i < scriptCount;i++)
            {
                if (strcmp(buffer,scripts[i][0]) == 0)
                {
                    strcopy(buffer,64,scripts[i][1]);
                    break;
                }
            }
        }
        script[spawnPoints][0] = buffer;
    }
    else
        script[spawnPoints][0] = script[tempID][0];
    if (g_enable)
        spawnReward(spawnPoints);
    if (client != 0)
        autoSave(SAVE_EDIT,true);
    RespondToCommand(client, "[SM] Added reward spawn point #%d", spawnPoints);
    return Plugin_Handled;
}

public Action:copyRewardHere(client, args)
{
    if (client > 0)
    {
        new flagBits = GetUserFlagBits(client);
        if (((flagBits & ADMFLAG_ROOT) == 0) && ((flagBits & g_createFlag) != g_createFlag))
        {
            ReplyToCommand(client,"[SM] You do not have access to this command.");
            return Plugin_Handled;
        }
    }
    if (args < 1)
    {
        RespondToCommand(client,"[SM] Usage: sm_mrw_copy_here <#id|name> [new_name] [new_script]");
        return Plugin_Handled;
    }
    decl String:buffer[64];
    GetCmdArg(1,buffer,64);
    new tempID = getRewardID(buffer,client);
    if (!isValidReward(tempID))
    {
        RespondToCommand(client, "[SM] Error: Unknown reward '%s'",buffer);
        return Plugin_Handled;
    }
    new spawnPoints = newEnt();
    if (spawnPoints >= MAXSPAWNPOINT)
    {
        RespondToCommand(client, "[SM] No more room for rewards! :( Use sm_mrw_removeall to reset.");
        return Plugin_Handled;
    }
    if (args > 1)
        GetCmdArg(2,entName[spawnPoints],32);
    else
        IntToString(spawnPoints,entName[spawnPoints],32);
    if (args > 2)
    {
        GetCmdArg(2,buffer,64);
        if (strcmp(buffer,"0") != 0)
        {
            for (new i = 0;i < scriptCount;i++)
            {
                if (strcmp(buffer,scripts[i][0]) == 0)
                {
                    strcopy(buffer,64,scripts[i][1]);
                    break;
                }
            }
        }
        script[spawnPoints][0] = buffer;
    }
    else
        script[spawnPoints][0] = script[tempID][0];
    if ((client > 0) && (IsClientInGame(client)))
        GetClientAbsOrigin(client,defSpawnCoords[spawnPoints]);
    else
    //{
        defSpawnCoords[spawnPoints] = defSpawnCoords[tempID];
        //defSpawnCoords[spawnPoints][0] = defSpawnCoords[tempID][0];
        //defSpawnCoords[spawnPoints][1] = defSpawnCoords[tempID][1];
        //defSpawnCoords[spawnPoints][2] = defSpawnCoords[tempID][2];
    //}
    defSpawnAngles[spawnPoints] = defSpawnAngles[tempID];
    //defSpawnAngles[spawnPoints][0] = defSpawnAngles[tempID][0];
    //defSpawnAngles[spawnPoints][1] = defSpawnAngles[tempID][1];
    //defSpawnAngles[spawnPoints][2] = defSpawnAngles[tempID][2];
    model[spawnPoints] = model[tempID];
    rCommand[spawnPoints][0] = rCommand[tempID][0];
    rCommand[spawnPoints][1] = rCommand[tempID][1];
    script[spawnPoints][1] = script[tempID][1];
    entType[spawnPoints] = entType[tempID];
    respawnMethod[spawnPoints] = respawnMethod[tempID];
    respawnTime[spawnPoints] = respawnTime[tempID];
    entSpin[spawnPoints] = entSpin[tempID];
    entSpinInt[spawnPoints] = entSpinInt[spawnPoints];
    if (g_enable)
        spawnReward(spawnPoints);
    if (client != 0)
        autoSave(SAVE_EDIT,true);
    RespondToCommand(client, "[SM] Added reward spawn point #%d", spawnPoints);
    return Plugin_Handled;
}

public Action:moveReward(client, args)
{
    if (client > 0)
    {
        new flagBits = GetUserFlagBits(client);
        if (((flagBits & ADMFLAG_ROOT) == 0) && ((flagBits & g_basicFlag) != g_basicFlag))
        {
            ReplyToCommand(client,"[SM] You do not have access to this command.");
            return Plugin_Handled;
        }
    }
    if (args < 4)
    {
        RespondToCommand(client,"[SM] Usage: sm_mrw_move <#id|name> <X Y Z>");
        return Plugin_Handled;
    }
    decl String:buffer[32];
    GetCmdArg(1,buffer,32);
    new tempID = getRewardID(buffer,client);
    tempID = StringToInt(buffer);
    if (!isValidReward(tempID))
    {
        RespondToCommand(client, "[SM] Error: Unknown reward '%s'",buffer);
        return Plugin_Handled;
    }
    GetCmdArg(2,buffer,16);
    defSpawnCoords[tempID][0] += StringToFloat(buffer);
    GetCmdArg(3,buffer,16);
    defSpawnCoords[tempID][1] += StringToFloat(buffer);
    GetCmdArg(4,buffer,16);
    defSpawnCoords[tempID][2] += StringToFloat(buffer);
    TeleportEntity(spawnEnts[tempID], defSpawnCoords[tempID], defSpawnAngles[tempID], NULL_VECTOR);
    if (client != 0)
        autoSave(SAVE_EDIT,true);
    return Plugin_Handled;
}

public Action:turnReward(client, args)
{
    if (client > 0)
    {
        new flagBits = GetUserFlagBits(client);
        if (((flagBits & ADMFLAG_ROOT) == 0) && ((flagBits & g_basicFlag) != g_basicFlag))
        {
            ReplyToCommand(client,"[SM] You do not have access to this command.");
            return Plugin_Handled;
        }
    }
    if (args < 4)
    {
        RespondToCommand(client,"[SM] Usage: sm_mrw_turn <#id|name> <RX RY RZ>");
        return Plugin_Handled;
    }
    decl String:buffer[16];
    GetCmdArg(1,buffer,16);
    new tempID = getRewardID(buffer,client);
    if (!isValidReward(tempID))
    {
        RespondToCommand(client, "[SM] Error: Unknown reward '%s'",buffer);
        return Plugin_Handled;
    }
    GetCmdArg(2,buffer,16);
    defSpawnAngles[tempID][0] += StringToFloat(buffer);
    defSpawnAngles[tempID][0] = float(RoundToFloor(defSpawnAngles[tempID][0]) % 360);
    GetCmdArg(3,buffer,16);
    defSpawnAngles[tempID][1] += StringToFloat(buffer);
    defSpawnAngles[tempID][1] = float(RoundToFloor(defSpawnAngles[tempID][1]) % 360);
    GetCmdArg(4,buffer,16);
    defSpawnAngles[tempID][2] += StringToFloat(buffer);
    defSpawnAngles[tempID][2] = float(RoundToFloor(defSpawnAngles[tempID][2]) % 360);
    TeleportEntity(spawnEnts[tempID], defSpawnCoords[tempID], defSpawnAngles[tempID], NULL_VECTOR);
    if (client != 0)
        autoSave(SAVE_EDIT,true);
    return Plugin_Handled;
}

public Action:tpPlayer(client, args)
{
    if (client > 0)
    {
        new flagBits = GetUserFlagBits(client);
        if (((flagBits & ADMFLAG_ROOT) == 0) && ((flagBits & g_basicFlag) != g_basicFlag))
        {
            ReplyToCommand(client,"[SM] You do not have access to this command.");
            return Plugin_Handled;
        }
    }
    if (args < 1)
    {
        RespondToCommand(client,"[SM] Usage: sm_mrw_tp <#id|name> [#userid|name] [X Y Z] [RX RY RZ] [VX VY VZ]");
        return Plugin_Handled;
    }
    decl String:target[32];
    decl String:target_name[MAX_NAME_LENGTH];
    decl target_list[MAXPLAYERS];
    decl target_count;
    decl bool:tn_is_ml;
    GetCmdArg(1,target,32);
    new tempID = getRewardID(target,client);
    if (!isValidReward(tempID))
    {
        RespondToCommand(client, "[SM] Error: Unknown reward '%s'",target);
        return Plugin_Handled;
    }
    new Float:rCoords[4][3];
    //rCoords[0] = defSpawnCoords[tempID];
    //rCoords[1] = defSpawnAngles[tempID];
    if (spawnEnts[tempID] > -1)
    {
        GetEntPropVector(spawnEnts[tempID],Prop_Data,"m_vecOrigin",rCoords[0]);
        GetEntPropVector(spawnEnts[tempID],Prop_Data,"m_angRotation",rCoords[1]);
    }
    else
    {
        rCoords[0] = defSpawnCoords[tempID];
        rCoords[1] = defSpawnAngles[tempID];
    }
    new bool:relativeV[4];
    new nextArg = 2;
    switch (args)
    {
        case 1, 4, 7, 10:
        {
            target_list[0] = client;
            target_count = 1;
        }
        case 2, 5, 8, 11:
        {
            GetCmdArg(nextArg++,target,32);        
            if ((target_count = ProcessTargetString(
                    target,
                    client,
                    target_list,
                    MAXPLAYERS,
                    COMMAND_FILTER_ALIVE,
                    target_name,
                    sizeof(target_name),
                    tn_is_ml)) <= 0)
            {
                ReplyToTargetError(client, target_count);
                return Plugin_Handled;
            }
        }
        default:
        {
            RespondToCommand(client,"[SM] Usage: sm_mrw_tp <#id|name> [#userid|name] [X Y Z] [RX RY RZ] [VX VY VZ]");
            return Plugin_Handled;
        }
    }
    decl String:temp[16];
    for (new h = 0;nextArg <= args;h++)
    {
        for (new i = 0;i < 3;i++)
        {
            GetCmdArg(nextArg++,temp,16);
            if (temp[0] == '~')
            {
                if (h == 2)
                    relativeV[3] = relativeV[i] = true;
                if (strlen(temp) > 1)
                {
                    StrErase(temp,0,1);
                    rCoords[h][i] += StringToFloat(temp);
                }
            }
            else
                rCoords[h][i] = StringToFloat(temp);
        }
    }
    rCoords[3] = rCoords[2];
    for (new i = 0;i < target_count;i++)
    {
        if (relativeV[3])
        {
            GetEntPropVector(target_list[i],Prop_Data,"m_vecVelocity",rCoords[3]);
            for (new h = 0;h < 3;h++)
                if (relativeV[h])
                    rCoords[3][h] += rCoords[2][h];
        }
        TeleportEntity(target_list[i], rCoords[0], rCoords[1], rCoords[3]);
    }
    return Plugin_Handled;
}

stock buildRewardCmd(index, String:cmdC[], cmdSize, bool:relative = false, const Float:originC[3] = { 0.0, 0.0, 0.0 })
{
    decl Float:coordsC[3];
    coordsC = defSpawnCoords[index];
    if (relative)
    {
        //Format(cmdC,cmdSize,"sm_mrw_add -o %f %f %f",origin[0],origin[1],origin[2]);
        for (new i = 0;i < 3;i++)
            coordsC[i] -= originC[i];
        Format(cmdC,cmdSize,"sm_mrw_add -c ~%f ~%f ~%f",coordsC[0],coordsC[1],coordsC[2]);
    }
    else
        Format(cmdC,cmdSize,"sm_mrw_add -c %f %f %f",coordsC[0],coordsC[1],coordsC[2]);
    if ((defSpawnAngles[index][0] != 0.0) || (defSpawnAngles[index][1] != 0.0) || (defSpawnAngles[index][2] != 0.0))
        Format(cmdC,cmdSize,"%s -r %f %f %f",cmdC,defSpawnAngles[index][0],defSpawnAngles[index][1],defSpawnAngles[index][2]);
    if (strcmp(entType[index],"prop_physics_override") != 0)
        Format(cmdC,cmdSize,"%s -e %s",cmdC,entType[index]);
    if (strlen(model[index]) > 0)
        Format(cmdC,cmdSize,"%s -m %s",cmdC,model[index]);
    if (((index > 0) && (StringToInt(entName[index]) != index)) || ((index == 0) && (strcmp(entName[index],"0") != 0)))
        Format(cmdC,cmdSize,"%s -n %s",cmdC,entName[index]);
    if (strlen(script[index][0]) > 0)
        Format(cmdC,cmdSize,"%s -s %s",cmdC,script[index][0]);
    if (strlen(script[index][1]) > 0)
        Format(cmdC,cmdSize,"%s -p %s",cmdC,script[index][1]);
    if (entSpinInt[index] > 0.0)
        Format(cmdC,cmdSize,"%s -T %f %f %f %.1f",cmdC,entSpin[index][0],entSpin[index][1],entSpin[index][2],entSpinInt[index]);
    if (respawnMethod[index] != HOOK_NOHOOK)
    {
        /*switch (respawnMethod[index])
        {
            case 0: StrCat(cmdC,cmdSize," -P");
            case 1: StrCat(cmdC,cmdSize," -S");
            case 2: StrCat(cmdC,cmdSize," -C");
            default: Format(cmdC,cmdSize,"%s -d %i",cmdC,respawnMethod[index]);
        }*/
        Format(cmdC,cmdSize,"%s -d %i",cmdC,(respawnMethod[index] & ~HOOK_DEACTIVE));
        if (respawnTime[index] >= 0.0)
            Format(cmdC,cmdSize,"%s -t %.2f",cmdC,respawnTime[index]);
        if (entHealth[index] > 0.0)
            Format(cmdC,cmdSize,"%s -A %.2f",cmdC,entHealth[index]);
        if ((strlen(rCommand[index][0]) > 0) && (strcmp(rCommand[index][0],"null") != 0))
        {
            Format(cmdC,cmdSize,"%s \"%s\"",cmdC,rCommand[index][0]);
            if (strlen(rCommand[index][1]) > 0)
                Format(cmdC,cmdSize,"%s\nsm_mrw_modify -1 -X \"%s\"",cmdC,rCommand[index][1]);
        }
        else if (strlen(rCommand[index][1]) > 0)
            Format(cmdC,cmdSize,"%s -X \"%s\"",cmdC,rCommand[index][1]);
    }
}

public Action:infoSpawnPoint(client, args)
{
    if (client > 0)
    {
        new flagBits = GetUserFlagBits(client);
        if (((flagBits & ADMFLAG_ROOT) == 0) && ((flagBits & g_basicFlag) != g_basicFlag))
        {
            ReplyToCommand(client,"[SM] You do not have access to this command.");
            return Plugin_Handled;
        }
    }
    if (args < 1)
    {
        RespondToCommand(client,"[SM] Usage: sm_mrw_info <#id|name>");
        return Plugin_Handled;
    }
    decl String:buffer[32];
    GetCmdArg(1,buffer,32);
    new tempID = getRewardID(buffer,client);
    if (!isValidReward(tempID))
    {
        RespondToCommand(client, "[SM] Unknown reward '%s'",buffer);
        return Plugin_Handled;
    }
    decl String:cmdC[1024];
    buildRewardCmd(tempID,cmdC,1024);
    RespondToCommand(client,"[SM] Info on #%d(%d): X=%.1f Y=%.1f Z=%.1f RX=%.1f RY=%.1f RZ=%.1f",tempID,spawnEnts[tempID],defSpawnCoords[tempID][0],defSpawnCoords[tempID][1],defSpawnCoords[tempID][2],defSpawnAngles[tempID][0],defSpawnAngles[tempID][1],defSpawnAngles[tempID][2]);
    RespondToCommand(client,"[SM] Model: %s",model[tempID]);
    if (strlen(rCommand[tempID][0]) > 0)
        RespondToCommand(client,"[SM] Touch Command: %s",rCommand[tempID][0]);
    if (strlen(rCommand[tempID][1]) > 0)
        RespondToCommand(client,"[SM] Kill Command: %s",rCommand[tempID][1]);
    RespondToCommand(client,"[SM] Spawn scripts: [%s] [%s]",script[tempID][0],script[tempID][1]);
    RespondToCommand(client,"[SM] %s",cmdC);
    return Plugin_Handled;
}

public Action:listAlias(client, args)
{
    if (client > 0)
    {
        new flagBits = GetUserFlagBits(client);
        if (((flagBits & ADMFLAG_ROOT) == 0) && ((flagBits & g_basicFlag) != g_basicFlag))
        {
            ReplyToCommand(client,"[SM] You do not have access to this command.");
            return Plugin_Handled;
        }
    }
    for (new i = 0;i < aliasCount;i++)
        RespondToCommand(client,"[SM] #%d: '%s' = '%s' (%s) : '%s' : '%s'",i,aliases[i][0],aliases[i][1],aliases[i][2],aliases[i][3],aliases[i][4]);
    return Plugin_Handled;
}

public Action:reloadAlias(client, args)
{
    if (client > 0)
    {
        new flagBits = GetUserFlagBits(client);
        if (((flagBits & ADMFLAG_ROOT) == 0) && ((flagBits & g_basicFlag) != g_basicFlag))
        {
            ReplyToCommand(client,"[SM] You do not have access to this command.");
            return Plugin_Handled;
        }
    }
    aliasCount = loadAliases();
    RespondToCommand(client,"[SM] Successfully loaded %d aliases.",aliasCount);
    return Plugin_Handled;
}

public Action:addAlias(client, args)
{
    if (client > 0)
    {
        new flagBits = GetUserFlagBits(client);
        if (((flagBits & ADMFLAG_ROOT) == 0) && ((flagBits & g_basicFlag) != g_basicFlag))
        {
            ReplyToCommand(client,"[SM] You do not have access to this command.");
            return Plugin_Handled;
        }
    }
    if (args < 2)
    {
        RespondToCommand(client, "[SM] Usage: sm_mrw_model_add <name> <model> [entity_type] [overridescript] [entity_properties]");
        return Plugin_Handled;
    }
    decl String:buffer[MAXINPUT];
    GetCmdArg(1, buffer, MAXINPUT);
    strcopy(aliases[aliasCount][0],MAXINPUT,buffer);
    new marg = args;
    if (marg > 5)
        marg = 5;
    for (new i = 2;i <= marg;i++)
    {
        GetCmdArg(i, buffer, sizeof(buffer));
        if ((strcmp(buffer,"0") != 0) && (strcmp(buffer,"null") != 0))
            strcopy(aliases[aliasCount][i-1],MAXINPUT,buffer);
    }
    RespondToCommand(client, "[SM] Added alias #%d '%s' as '%s' (%s). Override: '%s' EntProp: '%s'.",aliasCount,aliases[aliasCount][0],aliases[aliasCount][1],aliases[aliasCount][2],aliases[aliasCount][3],aliases[aliasCount][4]);
    aliasCount++;
    return Plugin_Handled;
}

public Action:saveAlias(client, args)
{
    if (client > 0)
    {
        new flagBits = GetUserFlagBits(client);
        if (((flagBits & ADMFLAG_ROOT) == 0) && ((flagBits & g_basicFlag) != g_basicFlag))
        {
            ReplyToCommand(client,"[SM] You do not have access to this command.");
            return Plugin_Handled;
        }
    }
    if (writeAliases())
        RespondToCommand(client, "[SM] Successfully saved 'cfg/maprewards/aliases.cfg' file.");
    else
        RespondToCommand(client, "[SM] Some kind of error has occurred trying to save 'cfg/maprewards/aliases.cfg' file.");
    return Plugin_Handled;
}

resetAliases()
{
    for (new i = 0;i < MAXALIASES;i++)
    {
        strcopy(aliases[i][0],MAXINPUT,"");
        strcopy(aliases[i][1],MAXINPUT,"");
        strcopy(aliases[i][2],MAXINPUT,"");
        strcopy(aliases[i][3],MAXINPUT,"");
    }
    aliasCount = 0;
}

loadAliases()
{
    resetAliases();
    if (DirExists("cfg/maprewards") == false)
        CreateDirectory("cfg/maprewards",511);
    new i = 0;
    if (FileSize("cfg/maprewards/aliases.cfg") > 4)
    {
        new Handle:iFile = OpenFile("cfg/maprewards/aliases.cfg","r");
        decl String:buffer[1024];
        while (ReadFileLine(iFile,buffer,1024))
        {
            TrimString(buffer);
            if (strcmp(buffer,"") == 0)
                continue;
            if (ExplodeString(buffer,"@",aliases[i],5,MAXINPUT,true) > 1)
                i++;
            if (i >= MAXALIASES)
                break;
        }
        CloseHandle(iFile);
    }
    return i;
}

writeAliases()
{
    if (DirExists("cfg/maprewards") == false)
        CreateDirectory("cfg/maprewards",511);
    if (FileExists("cfg/maprewards/aliases.cfg"))
    {
        DeleteFile("cfg/maprewards/aliases.cfg.bak");
        RenameFile("cfg/maprewards/aliases.cfg.bak","cfg/maprewards/aliases.cfg");
    }
    new Handle:oFile = OpenFile("cfg/maprewards/aliases.cfg","w");
    for (new i = 0;i < aliasCount;i++)
        WriteFileLine(oFile,"%s@%s@%s@%s@%s",aliases[i][0],aliases[i][1],aliases[i][2],aliases[i][3],aliases[i][4]);
    CloseHandle(oFile);
    return FileExists("cfg/maprewards/aliases.cfg");
}

public Action:listScript(client, args)
{
    if (client > 0)
    {
        new flagBits = GetUserFlagBits(client);
        if (((flagBits & ADMFLAG_ROOT) == 0) && ((flagBits & g_basicFlag) != g_basicFlag))
        {
            ReplyToCommand(client,"[SM] You do not have access to this command.");
            return Plugin_Handled;
        }
    }
    for (new i = 0;i < scriptCount;i++)
        RespondToCommand(client,"[SM] #%d: '%s' = '%s'",i,scripts[i][0],scripts[i][1]);
    return Plugin_Handled;
}

public Action:reloadScript(client, args)
{
    if (client > 0)
    {
        new flagBits = GetUserFlagBits(client);
        if (((flagBits & ADMFLAG_ROOT) == 0) && ((flagBits & g_basicFlag) != g_basicFlag))
        {
            ReplyToCommand(client,"[SM] You do not have access to this command.");
            return Plugin_Handled;
        }
    }
    scriptCount = loadScripts();
    RespondToCommand(client,"[SM] Successfully loaded %d scripts.",scriptCount);
    return Plugin_Handled;
}

public Action:addScript(client, args)
{
    if (client > 0)
    {
        new flagBits = GetUserFlagBits(client);
        if (((flagBits & ADMFLAG_ROOT) == 0) && ((flagBits & g_basicFlag) != g_basicFlag))
        {
            ReplyToCommand(client,"[SM] You do not have access to this command.");
            return Plugin_Handled;
        }
    }
    if (args < 2)
    {
        RespondToCommand(client, "[SM] Usage: sm_mrw_script_add <name> <script>");
        return Plugin_Handled;
    }
    decl String:buffer[MAXINPUT];
    GetCmdArg(1, buffer, sizeof(buffer));
    strcopy(scripts[scriptCount][0],MAXINPUT,buffer);
    GetCmdArg(2, buffer, sizeof(buffer));
    strcopy(scripts[scriptCount][1],MAXINPUT,buffer);
    RespondToCommand(client, "[SM] Added script #%d '%s' as '%s'.",scriptCount,scripts[scriptCount][0],scripts[scriptCount][1]);
    scriptCount++;
    return Plugin_Handled;
}

public Action:saveScript(client, args)
{
    if (client > 0)
    {
        new flagBits = GetUserFlagBits(client);
        if (((flagBits & ADMFLAG_ROOT) == 0) && ((flagBits & g_basicFlag) != g_basicFlag))
        {
            ReplyToCommand(client,"[SM] You do not have access to this command.");
            return Plugin_Handled;
        }
    }
    if (writeScripts())
        RespondToCommand(client, "[SM] Successfully saved 'cfg/maprewards/scripts.cfg' file.");
    else
        RespondToCommand(client, "[SM] Some kind of error has occurred trying to save 'cfg/maprewards/scripts.cfg' file.");
    return Plugin_Handled;
}

resetScripts()
{
    for (new i = 0;i < MAXSCRIPTS;i++)
    {
        strcopy(scripts[i][0],MAXINPUT,"");
        strcopy(scripts[i][1],MAXINPUT,"");
    }
    scriptCount = 0;
}

loadScripts()
{
    resetScripts();
    if (DirExists("cfg/maprewards") == false)
        CreateDirectory("cfg/maprewards",511);
    new i = 0;
    if (FileSize("cfg/maprewards/scripts.cfg") > 4)
    {
        new Handle:iFile = OpenFile("cfg/maprewards/scripts.cfg","r");
        decl String:buffer[MAXINPUT];
        while (ReadFileLine(iFile,buffer,MAXINPUT))
        {
            TrimString(buffer);
            if (strcmp(buffer,"") == 0)
                continue;
            if (ExplodeString(buffer," ",scripts[i],2,MAXINPUT,true) > 1)
                i++;
            if (i >= MAXALIASES)
                break;
        }
        CloseHandle(iFile);
    }
    return i;
}

writeScripts()
{
    if (DirExists("cfg/maprewards") == false)
        CreateDirectory("cfg/maprewards",511);
    if (FileExists("cfg/maprewards/scripts.cfg"))
    {
        DeleteFile("cfg/maprewards/scripts.cfg.bak");
        RenameFile("cfg/maprewards/scripts.cfg.bak","cfg/maprewards/scripts.cfg");
    }
    new Handle:oFile = OpenFile("cfg/maprewards/scripts.cfg","w");
    for (new i = 0;i < scriptCount;i++)
        WriteFileLine(oFile,"%s %s",scripts[i][0],scripts[i][1]);
    CloseHandle(oFile);
    return FileExists("cfg/maprewards/scripts.cfg");
}

RespondWriteUsage(client)
{
    CRespondToCommand(client,"[SM] Usage: {green}sm_mrw_cfg_save{default} [{green}OPTIONS{default} ...] <{green}file.cfg{default}>");
    CRespondToCommand(client,"[SM]    {green}file.cfg{default} is the cfg file to save to. It will be stored within {green}cfg/maprewards/{default}.");
    CRespondToCommand(client,"[SM]    {green}OPTIONS{default}:");
    CRespondToCommand(client,"[SM]       -E <{green}reward_id|name{default}>");
    CRespondToCommand(client,"[SM]          Exclude {green}reward_id{default} from the cfg.");
    CRespondToCommand(client,"[SM]          Allows a range: {green}#..#{default}, {green}..#{default}, or {green}#..");
    CRespondToCommand(client,"[SM]          Ranges do not accept reward names, only their ID numbers.");
    CRespondToCommand(client,"[SM]          Multiple {green}-E{default} switches are accepted.");
    CRespondToCommand(client,"[SM]       -o <{green}X Y Z{default}>");
    CRespondToCommand(client,"[SM]          Set the origin coordinates. Only used if the {green}-R{default} switch is also set.");
    CRespondToCommand(client,"[SM]          The origin will default to your location (or 0,0,0 for the server) unless this option is present.");
    CRespondToCommand(client,"[SM]          Relative coordinates can be used to offset from your current coordinates.");
    CRespondToCommand(client,"[SM]       -O <{green}#userid|name{default}>");
    CRespondToCommand(client,"[SM]          Set the origin coordinates to a player's location.");
    CRespondToCommand(client,"[SM]          May be used in conjunction with {green}-o{default} to offset from a player as long as {green}-O{default} is provided first.");
    CRespondToCommand(client,"[SM]       -D <{green}#reward_id|name{default}>");
    CRespondToCommand(client,"[SM]          Set the origin coordinates to a reward's location.");
    CRespondToCommand(client,"[SM]       -R");
    CRespondToCommand(client,"[SM]          Save the rewards with coordinates relative to the origin.");
    CRespondToCommand(client,"[SM]          If this switch is not present, the {green}-o{default}, {green}-O{default}, and {green}-D{default} switches will be ignored.");
    CRespondToCommand(client,"[SM]       -f");
    CRespondToCommand(client,"[SM]          Force the saving of the file, even if a file with the same name already exists.");
}

public Action:writeCFG(client, args)
{
    if (client > 0)
    {
        new flagBits = GetUserFlagBits(client);
        if (((flagBits & ADMFLAG_ROOT) == 0) && ((flagBits & g_extendedFlag) != g_extendedFlag))
        {
            ReplyToCommand(client,"[SM] You do not have access to this command.");
            return Plugin_Handled;
        }
    }
    if (args < 1)
    {
        RespondWriteUsage(client);
        return Plugin_Handled;
    }
    decl String:buffer[128];
    new nextArg = 1;
    new bool:lastArg = false;
    new bool:rewards[MAXSPAWNPOINT] = { true, ... };
    new bool:relative = false;
    new bool:force = false;
    new Float:originC[3];
    if ((client > 0) && (IsClientInGame(client)))
        GetClientAbsOrigin(client,originC);
    new bool:err = false;
    for (;nextArg <= args;nextArg++)
    {
        if (nextArg == args)
            lastArg = true;
        GetCmdArg(nextArg,buffer,128);
        if (buffer[0] == '-')
        {
            if (buffer[1] == '-')
            {
                nextArg++;
                break;
            }
            switch (buffer[1])
            {
                case 'R': // Relative
                {
                    relative = true;
                }
                case 'E': // Exclude reward #
                {
                    if (lastArg)
                        err = true;
                    else
                    {
                        GetCmdArg(++nextArg,buffer,128);
                        new blen = strlen(buffer);
                        new dots = StrFind(buffer,"..",0);
                        new range[2] = { -1, -1 };
                        switch (dots)
                        {
                            case -1:
                            {
                                range[0] = range[1] = getRewardID(buffer,client);
                            }
                            case 0:
                            {
                                if (blen > 2)
                                {
                                    range[0] = 0;
                                    StrErase(buffer,0,2);
                                    range[1] = StringToInt(buffer);
                                }
                            }
                            default:
                            {
                                range[0] = StringToInt(buffer);
                                if ((dots+1) < blen)
                                {
                                    StrErase(buffer,0,dots+1);
                                    range[1] = StringToInt(buffer);
                                }
                                else
                                    range[1] = MAXSPAWNPOINT-1;
                            }
                        }
                        if (range[0] > -1)
                        {
                            if (range[1] >= MAXSPAWNPOINT)
                                range[1] = MAXSPAWNPOINT-1;
                            for (new i = range[0];i <= range[1];i++)
                                rewards[i] = false;
                        }
                    }
                }
                case 'o': // Origin
                {
                    if ((args-nextArg) < 3)
                        err = true;
                    else
                    {
                        for (new i = 0;i < 3;i++)
                        {
                            GetCmdArg(++nextArg,buffer,17);
                            if (buffer[0] == '~')
                            {
                                if (strlen(buffer) > 1)
                                {
                                    StrErase(buffer,0,1);
                                    originC[i] += StringToFloat(buffer);
                                }
                            }
                            else
                                originC[i] = StringToFloat(buffer);
                        }
                    }
                }
                case 'O': // Set origin to anOther player
                {
                    if (lastArg)
                        err = true;
                    else
                    {
                        GetCmdArg(++nextArg,buffer,64);
                        decl String:target_name[MAX_NAME_LENGTH];
                        decl target_list[1];
                        decl target_count;
                        decl bool:tn_is_ml;
                        if ((target_count = ProcessTargetString(buffer,
                                                                client,
                                                                target_list,
                                                                1,
                                                                0,
                                                                target_name,
                                                                MAX_NAME_LENGTH,
                                                                tn_is_ml)) <= 0)
                        {
                            ReplyToTargetError(client, target_count);
                            return Plugin_Handled;
                        }
                        GetClientAbsOrigin(target_list[0],originC);
                    }
                }
                case 'D': // set origin to another rewarD
                {
                    if (lastArg)
                        err = true;
                    else
                    {
                        GetCmdArg(++nextArg,buffer,64);
                        new base = getRewardID(buffer,client);
                        if (base < 0)
                        {
                            RespondToCommand(client, "[SM] Error: Unknown reward '%s'",buffer);
                            return Plugin_Handled;
                        }
                        originC = defSpawnCoords[base];
                    }
                }
                case 'f': // Force, overwrite existing files
                {
                    force = true;
                }
                default:
                {
                    RespondToCommand(client,"[SM] Ignoring unknown switch: %s",buffer);
                }
            }
        }
        else
            break;
        if (err)
            break;
    }
    if ((err) || (nextArg > args))
    {
        RespondWriteUsage(client);
        return Plugin_Handled;
    }
    GetCmdArg(nextArg, buffer, 112);
    while ((buffer[0] == '/') || (buffer[0] == '\\'))
        StrErase(buffer,0);
    if (StrFind(buffer,"..") > -1)
    {
        RespondToCommand(client,"[SM] Error: Illegal path.");
        return Plugin_Handled;
    }
    if ((strcmp(buffer,"aliases.cfg") == 0) || (strcmp(buffer,"scripts.cfg") == 0))
    {
        RespondToCommand(client,"[SM] Error: Unable to overwrite system file.");
        return Plugin_Handled;
    }
    Format(buffer,64,"cfg/maprewards/%s",buffer);
    if (DirExists("cfg/maprewards") == false)
        CreateDirectory("cfg/maprewards",511);
    if (FileExists(buffer))
    {
        if (force)
        {
            RespondToCommand(client,"[SM] File exists . . . Overwriting . . .");
            DeleteFile(buffer);
        }
        else
        {
            CRespondToCommand(client,"[SM] File exists . . . Use {green}-f{default} to overwrite.");
            return Plugin_Handled;
        }
    }
    
    new Handle:oFile = OpenFile(buffer,"w");
    new lines = 0;
    for (new i = 0;i < MAXSPAWNPOINT;i++)
    {
        if ((rewards[i]) && (isValidReward(i)))
        {
            decl String:cmdC[1024];
            buildRewardCmd(i,cmdC,1024,relative,originC);
            WriteFileLine(oFile,cmdC);
            lines++;
        }
    }
    CloseHandle(oFile);
    if (FileExists(buffer))
        RespondToCommand(client,"[SM] Successfully wrote %d rewards to file '%s'.",lines,buffer);
    else
        RespondToCommand(client,"[SM] Some error has occurred. The file was not saved.");
    return Plugin_Handled;
}

RespondLoadUsage(client)
{
    CRespondToCommand(client,"[SM] Usage: {green}sm_mrw_cfg_load{default} [{green}OPTIONS{default} ...] <{green}file.cfg{default}>");
    CRespondToCommand(client,"[SM]    {green}file.cfg{default} is the name of a previously saved cfg file stored within {green}cfg/maprewards/{default}.");
    CRespondToCommand(client,"[SM]    {green}OPTIONS{default}:");
    CRespondToCommand(client,"[SM]       -E <{green}reward_id{default}>");
    CRespondToCommand(client,"[SM]          Exclude {green}reward_id{default} from being loaded.");
    CRespondToCommand(client,"[SM]          Allows a range: {green}#..#{default}, {green}..#{default}, or {green}#..");
    CRespondToCommand(client,"[SM]          {green}reward_id{default} can only be numbers that correspond to the reward in the order they appear in the CFG, starting with 0.");
    CRespondToCommand(client,"[SM]          Multiple {green}-E{default} switches are accepted.");
    CRespondToCommand(client,"[SM]       -o <{green}X Y Z{default}>");
    CRespondToCommand(client,"[SM]          Set the origin coordinates. Only used for rewards in the cfg that were saved with relative coordinates.");
    CRespondToCommand(client,"[SM]          The origin will default to your location (or 0,0,0 for the server) unless this option is present.");
    CRespondToCommand(client,"[SM]          Relative coordinates can be used to offset from your current coordinates.");
    CRespondToCommand(client,"[SM]       -O <{green}#userid|name{default}>");
    CRespondToCommand(client,"[SM]          Set the origin coordinates to a player's location.");
    CRespondToCommand(client,"[SM]          May be used in conjunction with {green}-o{default} to offset from a player as long as {green}-O{default} is provided first.");
    CRespondToCommand(client,"[SM]       -D <{green}#reward_id|name{default}>");
    CRespondToCommand(client,"[SM]          Set the origin coordinates to a reward's location.");
}

public Action:loadCFG(client, args)
{
    if (client > 0)
    {
        new flagBits = GetUserFlagBits(client);
        if (((flagBits & ADMFLAG_ROOT) == 0) && ((flagBits & g_basicFlag) != g_basicFlag))
        {
            ReplyToCommand(client,"[SM] You do not have access to this command.");
            return Plugin_Handled;
        }
    }
    if (args < 1)
    {
        RespondLoadUsage(client);
        return Plugin_Handled;
    }
    decl String:buffer[64];
    new Float:originC[3];
    if ((client > 0) && (IsClientInGame(client)))
        GetClientAbsOrigin(client,originC);
    new bool:err = false;
    new nextArg = 1;
    new bool:lastArg = false;
    new bool:rewards[MAXSPAWNPOINT] = { true, ... };
    for (;nextArg <= args;nextArg++)
    {
        if (nextArg == args)
            lastArg = true;
        GetCmdArg(nextArg,buffer,64);
        if (buffer[0] == '-')
        {
            if (buffer[1] == '-')
            {
                nextArg++;
                break;
            }
            switch (buffer[1])
            {
                case 'E': // Except ID
                {
                    if (lastArg)
                        err = true;
                    else
                    {
                        GetCmdArg(++nextArg,buffer,64);
                        new blen = strlen(buffer);
                        new dots = StrFind(buffer,"..",0);
                        new range[2] = { -1, -1 };
                        switch (dots)
                        {
                            case -1:
                            {
                                range[0] = range[1] = StringToInt(buffer);
                            }
                            case 0:
                            {
                                if (blen > 2)
                                {
                                    range[0] = 0;
                                    StrErase(buffer,0,2);
                                    range[1] = StringToInt(buffer);
                                }
                            }
                            default:
                            {
                                range[0] = StringToInt(buffer);
                                if ((dots+1) < blen)
                                {
                                    StrErase(buffer,0,dots+1);
                                    range[1] = StringToInt(buffer);
                                }
                                else
                                    range[1] = MAXSPAWNPOINT-1;
                            }
                        }
                        if (range[0] > -1)
                        {
                            if (range[1] >= MAXSPAWNPOINT)
                                range[1] = MAXSPAWNPOINT-1;
                            for (new i = range[0];i <= range[1];i++)
                                rewards[i] = false;
                        }
                    }
                }
                case 'o': // Origin
                {
                    if ((args-nextArg) < 3)
                        err = true;
                    else
                    {
                        for (new i = 0;i < 3;i++)
                        {
                            GetCmdArg(++nextArg,buffer,17);
                            if (buffer[0] == '~')
                            {
                                if (strlen(buffer) > 1)
                                {
                                    StrErase(buffer,0,1);
                                    originC[i] += StringToFloat(buffer);
                                }
                            }
                            else
                                originC[i] = StringToFloat(buffer);
                        }
                    }
                }
                case 'O': // set origin to anOther player
                {
                    if (lastArg)
                        err = true;
                    else
                    {
                        GetCmdArg(++nextArg,buffer,64);
                        decl String:target_name[MAX_NAME_LENGTH];
                        decl target_list[1];
                        decl target_count;
                        decl bool:tn_is_ml;
                        if ((target_count = ProcessTargetString(buffer,
                                                                client,
                                                                target_list,
                                                                1,
                                                                0,
                                                                target_name,
                                                                MAX_NAME_LENGTH,
                                                                tn_is_ml)) <= 0)
                        {
                            ReplyToTargetError(client, target_count);
                            return Plugin_Handled;
                        }
                        GetClientAbsOrigin(target_list[0],originC);
                    }
                }
                case 'D': // set origin to another rewarD
                {
                    if (lastArg)
                        err = true;
                    else
                    {
                        GetCmdArg(++nextArg,buffer,64);
                        new base = getRewardID(buffer,client);
                        if (base < 0)
                        {
                            RespondToCommand(client, "[SM] Error: Unknown reward '%s'",buffer);
                            return Plugin_Handled;
                        }
                        originC = defSpawnCoords[base];
                    }
                }
                default:
                {
                    RespondToCommand(client,"[SM] Ignoring unknown switch: %s",buffer);
                }
            }
        }
        else
            break;
        if (err)
            break;
    }
    if ((err) || (nextArg > args))
    {
        RespondLoadUsage(client);
        return Plugin_Handled;
    }
    GetCmdArg(nextArg, buffer, 48);
    while ((buffer[0] == '/') || (buffer[0] == '\\'))
        StrErase(buffer,0);
    if (StrFind(buffer,"..") > -1)
    {
        RespondToCommand(client,"[SM] Error: Illegal path.");
        return Plugin_Handled;
    }
    if ((strcmp(buffer,"aliases.cfg") == 0) || (strcmp(buffer,"scripts.cfg") == 0))
    {
        RespondToCommand(client,"[SM] Error: Unable to load system file.");
        return Plugin_Handled;
    }
    Format(buffer,64,"cfg/maprewards/%s",buffer);
    if (!FileExists(buffer))
    {
        CRespondToCommand(client,"[SM] Error: File {green}%s{default} does not exist.",buffer);
        return Plugin_Handled;
    }
    cleanUp(CLEAN_MAN_LOAD);
    new Handle:iFile = OpenFile(buffer,"r");
    decl String:fBuf[1024];
    new lines, skipped;
    decl String:rep[MAXINPUT];
    Format(rep,MAXINPUT,"sm_mrw_add -o %f %f %f ",originC[0],originC[1],originC[2]);
    while (ReadFileLine(iFile,fBuf,1024))
    {
        TrimString(fBuf);
        if (strlen(fBuf) == 0)
            continue;
        if (ReplaceStringEx(fBuf,1024,"sm_mrw_add ",rep) > 0)
        {
            if (rewards[lines++])
                ServerCommand(fBuf);
            else
                skipped++;
        }
        else if (StrFind(fBuf,"sm_mrw_modify -1") == 0)
        {
            if (rewards[lines])
                ServerCommand(fBuf);
        }
        else
            ServerCommand(fBuf);
    }
    CloseHandle(iFile);
    if (lines > 0)
        CRespondToCommand(client,"[SM] Successfully spawned {green}%d{default} rewards.",lines-skipped);
    else
        CRespondToCommand(client,"[SM] Warning: No rewards found in file {green}%s{default}. CFG was executed.",buffer);
    return Plugin_Handled;
}

public cvarEnableChange(Handle:convar, const String:oldValue[], const String:newValue[])
{
    g_enable = StringToInt(newValue);
    if ((StringToInt(oldValue)) && (!g_enable))
        killRewards();
    else if ((!StringToInt(oldValue)) && (g_enable))
        spawnRewards();
}

public cvarChange(Handle:convar, const String:oldValue[], const String:newValue[])
{
    g_respawnTime = StringToFloat(newValue);
}

stock orFlag(&flags, flag)
{
    if (64 < flag < 91)
        flag += 32;
    switch (flag)
    {
        case 'a':   flags |= ADMFLAG_RESERVATION;
		case 'b':   flags |= ADMFLAG_GENERIC;
		case 'c':   flags |= ADMFLAG_KICK;
		case 'd':   flags |= ADMFLAG_BAN;
		case 'e':   flags |= ADMFLAG_UNBAN;
		case 'f':   flags |= ADMFLAG_SLAY;
		case 'g':   flags |= ADMFLAG_CHANGEMAP;
		case 'h':   flags |= ADMFLAG_CONVARS;
		case 'i':   flags |= ADMFLAG_CONFIG;
		case 'j':   flags |= ADMFLAG_CHAT;
		case 'k':   flags |= ADMFLAG_VOTE;
		case 'l':   flags |= ADMFLAG_PASSWORD;
		case 'm':   flags |= ADMFLAG_RCON;
		case 'n':   flags |= ADMFLAG_CHEATS;
		case 'o':   flags |= ADMFLAG_CUSTOM1;
		case 'p':   flags |= ADMFLAG_CUSTOM2;
		case 'q':   flags |= ADMFLAG_CUSTOM3;
		case 'r':   flags |= ADMFLAG_CUSTOM4;
		case 's':   flags |= ADMFLAG_CUSTOM5;
		case 't':   flags |= ADMFLAG_CUSTOM6;
		case 'z':   flags |= ADMFLAG_ROOT;
    }
}

public cvarBasicFlagChange(Handle:convar, const String:oldValue[], const String:newValue[])
{
    g_basicFlag = 0;
    for (new i = 0, j = strlen(newValue);i < j;i++)
        orFlag(g_basicFlag,newValue[i]);
}

public cvarCreateFlagChange(Handle:convar, const String:oldValue[], const String:newValue[])
{
    g_createFlag = 0;
    for (new i = 0, j = strlen(newValue);i < j;i++)
        orFlag(g_createFlag,newValue[i]);
}

public cvarExtendedFlagChange(Handle:convar, const String:oldValue[], const String:newValue[])
{
    g_extendedFlag = 0;
    for (new i = 0, j = strlen(newValue);i < j;i++)
        orFlag(g_extendedFlag,newValue[i]);
}

public OnPluginEnd()
{
    // Clean up.
    
    cleanUp(CLEAN_PLUG_END,autoSave(SAVE_PLUG_END));
}

public OnMapStart()
{
    //PrecacheModel("models/props_halloween/halloween_gift.mdl");
    /*defSpawnCoords[0][0] = 1.5;
    defSpawnCoords[0][1] = -2144.0;
    defSpawnCoords[0][2] = -9856.0;
    defSpawnAngles[0][0] = defSpawnAngles[0][1] = defSpawnAngles[0][2] = 0.0;
    rCommand[0] = "sm_ahopmultiplier";
    rCommand2[0] = "1.1";
    model[0] = "models/props_halloween/halloween_gift.mdl";
    script[0] = "mass,0.1,inertia,1000.0";
    entType[0] = "prop_physics_override";*/
    
    // Get cvar values.
    
    g_enable = GetConVarInt(c_enable);
    g_respawnTime = GetConVarFloat(c_respawnTime);
    g_cleanUp = GetConVarInt(c_cleanUp);
    g_autoLoad = GetConVarInt(c_autoLoad);
    g_autoSave = GetConVarInt(c_autoSave);
    
    autoLoad(LOAD_MAP_START|LOAD_PLUG_START,cleanUp(CLEAN_MAP_START,autoSave(SAVE_MAP_START)));
    
    // Spawn rewards if enabled.
    
    //spawnRewards();
}

public OnRoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
    CreateTimer(5.0, timerRespawnReward, -1);
    autoLoad(LOAD_ROUND_START,cleanUp(CLEAN_ROUND_START,autoSave(SAVE_ROUND_START)));
}

killReward(index)
{
    new ent = spawnEnts[index];
    if (ent > -1)
    {
        spawnEnts[index] = -1;
        if (entTimers[index] != INVALID_HANDLE)
        {
            KillTimer(entTimers[index]);
            entTimers[index] = INVALID_HANDLE;
        }
        if (IsValidEntity(ent))
        {
            decl String:temp[32];
            GetEntPropString(ent, Prop_Data, "m_iName", temp, 32);
            if (strcmp(entName[index],temp) == 0)
                AcceptEntityInput(ent, "Kill");
            else
            {
                decl String:className[35];
                GetEdictClassname(ent,className,35);
                PrintToServer("[SM] Error: Reward #%d,%s (%d,%s) m_iName == %s, expected '%s'",index,entType[index],ent,className,temp,entName[index]);
                //AcceptEntityInput(ent, "Kill");
            }
        }
    }
}

killRewards()
{
    for (new i = 0; i < MAXSPAWNPOINT; i++)
    {
        killReward(i);
    }
}

public Action:killEntity(client, args)
{
    if (client > 0)
    {
        new flagBits = GetUserFlagBits(client);
        if (((flagBits & ADMFLAG_ROOT) == 0) && ((flagBits & g_basicFlag) != g_basicFlag))
        {
            ReplyToCommand(client,"[SM] You do not have access to this command.");
            return Plugin_Handled;
        }
    }
    if (args < 1)
    {
        RespondToCommand(client, "[SM] Usage: sm_mrw_kill <#entity_id>");
        return Plugin_Handled;
    }
    decl String:buffer[16];
    GetCmdArg(1,buffer,16);
    new entID = StringToInt(buffer);
    if (entID < 1)
    {
        RespondToCommand(client,"[SM] Error: Cannot kill entity '%d'.",entID);
        return Plugin_Handled;
    }
    for (new i = 0; i < MAXSPAWNPOINT; i++)
    {
        if (spawnEnts[i] == entID)
        {
            RespondToCommand(client,"[SM] Error: Entity is still loaded as ID #%d. Use sm_mrw_remove or sm_mrw_release the entity first.",i);
            return Plugin_Handled;
        }
    }
    if (IsValidEntity(entID))
        AcceptEntityInput(entID, "Kill");
    else
        RespondToCommand(client,"[SM] Error: Invalid entity.");
    return Plugin_Handled;
}

resetReward(index)
{
    spawnEnts[index] = -1;
    defSpawnCoords[index][0] = defSpawnCoords[index][1] = defSpawnCoords[index][2] = 0.0;
    defSpawnAngles[index][0] = defSpawnAngles[index][1] = defSpawnAngles[index][2] = 0.0;
    rCommand[index][0] = "";
    rCommand[index][1] = "";
    model[index] = "";
    script[index][0] = "";
    script[index][1] = "";
    entType[index] = "";
    respawnMethod[index] = HOOK_NOHOOK;
    respawnTime[index] = -1.0;
    entName[index] = "";
    entSpin[index][0] = entSpin[index][1] = entSpin[index][2] = entSpinInt[index] = 0.0;
    if (entTimers[index] != INVALID_HANDLE)
    {
        KillTimer(entTimers[index]);
        entTimers[index] = INVALID_HANDLE;
    }
    rewardKiller[index] = 0;
    entHealth[index] = 0.0;
    entDamage[index] = 0.0;
}

resetRewards()
{
    for (new i = 0;i < MAXSPAWNPOINT;i++)
        resetReward(i);
}

removeReward(index)
{
    killReward(index);
    resetReward(index);
}

removeRewards()
{
    for (new i = 0;i < MAXSPAWNPOINT;i++)
        removeReward(i);
}

stock bool:cleanUp(event, bool:didSave = false)
{
    if (g_cleanUp & event)
    {
        if (!didSave)
            autoSave(SAVE_CLEANUP);
        removeRewards();
        return true;
    }
    if (event & CLEAN_KILL)
        killRewards();
    if (event & CLEAN_RESET)
    {
        if (!didSave)
            autoSave(SAVE_CLEANUP);
        resetRewards();
        return true;
    }
    return false;
}

autoLoad(event, bool:didCleanUp)
{
    if (g_autoLoad & event)
    {
        if (!didCleanUp)
            cleanUp(CLEAN_AUTO_LOAD);
        if (event & LOAD_PLUG_START)
        {
            if (FileExists("cfg/maprewards/server.cfg"))
                ServerCommand("exec maprewards/server");
        }
        if (event & (LOAD_MAP_START|LOAD_ROUND_START))
        {
            new String:mapName[32];
            new String:mapFile[47] = "maprewards/";
            new String:mapCheck[51] = "cfg/";
            GetCurrentMap(mapName,32);
            StrCat(mapFile,46,mapName);
            StrCat(mapCheck,51,mapFile);
            StrCat(mapCheck,51,".cfg");
            if (FileExists(mapCheck))
            {
                ServerCommand("exec %s",mapFile);
            }
        }
    }
}

getActiveCount()
{
    new r = 0;
    for (new i = 0;i < MAXSPAWNPOINT;i++)
        if (strlen(entType[i]) > 0)
            r++;
    return r;
}

stock bool:autoSave(event, bool:force = false)
{
    if (g_autoSave & event)
    { // we keep these two statements separate so we can return true if we were supposed to save, regardless if we actually did.
        if ((force) || (getActiveCount() > 0))
        {
            decl String:mapFile[51];
            decl String:backupFile[91];
            GetCurrentMap(mapFile,32);
            if (strlen(mapFile) > 0)
            {
                Format(backupFile,91,"cfg/maprewards/backup/%s.cfg.%d",mapFile,GetTime());
                Format(mapFile,51,"cfg/maprewards/%s.cfg",mapFile);
                if ((g_autoSave & SAVE_BACKUP) && (FileExists(mapFile)))
                {
                    if (DirExists("cfg/maprewards/backup") == false)
                        CreateDirectory("cfg/maprewards/backup",511);
                    RenameFile(backupFile,mapFile);
                    PrintToServer("[SM] Backed up old maprewards cfg file to '%s'.",backupFile);
                }
                new Handle:oFile = OpenFile(mapFile,"w");
                for (new i = 0;i < MAXSPAWNPOINT;i++)
                {
                    if (strlen(entType[i]) != 0)
                    {
                        decl String:cmdC[1024];
                        buildRewardCmd(i,cmdC,1024);
                        WriteFileLine(oFile,cmdC);
                    }
                }
                CloseHandle(oFile);
                PrintToServer("[SM] Saved maprewards cfg file to '%s'.",mapFile);
            }
        }
        return true;
    }
    return false;
}

spawnRewards()
{
    if (g_enable)
    {
        for (new i = 0; i < MAXSPAWNPOINT; i++)
        {
            spawnReward(i);
        }
    }
}

newEnt()
{
    new i;
    for (i = 0;i < MAXSPAWNPOINT;i++)
    {
        // Find the first unused index entry.
        if (!strlen(entType[i]))
            break;
    }
    return i;
}

stock RespondUsage(client)
{
    CRespondToCommand(client, "[SM] Usage: {green}sm_mrw_add{default} [{green}OPTIONS{default} ...] [{green}command{default} ...]");
    CRespondToCommand(client, "[SM]    At least {green}model{default} or {green}entity_type{default} is required.");
    CRespondToCommand(client, "[SM]       If {green}entity_type{default} is {green}prop_physics_override{default}, both are required.");
    CRespondToCommand(client, "[SM]    {green}command{default} is a full command to run when a player touches the reward.");
    CRespondToCommand(client, "[SM]       If present, {green}#player{default} will be replaced with the target string of the client who activated the reward.");
    CRespondToCommand(client, "[SM]    {green}OPTIONS{default}:");
    CRespondToCommand(client, "[SM]       -h   Display this help text.");
    CRespondToCommand(client, "[SM]       -A <{green}health{default}>");
    CRespondToCommand(client, "[SM]          Set an internal health amount for the reward.");
    CRespondToCommand(client, "[SM]          Only used when {green}respawn_method{default} is {green}kill{deafult} to kill the reward after it takes this much damage.");
    CRespondToCommand(client, "[SM]       -b <{green}#reward_id|name>");
    CRespondToCommand(client, "[SM]          Uses the provided reward as a base to copy data from.");
    CRespondToCommand(client, "[SM]          This switch should appear before anything else as it overwrites all the data.");
    CRespondToCommand(client, "[SM]          The origin coordinates will be set to this reward unless the origin is set.");
    CRespondToCommand(client, "[SM]       -c <{green}X Y Z{default}>");
    CRespondToCommand(client, "[SM]          Coordinates to spawn the entity at, can be relative to {green}origin{default} using {green}~{default}'s.");
    CRespondToCommand(client, "[SM]          If not provided, {green}origin{default} will be used.");
    CRespondToCommand(client, "[SM]       -d <{green}respawn_method{default}>");
    CRespondToCommand(client, "[SM]          Must be one of the following:");
    CRespondToCommand(client, "[SM]          {green}pickup{default}: When a player touches it, it will disappear until the respawn time is up.");
    CRespondToCommand(client, "[SM]          {green}static{default}: The reward will stay, but will be inactive until the respawn time is up.");
    CRespondToCommand(client, "[SM]          {green}constant{default}: The reward will stay and never deactivate.");
    CRespondToCommand(client, "[SM]          {green}hurt{default}: The reward will trigger when a player hurts it.");
    CRespondToCommand(client, "[SM]          {green}kill{default}: The reward will trigger when a player kills it.");
    CRespondToCommand(client, "[SM]          {green}notouch{default}: The reward will not trigger when a player touches it. Can be used after other settings to remove the {green}touch{default} event.");
    CRespondToCommand(client, "[SM]          {green}nohook{default} or {green}nopickup{default}: Default. Just an entity, nothing special about it.");
    CRespondToCommand(client, "[SM]       -e <{green}entity_type{default}>");
    CRespondToCommand(client, "[SM]          The type of entity you wish to create. If not provided, {green}prop_physics_override{default} is used.");
    CRespondToCommand(client, "[SM]          You may use model aliases defined with {green}sm_mrw_model_add{default}.");
    CRespondToCommand(client, "[SM]       -m <{green}model{default}>");
    CRespondToCommand(client, "[SM]          The path to the model file you wish to use.");
    CRespondToCommand(client, "[SM]          You may use model aliases defined with {green}sm_mrw_model_add{default}.");
    CRespondToCommand(client, "[SM]       -n <{green}name{default}>");
    CRespondToCommand(client, "[SM]          Allows you to define a name for the entity, which can be later used when referring to this reward.");
    CRespondToCommand(client, "[SM]          If not defined, the name will default to its corresponding ID number.");
    CRespondToCommand(client, "[SM]       -o <{green}X Y Z{default}>");
    CRespondToCommand(client, "[SM]          Origin coordinates. If not provided client's location will be used.");
    CRespondToCommand(client, "[SM]       -O <{green}#userid|name{default}>");
    CRespondToCommand(client, "[SM]          Set the origin coordinates to a player's location.");
    CRespondToCommand(client, "[SM]       -D <{green}#reward_id|name{default}>");
    CRespondToCommand(client, "[SM]          Set the origin coordinates to a reward's location.");
    CRespondToCommand(client, "[SM]       -p <{green}entity_property_script{default}>");
    CRespondToCommand(client, "[SM]          Allows you to define a series of entity properties using this format:");
    CRespondToCommand(client, "[SM]             [{green}prop_type{default}:]{green}key{default},[{green}type{default}=]{green}value{default}");
    CRespondToCommand(client, "[SM]             {green}prop_type{default} must be {green}0{default} for {green}Prop_Data{default} (default) or {green}1{default} for {green}Prop_Send{default}.");
    CRespondToCommand(client, "[SM]             {green}type{default} may be one of the following: {green}int float string ent{default} or {green}vec{default}.");
    CRespondToCommand(client, "[SM]                For {green}vec{default}, {green}value{default} must be a series of 3 floats seperated by commas.");
    CRespondToCommand(client, "[SM]             Multiple key,value pairs can be seperated by {green}&{default}'s.");
    CRespondToCommand(client, "[SM]             Please do not set {green}m_iName{default} here. Use the {green}-n{default} switch to set a name.");
    CRespondToCommand(client, "[SM]          You may use script aliases defined with {green}sm_mrw_script_add{default}.");
    CRespondToCommand(client, "[SM]       -r <{green}RX RY RZ{default}>");
    CRespondToCommand(client, "[SM]          Rotations for the entity. Cannot be relative.");
    CRespondToCommand(client, "[SM]       -s <{green}script{default}>");
    CRespondToCommand(client, "[SM]          A series of variables dispatched to the entity as an {green}overridescript{default} or individual keys to trigger.");
    CRespondToCommand(client, "[SM]          A value of {green}null{default} will erase the script defined by a provided model alias.");
    CRespondToCommand(client, "[SM]          Format:");
    CRespondToCommand(client, "[SM]             {green}overridescript{default}?{green}key{default}[,[{green}type{default}=]{green}value{default}]");
    CRespondToCommand(client, "[SM]             {green}type{default} may be one of the following: {green}int float{default} or {green}string{default}.");
    CRespondToCommand(client, "[SM]             Multiple key[,value]'s can be seperated on the right side of the {green}?{default} by {green}&{default}'s.");
    CRespondToCommand(client, "[SM]          You may use script aliases defined with {green}sm_mrw_script_add{default}.");
    CRespondToCommand(client, "[SM]       -t <{green}respawn_time{default}>");
    CRespondToCommand(client, "[SM]             The fractional seconds until the reward respawns.");
    CRespondToCommand(client, "[SM]             A value of {green}0{default} will never respawn.");
    CRespondToCommand(client, "[SM]             A value of {green}-1{default} will use the value of {green}sm_mrw_respawn_time{default}.");
    CRespondToCommand(client, "[SM]       -T <{green}SX SY SZ interval{default}>");
    CRespondToCommand(client, "[SM]          Set the reward to rotate every {green}interval{default}.");
    CRespondToCommand(client, "[SM]          {green}interval{default} is in fractional seconds.");
    CRespondToCommand(client, "[SM]       -X   Sets the command for when the reward is {green}kill{default}ed to {green}command{default}.");
    CRespondToCommand(client, "[SM]               To set both {green}pickup{default} and {green}kill{default} commands requires an extra call to {green}sm_mrw_modify{default}.");
    CRespondToCommand(client, "[SM]               If {green}respawn_method{default} is set to {green}kill{default} and {green}-X{default} is not present, {green}command{default} will be used for both {green}pickup{default} and {green}kill{default}.");
    CRespondToCommand(client, "[SM]       -P   Sets {green}respawn_method{default} to {green}pickup{default}.");
    CRespondToCommand(client, "[SM]       -S   Sets {green}respawn_method{default} to {green}static{default}.");
    CRespondToCommand(client, "[SM]       -C   Sets {green}respawn_method{default} to {green}constant{default}.");
    CRespondToCommand(client, "[SM]       -H   Adds {green}hurt{default} to the current {green}respawn_method{default}.");
    CRespondToCommand(client, "[SM]       -K   Adds {green}kill{default} to the current {green}respawn_method{default}.");
    CRespondToCommand(client, "[SM]       -N   Removes {green}touch{default} events from the current {green}respawn_method{default}.");
    CRespondToCommand(client, "[SM]       -R   Automatically release the reward from the plugin imediately after spawning it.");
}

public Action:addSpawnPoint(client, args)
{
    if (client > 0)
    {
        new flagBits = GetUserFlagBits(client);
        if (((flagBits & ADMFLAG_ROOT) == 0) && ((flagBits & g_createFlag) != g_createFlag))
        {
            ReplyToCommand(client,"[SM] You do not have access to this command.");
            return Plugin_Handled;
        }
    }
    if (args < 2)
    {
        RespondUsage(client);
        return Plugin_Handled;
    }
    new spawnPoints = newEnt();
    if (spawnPoints >= MAXSPAWNPOINT)
    {
        CRespondToCommand(client, "[SM] No more room for rewards! :( Use {green}sm_mrw_removeall{default} to reset.");
        return Plugin_Handled;
    }
    
    entType[spawnPoints] = "prop_physics_override";
    //model[spawnPoints] = "";
    //rCommand[spawnPoints][0] = "null";
    IntToString(spawnPoints,entName[spawnPoints],32);
    
    decl String:buffer[128];
    new nextArg = 1;
    new bool:lastArg = false;
    new bool:err = false;
    new bool:release = false;
    new whichCommand = 0;
    
    if ((client > 0) && (IsClientInGame(client)))
        GetClientAbsOrigin(client,defSpawnCoords[spawnPoints]);
    new String:strCoords[3][16];
    //for (new i = 0;i < 3;i++)
    //    FloatToString(originCoords[i],strCoords[i],16);
    
    for (;nextArg <= args;nextArg++)
    {
        if (nextArg == args)
            lastArg = true;
        GetCmdArg(nextArg,buffer,64);
        if (buffer[0] == '-')
        {
            if (buffer[1] == '-')
            {
                nextArg++;
                break;
            }
            switch (buffer[1])
            {
                case 'P': // Shortcut for -d pickup
                {
                    respawnMethod[spawnPoints] &= ~HOOK_STATIC;
                    respawnMethod[spawnPoints] &= ~HOOK_CONSTANT;
                    respawnMethod[spawnPoints] |= HOOK_TOUCH;
                }
                case 'S': // Shortcut for -d static
                {
                    respawnMethod[spawnPoints] &= ~HOOK_CONSTANT;
                    respawnMethod[spawnPoints] |= HOOK_STATIC|HOOK_TOUCH;
                }
                case 'C': // Shortcut for -d constant
                {
                    respawnMethod[spawnPoints] &= ~HOOK_STATIC;
                    respawnMethod[spawnPoints] |= HOOK_CONSTANT|HOOK_TOUCH;
                }
                case 'H': // Shortcut for -d hurt
                {
                    respawnMethod[spawnPoints] |= HOOK_HURT;
                }
                case 'K': // Shortcut for -d kill
                {
                    respawnMethod[spawnPoints] |= HOOK_HURT|HOOK_KILL;
                }
                case 'N': // Shortcut for -d notouch
                {
                    respawnMethod[spawnPoints] &= ~HOOK_TOUCH;
                }
                case 'A': // heAlth
                {
                    if (lastArg)
                        err = true;
                    else
                    {
                        GetCmdArg(++nextArg,buffer,64);
                        if (!StrIsDigit(buffer))
                            err = true;
                        else
                            entHealth[spawnPoints] = StringToFloat(buffer);
                    }
                }
                case 'b': // Base
                {
                    if (lastArg)
                        err = true;
                    else
                    {
                        GetCmdArg(++nextArg,buffer,64);
                        new base = getRewardID(buffer);
                        if (!isValidReward(base))
                        {
                            resetReward(spawnPoints);
                            RespondToCommand(client, "[SM] Error: Unknown reward '%s'",buffer);
                            return Plugin_Handled;
                        }
                        defSpawnCoords[spawnPoints] = defSpawnCoords[base];
                        defSpawnAngles[spawnPoints] = defSpawnAngles[base];
                        respawnMethod[spawnPoints] = respawnMethod[base];
                        model[spawnPoints] = model[base];
                        entType[spawnPoints] = entType[base];
                        rCommand[spawnPoints][0] = rCommand[base][0];
                        rCommand[spawnPoints][1] = rCommand[base][1];
                        script[spawnPoints][0] = script[base][0];
                        script[spawnPoints][1] = script[base][1]
                        respawnTime[spawnPoints] = respawnTime[base];
                    }
                }
                case 'c': // Coords
                {
                    if (lastArg)
                        err = true;
                    else
                    {
                        GetCmdArg(nextArg+1,buffer,64);
                        if (strcmp(buffer,"@aim") == 0)
                        {
                            nextArg++;
                            if ((client > 0) && (IsClientInGame(client)))
                                SetTeleportEndPoint(client,defSpawnCoords[spawnPoints]);
                        }
                        else if ((args-nextArg) < 3)
                            err = true;
                        else
                        {
                            for (new i = 0;i < 3;i++)
                                GetCmdArg(++nextArg,strCoords[i],16);
                        }
                    }
                }
                case 'd': // respawn methoD
                {
                    if (lastArg)
                        err = true;
                    else
                    {
                        GetCmdArg(++nextArg,buffer,64);
                        if (strcmp(buffer,"pickup") == 0)
                            respawnMethod[spawnPoints] = HOOK_TOUCH;
                        else if (strcmp(buffer,"static") == 0)
                            respawnMethod[spawnPoints] = HOOK_STATIC|HOOK_TOUCH;
                        else if ((strcmp(buffer,"nohook") == 0) || (strcmp(buffer,"nopickup") == 0))
                            respawnMethod[spawnPoints] = HOOK_NOHOOK;
                        else if (strcmp(buffer,"constant") == 0)
                            respawnMethod[spawnPoints] = HOOK_CONSTANT|HOOK_TOUCH;
                        else if (strcmp(buffer,"hurt") == 0)
                            respawnMethod[spawnPoints] |= HOOK_HURT;
                        else if (strcmp(buffer,"kill") == 0)
                            respawnMethod[spawnPoints] = HOOK_HURT|HOOK_KILL;
                        else if (strcmp(buffer,"notouch") == 0)
                            respawnMethod[spawnPoints] &= ~HOOK_TOUCH;
                        else
                            respawnMethod[spawnPoints] = StringToInt(buffer);
                    }
                }
                case 'e': // Entity type
                {
                    if (lastArg)
                        err = true;
                    else
                    {
                        GetCmdArg(++nextArg,buffer,64);
                        for (new i = 0;i < aliasCount;i++)
                        {
                            if (strcmp(buffer,aliases[i][0]) == 0)
                            {
                                strcopy(buffer,64,aliases[i][2]);
                                if ((strlen(aliases[i][1]) > 0) && (strcmp(model[spawnPoints],"null") != 0) && (strcmp(model[spawnPoints],"0") != 0))
                                    strcopy(model[spawnPoints],64,aliases[i][1]);
                                if ((strlen(aliases[i][3]) > 0) && (strcmp(script[spawnPoints][0],"null") != 0) && (strcmp(script[spawnPoints][0],"0") != 0))
                                    strcopy(script[spawnPoints][0],64,aliases[i][3]);
                                if ((strlen(aliases[i][4]) > 0) && (strcmp(script[spawnPoints][1],"null") != 0) && (strcmp(script[spawnPoints][1],"0") != 0))
                                    strcopy(script[spawnPoints][1],64,aliases[i][4]);
                                break;
                            }
                        }
                        strcopy(entType[spawnPoints],32,buffer);
                    }
                }
                case 'h': // Help
                {
                    resetReward(spawnPoints);
                    RespondUsage(client);
                    return Plugin_Handled;
                }
                case 'm': // Model
                {
                    if (lastArg)
                        err = true;
                    else
                    {
                        GetCmdArg(++nextArg,buffer,64);
                        for (new i = 0;i < aliasCount;i++)
                        {
                            if (strcmp(buffer,aliases[i][0]) == 0)
                            {
                                strcopy(buffer,64,aliases[i][1]);
                                if ((strlen(aliases[i][2]) > 0) && (strcmp(entType[spawnPoints],"null") != 0) && (strcmp(entType[spawnPoints],"0") != 0))
                                    strcopy(entType[spawnPoints],64,aliases[i][2]);
                                if ((strlen(aliases[i][2]) > 0) && (strcmp(script[spawnPoints][0],"null") != 0))
                                    strcopy(script[spawnPoints][0],64,aliases[i][2]);
                                if ((strlen(aliases[i][4]) > 0) && (strcmp(script[spawnPoints][1],"null") != 0) && (strcmp(script[spawnPoints][1],"0") != 0))
                                    strcopy(script[spawnPoints][1],64,aliases[i][4]);
                                break;
                            }
                        }
                        strcopy(model[spawnPoints],64,buffer);
                    }
                }
                case 'n': // Name
                {
                    if (lastArg)
                        err = true;
                    else
                    {
                        GetCmdArg(++nextArg,entName[spawnPoints],32);
                        new dupe = getRewardID(entName[spawnPoints]);
                        if ((dupe > -1) && (dupe != spawnPoints))
                        {
                            RespondToCommand(client, "[SM] Error: Reward #%d already exists with the same name!",dupe);
                            resetReward(spawnPoints);
                            return Plugin_Handled;
                        }
                    }
                }
                case 'o': // Origin coords
                {
                    if (lastArg)
                        err = true;
                    else
                    {
                        GetCmdArg(nextArg+1,buffer,64);
                        if (strcmp(buffer,"@aim") == 0)
                        {
                            nextArg++;
                            if ((client > 0) && (IsClientInGame(client)))
                                SetTeleportEndPoint(client,defSpawnCoords[spawnPoints]);
                        }
                        else if ((args-nextArg) < 3)
                            err = true;
                        else
                        {
                            for (new i = 0;i < 3;i++)
                            {
                                GetCmdArg(++nextArg,buffer,17);
                                if (buffer[0] == '~')
                                {
                                    if (strlen(buffer) > 1)
                                    {
                                        StrErase(buffer,0,1);
                                        defSpawnCoords[spawnPoints][i] += StringToFloat(buffer);
                                    }
                                }
                                else
                                    defSpawnCoords[spawnPoints][i] = StringToFloat(buffer);
                            }
                        }
                    }
                }
                case 'O': // set origin to anOther player
                {
                    if (lastArg)
                        err = true;
                    else
                    {
                        GetCmdArg(++nextArg,buffer,64);
                        decl String:target_name[MAX_NAME_LENGTH];
                        decl target_list[1];
                        decl target_count;
                        decl bool:tn_is_ml;
                        if ((target_count = ProcessTargetString(buffer,
                                                                client,
                                                                target_list,
                                                                1,
                                                                0,
                                                                target_name,
                                                                MAX_NAME_LENGTH,
                                                                tn_is_ml)) <= 0)
                        {
                            resetReward(spawnPoints);
                            ReplyToTargetError(client, target_count);
                            return Plugin_Handled;
                        }
                        GetClientAbsOrigin(target_list[0],defSpawnCoords[spawnPoints]);
                    }
                }
                case 'D': // set origin to another rewarD
                {
                    if (lastArg)
                        err = true;
                    else
                    {
                        GetCmdArg(++nextArg,buffer,64);
                        new base = getRewardID(buffer);
                        if (!isValidReward(base))
                        {
                            resetReward(spawnPoints);
                            RespondToCommand(client, "[SM] Error: Unknown reward '%s'",buffer);
                            return Plugin_Handled;
                        }
                        defSpawnCoords[spawnPoints] = defSpawnCoords[base];
                    }
                }
                case 'p': // entProp values
                {
                    if (lastArg)
                        err = true;
                    else
                    {
                        GetCmdArg(++nextArg,buffer,64);
                        for (new i = 0;i < scriptCount;i++)
                        {
                            if (strcmp(buffer,scripts[i][0]) == 0)
                            {
                                strcopy(buffer,64,scripts[i][1]);
                                break;
                            }
                        }
                        strcopy(script[spawnPoints][1],64,buffer);
                    }
                }
                case 'r': // Rotation angles
                {
                    if ((args-nextArg) < 3)
                        err = true;
                    else
                    {
                        for (new i = 0;i < 3;i++)
                        {
                            GetCmdArg(++nextArg,buffer,64);
                            defSpawnAngles[spawnPoints][i] = StringToFloat(buffer);
                        }
                    }
                }
                case 's': // Script
                {
                    if (lastArg)
                        err = true;
                    else
                    {
                        GetCmdArg(++nextArg,buffer,64);
                        for (new i = 0;i < scriptCount;i++)
                        {
                            if (strcmp(buffer,scripts[i][0]) == 0)
                            {
                                strcopy(buffer,64,scripts[i][1]);
                                break;
                            }
                        }
                        strcopy(script[spawnPoints][0],64,buffer);
                    }
                }
                case 't': // respawn Time
                {
                    if (lastArg)
                        err = true;
                    else
                    {
                        GetCmdArg(++nextArg,buffer,64);
                        respawnTime[spawnPoints] = StringToFloat(buffer);
                    }
                }
                case 'R': // Release after spawning
                {
                    release = true;
                }
                case 'T': // make the reward Turn every interval (Spin)
                {
                    if ((args-nextArg) < 4)
                        err = true;
                    else
                    {
                        for (new i = 0;i < 3;i++)
                        {
                            GetCmdArg(++nextArg,buffer,64);
                            entSpin[spawnPoints][i] = StringToFloat(buffer);
                        }
                        GetCmdArg(++nextArg,buffer,64);
                        entSpinInt[spawnPoints] = StringToFloat(buffer);
                    }
                }
                case 'X': // make command set the kill command
                {
                    whichCommand = 1;
                }
                default:
                {
                    CRespondToCommand(client,"[SM] Ignoring unknown switch: {green}%s",buffer);
                }
            }
        }
        else
            break;
        if (err)
            break;
    }
    if ((strcmp(model[spawnPoints],"null") == 0) || (strcmp(model[spawnPoints],"0") == 0))
        model[spawnPoints] = "";
    if ((strcmp(entType[spawnPoints],"null") == 0) || (strcmp(entType[spawnPoints],"0") == 0))
        entType[spawnPoints] = "prop_physics_override";
    if ((err) || ((strcmp(entType[spawnPoints],"prop_physics_override") == 0) && (strlen(model[spawnPoints]) < 1)))
    {
        resetReward(spawnPoints);
        //RespondUsage(client);
        CRespondToCommand(client, "[SM] Usage: {green}sm_mrw_add{default} [{green}OPTIONS{default} ...] [{green}command{default} ...]");
        CRespondToCommand(client, "[SM]   Use {green}sm_mrw_add -h{default} to see the full help. Note: It's long, may want to run it from console.");
        return Plugin_Handled;
    }
    if (strlen(strCoords[0]) > 0)
    {
        for (new i = 0;i < 3;i++)
        {
            if (strCoords[i][0] == '~')
            {
                if (strlen(strCoords[i]) > 1)
                {
                    StrErase(strCoords[i],0,1);
                    defSpawnCoords[spawnPoints][i] += StringToFloat(strCoords[i]);
                }
            }
            else
                defSpawnCoords[spawnPoints][i] = StringToFloat(strCoords[i]);
        }
    }
    if ((strcmp(script[spawnPoints][0],"null") == 0) || (strcmp(script[spawnPoints][0],"0") == 0))
        script[spawnPoints][0] = "";
    if ((strcmp(script[spawnPoints][1],"null") == 0) || (strcmp(script[spawnPoints][1],"0") == 0))
        script[spawnPoints][1] = "";
    if (nextArg <= args)
    {
        GetCmdArg(nextArg++,rCommand[spawnPoints][whichCommand],128);
        for (;nextArg <= args;nextArg++)
        {
            GetCmdArg(nextArg,buffer,128);
            Format(rCommand[spawnPoints][whichCommand],128,"%s %s",rCommand[spawnPoints][whichCommand],buffer);
        }
    }
    if (g_enable)
    {
        spawnReward(spawnPoints);
        if (release)
        {
            CRespondToCommand(client, "[SM] Added reward and released entity #{green}%d",spawnEnts[spawnPoints]);
            resetReward(spawnPoints);
        }
        else
            CRespondToCommand(client, "[SM] Added reward spawn point #{green}%d",spawnPoints);
    }
    else
        CRespondToCommand(client, "[SM] Added reward spawn point #{green}%d",spawnPoints);
    newestReward = spawnPoints;
    if (client != 0)
        autoSave(SAVE_EDIT,true);
    return Plugin_Handled;
}

// Legacy command support. This command should never be used except when loading old saved configs.
public Action:addSpawnPointCustom(client, args)
{
    if (client > 0)
    {
        new flagBits = GetUserFlagBits(client);
        if (((flagBits & ADMFLAG_ROOT) == 0) && ((flagBits & g_createFlag) != g_createFlag))
        {
            ReplyToCommand(client,"[SM] You do not have access to this command.");
            return Plugin_Handled;
        }
    }
    if (args < 8)
    {
        CRespondToCommand(client, "[SM] Usage: sm_mrw_add_custom <{green}entity_type{default}> <{green}X Y Z{default}> <{green}RX RY RZ{default}> <{green}model{default}> [{green}command{default}] [{green}script{default}] [{green}respawn_time{default}] [{green}respawn_method{default}] [{green}command2 ...{default}]");
        CRespondToCommand(client, "[SM]    {green}entity_type{default} is the type of entity you wish to create.");
        CRespondToCommand(client, "[SM]        This is prop_physics_override by default.");
        CRespondToCommand(client, "[SM]        A value of {green}null{default}, {green}0{default}, or {green}foo{default} will use the default.");
        CRespondToCommand(client, "[SM]    {green}X Y Z{default} are the coordinates for the entity.");
        CRespondToCommand(client, "[SM]    {green}RX RY RZ{default} are the rotations for the entity.");
        CRespondToCommand(client, "[SM]    {green}model{default} is the path to the model file you wish to use.");
        CRespondToCommand(client, "[SM]        You may use model aliases defined with {green}sm_mrw_model_add{default}.");
        CRespondToCommand(client, "[SM]    {green}command{default} is a command to run when a player touches the reward.");
        CRespondToCommand(client, "[SM]        For no command, use either {green}null{default}, {green}0{default}, or {green}foo{default}.");
        CRespondToCommand(client, "[SM]    {green}command2{default} is the parameter(s) following the player argument.");
        CRespondToCommand(client, "[SM]        Use quotes for multiple args.");
        CRespondToCommand(client, "[SM]        Example: {green}command{default} #player {green}command2{default}");
        CRespondToCommand(client, "[SM]    {green}script{default} is a series of variables dispatched to the entity as an {green}overridescript{default}.");
        CRespondToCommand(client, "[SM]        You may use script aliases defined with {green}sm_mrw_script_add{default}.");
        CRespondToCommand(client, "[SM]        A value of {green}0{default} means no script.");
        CRespondToCommand(client, "[SM]        A value of {green}null{default} is similar to {green}0{default}, except if a model alias is used that defined a script, that script is ignored.");
        CRespondToCommand(client, "[SM]    {green}respawn_time{default} is the fractional seconds until the reward respawns.");
        CRespondToCommand(client, "[SM]        A value of {green}0{default} will never respawn.");
        CRespondToCommand(client, "[SM]        A value of {green}-1{default} will use the value of {green}sm_mrw_respawn_time{default}.");
        CRespondToCommand(client, "[SM]    {green}respawn_method{default} must be one of the following:");
        CRespondToCommand(client, "[SM]        {green}pickup{default}: This is the default behavior, when a player touches it, it will disappear until the respawn time is up.");
        CRespondToCommand(client, "[SM]        {green}static{default}: The reward will stay, but will be inactive until the respawn time is up.");
        return Plugin_Handled;
    }
    new spawnPoints = newEnt();
    if (spawnPoints >= MAXSPAWNPOINT)
    {
        CRespondToCommand(client, "[SM] No more room for rewards! :( Use {green}sm_mrw_removeall{default} to reset.");
        return Plugin_Handled;
    }
    //if (IsClientInGame(client))
    //    GetClientAbsOrigin(client,defOriginCoords[spawnPoints]);
    IntToString(spawnPoints,entName[spawnPoints],32);
    decl String:buffer[64];
    GetCmdArg(1, buffer, sizeof(buffer));
    if ((strcmp(buffer,"null") == 0) || (strcmp(buffer,"0") == 0) || (strcmp(buffer,"foo") == 0))
        buffer = "prop_physics_override";
    strcopy(entType[spawnPoints],32,buffer);
    GetCmdArg(2, buffer, sizeof(buffer));
    defSpawnCoords[spawnPoints][0] = StringToFloat(buffer);
    GetCmdArg(3, buffer, sizeof(buffer));
    defSpawnCoords[spawnPoints][1] = StringToFloat(buffer);
    GetCmdArg(4, buffer, sizeof(buffer));
    defSpawnCoords[spawnPoints][2] = StringToFloat(buffer);
    GetCmdArg(5, buffer, sizeof(buffer));
    defSpawnAngles[spawnPoints][0] = StringToFloat(buffer);
    GetCmdArg(6, buffer, sizeof(buffer));
    defSpawnAngles[spawnPoints][1] = StringToFloat(buffer);
    GetCmdArg(7, buffer, sizeof(buffer));
    defSpawnAngles[spawnPoints][2] = StringToFloat(buffer);
    GetCmdArg(8, buffer, sizeof(buffer));
    for (new i = 0;i < aliasCount;i++)
    {
        if (strcmp(buffer,aliases[i][0]) == 0)
        {
            strcopy(buffer,64,aliases[i][1]);
            if (strcmp(aliases[i][2],"") != 0)
                strcopy(script[spawnPoints][0],64,aliases[i][2]);
            break;
        }
    }
    model[spawnPoints] = buffer;
    respawnTime[spawnPoints] = -1.0;
    if (args > 8)
    {
        GetCmdArg(9, buffer, sizeof(buffer));
        rCommand[spawnPoints][0] = buffer;
        StrCat(rCommand[spawnPoints][0],128," #player ");
        if (args > 9)
        {
            GetCmdArg(10, buffer, sizeof(buffer));
            if (strcmp(buffer,"null") == 0)
                script[spawnPoints][0] = "";
            else if (strcmp(buffer,"0") != 0)
            {
                for (new i = 0;i < scriptCount;i++)
                {
                    if (strcmp(buffer,scripts[i][0]) == 0)
                    {
                        strcopy(buffer,64,scripts[i][1]);
                        break;
                    }
                }
                script[spawnPoints][0] = buffer;
            }
            if (args > 10)
            {
                GetCmdArg(11, buffer, sizeof(buffer));
                respawnTime[spawnPoints] = StringToFloat(buffer);
                if (args > 11)
                {
                    GetCmdArg(12, buffer, sizeof(buffer));
                    if (strcmp(buffer,"pickup") == 0)
                        respawnMethod[spawnPoints] = HOOK_TOUCH;
                    else if (strcmp(buffer,"static") == 0)
                        respawnMethod[spawnPoints] = HOOK_STATIC|HOOK_TOUCH;
                    else if ((strcmp(buffer,"nohook") == 0) || (strcmp(buffer,"nopickup") == 0))
                        respawnMethod[spawnPoints] = HOOK_NOHOOK;
                    else if (strcmp(buffer,"constant") == 0)
                        respawnMethod[spawnPoints] = HOOK_CONSTANT|HOOK_TOUCH;
                    else
                    {
                        new n = StringToInt(buffer)
                        switch (n)
                        {
                            case -1: respawnMethod[spawnPoints] = HOOK_NOHOOK;
                            case 0: respawnMethod[spawnPoints] = HOOK_TOUCH;
                            case 1: respawnMethod[spawnPoints] = HOOK_STATIC|HOOK_TOUCH;
                            case 2: respawnMethod[spawnPoints] = HOOK_CONSTANT|HOOK_TOUCH;
                            case 22: respawnMethod[spawnPoints] = HOOK_STATIC|HOOK_DEACTIVE|HOOK_TOUCH;
                            default: respawnMethod[spawnPoints] = n;
                        }
                    }
                    if (args > 12)
                    {
                        for (new i = 13; i <= args; i++)
                        {
                            GetCmdArg(i, buffer, sizeof(buffer));
                            StrCat(rCommand[spawnPoints][0],128,buffer);
                            StrCat(rCommand[spawnPoints][0],128," ");
                        }
                    }
                }
            }
        }
    }
    else
        respawnMethod[spawnPoints] = HOOK_NOHOOK;
    if (g_enable)
        spawnReward(spawnPoints);
    if (client != 0)
        autoSave(SAVE_EDIT,true);
    CRespondToCommand(client, "[SM] Added reward spawn point #{green}%d",spawnPoints);
    return Plugin_Handled;
}

RespondModifyUsage(client)
{
    CRespondToCommand(client, "[SM] Usage: {green}sm_mrw_modify{default} <{green}#reward_id|name{default}> [{green}OPTIONS{default} ...] [{green}command{default} ...]");
    CRespondToCommand(client, "[SM]    {green}OPTIONS{default} is exactly the same as {green}sm_mrw_add{default} with the following exceptions:");
    CRespondToCommand(client, "[SM]       {green}-o{default} - Origin coordinates default to the reward's if not specified.");
    CRespondToCommand(client, "[SM]       {green}-r{default} - Rotation angles can now be relative.");
    CRespondToCommand(client, "[SM]       {green}-h{default} - No help switch, because it breaks the flow of this command.");
    CRespondToCommand(client, "[SM]    Use {green}sm_mrw_add -h{default} for a detailed paragraph about the {green}OPTIONS{default}.");
    CRespondToCommand(client, "[SM]    If any combination of options that result in a conflict are used, an error explaining why that specific option could not be set will be displayed. Other options will still be applied.");
    CRespondToCommand(client, "[SM]    If any multi-argument options are missing arguments, the command will stop where the error occured. This might cause undefined behaviour, and you will need to manually {green}sm_mrw_respawn{default} the reward.");
}

public Action:modifySpawnPoint(client, args)
{
    if (client > 0)
    {
        new flagBits = GetUserFlagBits(client);
        if (((flagBits & ADMFLAG_ROOT) == 0) && ((flagBits & g_createFlag) != g_createFlag))
        {
            ReplyToCommand(client,"[SM] You do not have access to this command.");
            return Plugin_Handled;
        }
    }
    if (args < 2)
    {
        RespondModifyUsage(client);
        return Plugin_Handled;
    }
    decl String:buffer[128];
    GetCmdArg(1,buffer,128);
    new spawnPoints = getRewardID(buffer,client);
    if (spawnPoints < 0)
    {
        RespondToCommand(client, "[SM] Error: Unknown reward '%s'",buffer);
        return Plugin_Handled;
    }
    if (spawnEnts[spawnPoints] > -1)
        killReward(spawnPoints);
    
    new nextArg = 2;
    new bool:lastArg = false;
    new bool:err = false;
    new bool:release = false;
    new whichCommand = 0;
    
    decl String:originalType[32];
    decl String:originalModel[64];
    strcopy(originalType,32,entType[spawnPoints]);
    strcopy(originalModel,64,model[spawnPoints]);
    
    new String:strCoords[3][16];
    
    for (;nextArg <= args;nextArg++)
    {
        if (nextArg == args)
            lastArg = true;
        GetCmdArg(nextArg,buffer,64);
        if (buffer[0] == '-')
        {
            if (buffer[1] == '-')
            {
                nextArg++;
                break;
            }
            switch (buffer[1])
            {
                case 'P': // Shortcut for -d pickup
                {
                    respawnMethod[spawnPoints] &= ~HOOK_STATIC;
                    respawnMethod[spawnPoints] &= ~HOOK_CONSTANT;
                    respawnMethod[spawnPoints] |= HOOK_TOUCH;
                }
                case 'S': // Shortcut for -d static
                {
                    respawnMethod[spawnPoints] &= ~HOOK_CONSTANT;
                    respawnMethod[spawnPoints] |= HOOK_STATIC|HOOK_TOUCH;
                }
                case 'C': // Shortcut for -d constant
                {
                    respawnMethod[spawnPoints] &= ~HOOK_STATIC;
                    respawnMethod[spawnPoints] |= HOOK_CONSTANT|HOOK_TOUCH;
                }
                case 'H': // Shortcut for -d hurt
                {
                    respawnMethod[spawnPoints] |= HOOK_HURT;
                }
                case 'K': // Shortcut for -d kill
                {
                    respawnMethod[spawnPoints] |= HOOK_HURT|HOOK_KILL;
                }
                case 'N': // Shortcut for -d notouch
                {
                    respawnMethod[spawnPoints] &= ~HOOK_TOUCH;
                }
                case 'A': // heAlth
                {
                    if (lastArg)
                        err = true;
                    else
                    {
                        GetCmdArg(++nextArg,buffer,64);
                        if (!StrIsDigit(buffer))
                            err = true;
                        else
                            entHealth[spawnPoints] = StringToFloat(buffer);
                    }
                }
                case 'b':
                {
                    if (lastArg)
                        err = true;
                    else
                    {
                        GetCmdArg(++nextArg,buffer,64);
                        new base = getRewardID(buffer,client);
                        if (!isValidReward(base))
                        {
                            resetReward(spawnPoints);
                            RespondToCommand(client, "[SM] Error: Unknown reward '%s'",buffer);
                            return Plugin_Handled;
                        }
                        defSpawnCoords[spawnPoints] = defSpawnCoords[base];
                        defSpawnAngles[spawnPoints] = defSpawnAngles[base];
                        respawnMethod[spawnPoints] = respawnMethod[base];
                        model[spawnPoints] = model[base];
                        entType[spawnPoints] = entType[base];
                        rCommand[spawnPoints][0] = rCommand[base][0];
                        rCommand[spawnPoints][1] = rCommand[base][1];
                        script[spawnPoints][0] = script[base][0];
                        script[spawnPoints][1] = script[base][1]
                        respawnTime[spawnPoints] = respawnTime[base];
                    }
                }
                case 'c': // Coords
                {
                    if (lastArg)
                        err = true;
                    else
                    {
                        GetCmdArg(nextArg+1,buffer,64);
                        if (strcmp(buffer,"@aim") == 0)
                        {
                            nextArg++;
                            if ((client > 0) && (IsClientInGame(client)))
                                SetTeleportEndPoint(client,defSpawnCoords[spawnPoints]);
                        }
                        else if ((args-nextArg) < 3)
                            err = true;
                        else
                        {
                            for (new i = 0;i < 3;i++)
                                GetCmdArg(++nextArg,strCoords[i],16);
                        }
                    }
                }
                case 'd': // respawn methoD
                {
                    if (lastArg)
                        err = true;
                    else
                    {
                        GetCmdArg(++nextArg,buffer,64);
                        if (strcmp(buffer,"pickup") == 0)
                            respawnMethod[spawnPoints] = HOOK_TOUCH;
                        else if (strcmp(buffer,"static") == 0)
                            respawnMethod[spawnPoints] = HOOK_STATIC|HOOK_TOUCH;
                        else if ((strcmp(buffer,"nohook") == 0) || (strcmp(buffer,"nopickup") == 0))
                            respawnMethod[spawnPoints] = HOOK_NOHOOK;
                        else if (strcmp(buffer,"constant") == 0)
                            respawnMethod[spawnPoints] = HOOK_CONSTANT|HOOK_TOUCH;
                        else if (strcmp(buffer,"hurt") == 0)
                            respawnMethod[spawnPoints] |= HOOK_HURT;
                        else if (strcmp(buffer,"kill") == 0)
                            respawnMethod[spawnPoints] = HOOK_HURT|HOOK_KILL;
                        else if (strcmp(buffer,"notouch") == 0)
                            respawnMethod[spawnPoints] &= ~HOOK_TOUCH;
                        else
                            respawnMethod[spawnPoints] = StringToInt(buffer);
                    }
                }
                case 'e': // Entity type
                {
                    if (lastArg)
                        err = true;
                    else
                    {
                        GetCmdArg(++nextArg,buffer,64);
                        for (new i = 0;i < aliasCount;i++)
                        {
                            if (strcmp(buffer,aliases[i][0]) == 0)
                            {
                                strcopy(buffer,64,aliases[i][2]);
                                if ((strlen(aliases[i][1]) > 0) && (strcmp(model[spawnPoints],"null") != 0) && (strcmp(model[spawnPoints],"0") != 0))
                                    strcopy(model[spawnPoints],64,aliases[i][1]);
                                if ((strlen(aliases[i][3]) > 0) && (strcmp(script[spawnPoints][0],"null") != 0) && (strcmp(script[spawnPoints][0],"0") != 0))
                                    strcopy(script[spawnPoints][0],64,aliases[i][3]);
                                if ((strlen(aliases[i][4]) > 0) && (strcmp(script[spawnPoints][1],"null") != 0) && (strcmp(script[spawnPoints][1],"0") != 0))
                                    strcopy(script[spawnPoints][1],64,aliases[i][4]);
                                break;
                            }
                        }
                        strcopy(entType[spawnPoints],32,buffer);
                    }
                }
                case 'm': // Model
                {
                    if (lastArg)
                        err = true;
                    else
                    {
                        GetCmdArg(++nextArg,buffer,64);
                        for (new i = 0;i < aliasCount;i++)
                        {
                            if (strcmp(buffer,aliases[i][0]) == 0)
                            {
                                strcopy(buffer,64,aliases[i][1]);
                                if ((strlen(aliases[i][2]) > 0) && (strcmp(entType[spawnPoints],"null") != 0) && (strcmp(entType[spawnPoints],"0") != 0))
                                    strcopy(entType[spawnPoints],64,aliases[i][2]);
                                if ((strlen(aliases[i][2]) > 0) && (strcmp(script[spawnPoints][0],"null") != 0))
                                    strcopy(script[spawnPoints][0],64,aliases[i][2]);
                                if ((strlen(aliases[i][4]) > 0) && (strcmp(script[spawnPoints][1],"null") != 0) && (strcmp(script[spawnPoints][1],"0") != 0))
                                    strcopy(script[spawnPoints][1],64,aliases[i][4]);
                                break;
                            }
                        }
                        strcopy(model[spawnPoints],64,buffer);
                    }
                }
                case 'n': // Name
                {
                    if (lastArg)
                        err = true;
                    else
                    {
                        decl String:tempName[32];
                        GetCmdArg(++nextArg,tempName,32);
                        new dupe = getRewardID(tempName);
                        if ((dupe > -1) && (dupe != spawnPoints))
                            RespondToCommand(client, "[SM] Error: Reward #%d already exists with the same name, name not changed from '%s'!",dupe,entName[spawnPoints]);
                        else
                            strcopy(entName[spawnPoints],32,tempName);
                    }
                }
                case 'o': // Origin coords
                {
                    if (lastArg)
                        err = true;
                    else
                    {
                        GetCmdArg(nextArg+1,buffer,64);
                        if (strcmp(buffer,"@aim") == 0)
                        {
                            nextArg++;
                            if ((client > 0) && (IsClientInGame(client)))
                                SetTeleportEndPoint(client,defSpawnCoords[spawnPoints]);
                        }
                        else if ((args-nextArg) < 3)
                            err = true;
                        else
                        {
                            for (new i = 0;i < 3;i++)
                            {
                                GetCmdArg(++nextArg,buffer,17);
                                if (buffer[0] == '~')
                                {
                                    if (strlen(buffer) > 1)
                                    {
                                        StrErase(buffer,0,1);
                                        defSpawnCoords[spawnPoints][i] += StringToFloat(buffer);
                                    }
                                }
                                else
                                    defSpawnCoords[spawnPoints][i] = StringToFloat(buffer);
                            }
                        }
                    }
                }
                case 'O': // set origin to anOther player
                {
                    if (lastArg)
                        err = true;
                    else
                    {
                        GetCmdArg(++nextArg,buffer,64);
                        decl String:target_name[MAX_NAME_LENGTH];
                        decl target_list[1];
                        decl bool:tn_is_ml;
                        if (ProcessTargetString(buffer,
                                                                client,
                                                                target_list,
                                                                1,
                                                                0,
                                                                target_name,
                                                                MAX_NAME_LENGTH,
                                                                tn_is_ml) <= 0)
                        {
                            RespondToCommand(client, "[SM] Error: No target found, not changing origin.");
                        }
                        else
                            GetClientAbsOrigin(target_list[0],defSpawnCoords[spawnPoints]);
                    }
                }
                case 'D': // set origin to another rewarD
                {
                    if (lastArg)
                        err = true;
                    else
                    {
                        GetCmdArg(++nextArg,buffer,64);
                        new base = getRewardID(buffer,client);
                        if (!isValidReward(base))
                            RespondToCommand(client, "[SM] Error: Unknown reward '%s', not changing origin.",buffer);
                        else
                            defSpawnCoords[spawnPoints] = defSpawnCoords[base];
                    }
                }
                case 'p': // entProp values
                {
                    if (lastArg)
                        err = true;
                    else
                    {
                        GetCmdArg(++nextArg,buffer,64);
                        for (new i = 0;i < scriptCount;i++)
                        {
                            if (strcmp(buffer,scripts[i][0]) == 0)
                            {
                                strcopy(buffer,64,scripts[i][1]);
                                break;
                            }
                        }
                        strcopy(script[spawnPoints][1],64,buffer);
                    }
                }
                case 'r': // Rotation angles
                {
                    if ((args-nextArg) < 3)
                        err = true;
                    else
                    {
                        for (new i = 0;i < 3;i++)
                        {
                            GetCmdArg(++nextArg,buffer,64);
                            if (buffer[0] == '~')
                            {
                                if (strlen(buffer) > 1)
                                {
                                    StrErase(buffer,0,1);
                                    defSpawnAngles[spawnPoints][i] += StringToFloat(buffer);
                                }
                            }
                            else
                                defSpawnAngles[spawnPoints][i] = StringToFloat(buffer);
                        }
                    }
                }
                case 's': // Script
                {
                    if (lastArg)
                        err = true;
                    else
                    {
                        GetCmdArg(++nextArg,buffer,64);
                        for (new i = 0;i < scriptCount;i++)
                        {
                            if (strcmp(buffer,scripts[i][0]) == 0)
                            {
                                strcopy(buffer,64,scripts[i][1]);
                                break;
                            }
                        }
                        strcopy(script[spawnPoints][0],64,buffer);
                    }
                }
                case 't': // respawn Time
                {
                    if (lastArg)
                        err = true;
                    else
                    {
                        GetCmdArg(++nextArg,buffer,64);
                        respawnTime[spawnPoints] = StringToFloat(buffer);
                    }
                }
                case 'R': // Release after spawning
                {
                    release = true;
                }
                case 'T': // make the reward Turn every interval (spin)
                {
                    if ((args-nextArg) < 4)
                        err = true;
                    else
                    {
                        for (new i = 0;i < 3;i++)
                        {
                            GetCmdArg(++nextArg,buffer,64);
                            entSpin[spawnPoints][i] = StringToFloat(buffer);
                        }
                        GetCmdArg(++nextArg,buffer,64);
                        entSpinInt[spawnPoints] = StringToFloat(buffer);
                    }
                }
                case 'X': // make command set the kill command
                {
                    whichCommand = 1;
                }
                default:
                {
                    CRespondToCommand(client,"[SM] Ignoring unknown switch: {green}%s",buffer);
                }
            }
        }
        else
            break;
        if (err)
            break;
    }
    if ((strcmp(model[spawnPoints],"null") == 0) || (strcmp(model[spawnPoints],"0") == 0))
        model[spawnPoints] = "";
    if ((strcmp(entType[spawnPoints],"null") == 0) || (strcmp(entType[spawnPoints],"0") == 0))
        entType[spawnPoints] = "prop_physics_override";
    if (err)
    {
        CRespondToCommand(client, "[SM] Error modifying reward #{green}%d{default}. Some data may have been changed, some was not. This likely resulted in undefined behaviour.");
        CRespondToCommand(client, "[SM]  You will need to manually run {green}sm_mrw_respawn %d{default} before the reward will be active again.",spawnPoints,spawnPoints);
        return Plugin_Handled;
    }
    if ((strcmp(entType[spawnPoints],"prop_physics_override") == 0) && (strlen(model[spawnPoints]) < 1))
    {
        strcopy(entType[spawnPoints],32,originalType);
        strcopy(model[spawnPoints],64,originalModel);
        RespondToCommand(client, "[SM] Error: Either type is 'prop_physics_override', but no model was specified, or type was not defined. Cannot change type nor model.");
    }
    if (strlen(strCoords[0]) > 0)
    {
        for (new i = 0;i < 3;i++)
        {
            if (strCoords[i][0] == '~')
            {
                if (strlen(strCoords[i]) > 1)
                {
                    StrErase(strCoords[i],0,1);
                    defSpawnCoords[spawnPoints][i] += StringToFloat(strCoords[i]);
                }
            }
            else
                defSpawnCoords[spawnPoints][i] = StringToFloat(strCoords[i]);
        }
    }
    if ((strcmp(script[spawnPoints][0],"null") == 0) || (strcmp(script[spawnPoints][0],"0") == 0))
        script[spawnPoints][0] = "";
    if ((strcmp(script[spawnPoints][1],"null") == 0) || (strcmp(script[spawnPoints][1],"0") == 0))
        script[spawnPoints][1] = "";
    if (nextArg <= args)
    {
        GetCmdArg(nextArg++,rCommand[spawnPoints][whichCommand],128);
        for (;nextArg <= args;nextArg++)
        {
            GetCmdArg(nextArg,buffer,128);
            Format(rCommand[spawnPoints][whichCommand],128,"%s %s",rCommand[spawnPoints][whichCommand],buffer);
        }
    }
    if (g_enable)
    {
        spawnReward(spawnPoints);
        if (release)
        {
            CRespondToCommand(client, "[SM] Modified reward and released entity #{green}%d",spawnEnts[spawnPoints]);
            resetReward(spawnPoints);
        }
        else
            CRespondToCommand(client, "[SM] Modified reward spawn point #{green}%d",spawnPoints);
    }
    else
        CRespondToCommand(client, "[SM] Modified reward spawn point #{green}%d",spawnPoints);
    if (client != 0)
        autoSave(SAVE_EDIT,true);
    return Plugin_Handled;
}

stock getRewardID(const String:name[], any:client = 0)
{
    new id = -1;
    if ((client > 0) && (strcmp(name,"@n") == 0))
    {
        new Float:distance[2];
        new Float:dCoords[2][3];
        GetClientAbsOrigin(client,dCoords[0]);
        new bool:initialized;
        for (new i = 0;i < MAXSPAWNPOINT;i++)
        {
            if (strlen(entType[i]) < 1)
                continue;
            if (spawnEnts[i] > -1)
                GetEntPropVector(spawnEnts[i],Prop_Data,"m_vecOrigin",dCoords[1]);
            else
                dCoords[1] = defSpawnCoords[i];
            distance[0] = GetVectorDistance(dCoords[0],dCoords[1]);
            if ((!initialized) || (distance[0] < distance[1]))
            {
                initialized = true;
                distance[1] = distance[0];
                id = i;
            }
        }
    }
    else if (strcmp(name,"-1") == 0)
        id = getNewestReward();
    else if (StrIsDigit(name) > -1)
        id = StringToInt(name);
    else
    {
        for (new i = 0;i < MAXSPAWNPOINT;i++)
        {
            if (strcmp(entName[i],name) == 0)
            {
                id = i;
                break;
            }
        }
    }
    return id;
}

public Action:removeSpawnPoint(client, args)
{
    if (client > 0)
    {
        new flagBits = GetUserFlagBits(client);
        if (((flagBits & ADMFLAG_ROOT) == 0) && ((flagBits & g_basicFlag) != g_basicFlag))
        {
            ReplyToCommand(client,"[SM] You do not have access to this command.");
            return Plugin_Handled;
        }
    }
    if (args < 1)
    {
        RespondToCommand(client, "[SM] Usage: sm_mrw_remove <#id|name>");
        return Plugin_Handled;
    }
    decl String:buffer[32];
    decl range[2];
    new blen;
    new dots;
    new bool:saved = false;
    if (client > 0)
        saved = true;
    for (new i = 1;i <= args;i++)
    {
        range[0] = range[1] = -1;
        GetCmdArg(i, buffer, sizeof(buffer));
        blen = strlen(buffer);
        switch ((dots = StrFind(buffer,"..")))
        {
            case -1:
            {
                range[0] = range[1] = getRewardID(buffer,client);
            }
            case 0:
            {
                if (blen > 2)
                {
                    range[0] = 0;
                    StrErase(buffer,0,2);
                    range[1] = StringToInt(buffer);
                }
            }
            default:
            {
                range[0] = StringToInt(buffer);
                if ((dots+1) < blen)
                {
                    StrErase(buffer,0,dots+1);
                    range[1] = StringToInt(buffer);
                }
                else
                    range[1] = MAXSPAWNPOINT-1;
            }
        }
        if (range[0] > -1)
        {
            if (range[1] >= MAXSPAWNPOINT)
                range[1] = MAXSPAWNPOINT-1;
            for (new j = range[0];j <= range[1];j++)
                removeReward(j);
            if (!saved)
            {
                autoSave(SAVE_REMOVE,true);
                saved = true;
            }
            if (range[0] != range[1])
                RespondToCommand(client, "[SM] Removed rewards %d through %d.", range[0], range[1]);
            else
                RespondToCommand(client, "[SM] Removed reward #%d.", range[0]);
        }
        else
            RespondToCommand(client, "[SM] Unknown reward '%s'",buffer);
    }
    return Plugin_Handled;
}

public Action:removeSpawnPoints(client, args)
{
    if (client > 0)
    {
        new flagBits = GetUserFlagBits(client);
        if (((flagBits & ADMFLAG_ROOT) == 0) && ((flagBits & g_basicFlag) != g_basicFlag))
        {
            ReplyToCommand(client,"[SM] You do not have access to this command.");
            return Plugin_Handled;
        }
    }
    for (new i = 0; i < MAXSPAWNPOINT; i++)
        removeReward(i);
    if (client != 0)
        autoSave(SAVE_REMOVE,true);
    RespondToCommand(client, "[SM] Removed all rewards");
    return Plugin_Handled;
}

public Action:manuallyRespawnReward(client, args)
{
    if (client > 0)
    {
        new flagBits = GetUserFlagBits(client);
        if (((flagBits & ADMFLAG_ROOT) == 0) && ((flagBits & g_basicFlag) != g_basicFlag))
        {
            ReplyToCommand(client,"[SM] You do not have access to this command.");
            return Plugin_Handled;
        }
    }
    if (args < 1)
    {
        RespondToCommand(client, "[SM] Usage: sm_mrw_respawn <#id|name>");
        return Plugin_Handled;
    }
    decl String:buffer[32], point;
    GetCmdArg(1, buffer, sizeof(buffer));
    point = getRewardID(buffer,client);
    if (isValidReward(point))
    {
        //respawnReward(point);
        killReward(point);
        respawnMethod[point] &= ~HOOK_DEACTIVE;
        spawnReward(point);
        RespondToCommand(client, "[SM] Respawned reward #%d", point);
    }
    else
        RespondToCommand(client, "[SM] Error: Unknown reward '%s'",buffer);
    return Plugin_Handled;
}

triggerReward(index, client, inflictor = -1)
{
    decl String:cmdD[128];
    strcopy(cmdD,128,rCommand[index][0]);
    if ((inflictor > -1) && (strlen(rCommand[index][1]) > 0))
        strcopy(cmdD,128,rCommand[index][1]);
    if ((strlen(cmdD) > 0) && (strcmp(cmdD,"null") != 0))
    {
        decl String:cmdC[128];
        decl String:target[8];
        Format(target,8,"#%i",GetClientUserId(client));
        strcopy(cmdC,128,cmdD);
        ReplaceString(cmdC,128,"#player",target);
        ReplaceString(cmdC,128,"#reward",entName[index]);
        if (inflictor > -1)
        {
            decl String:flict[8];
            IntToString(inflictor,flict,8);
            ReplaceString(cmdC,128,"#inflictor",flict);
        }
        ServerCommand(cmdC);
    }
}

public Action:mapRewardPickUp(ent, client)
{
    if ((g_enable) && (client > 0) && (client <= MaxClients) && (IsClientInGame(client)))
    {
        new index = -1;
        for (new i = 0; i < MAXSPAWNPOINT; i++)
            if (spawnEnts[i] == ent) index = i;
        if (index > -1)
        {
            triggerReward(index,client);
            if (respawnMethod[index] & HOOK_STATIC)
            {
                SDKUnhook(spawnEnts[index], SDKHook_StartTouch, mapRewardPickUp);
                respawnMethod[index] |= HOOK_DEACTIVE;
                //respawnMethod[index] = 22;
            }
            if (!(respawnMethod[index] & HOOK_CONSTANT))
            {
                if (!(respawnMethod[index] & HOOK_STATIC))
                    killReward(index);
                if (respawnTime[index] < 0.0)
                    CreateTimer(g_respawnTime, timerRespawnReward, index);
                else if (respawnTime[index] > 0.0)
                    CreateTimer(respawnTime[index], timerRespawnReward, index);
            }
        }
    }
}

public Action:mapRewardTakeDamage(ent, &client, &inflictor, &Float:damage, &damageType)
{
    if ((g_enable) && (client > 0) && (client <= MaxClients) && (IsClientInGame(client)))
    {
        new index = -1;
        for (new i = 0; i < MAXSPAWNPOINT; i++)
            if (spawnEnts[i] == ent) index = i;
        if (index > -1)
        {
            //if ((damageMethod[index] != 1) || (respawnMethod[index] == 2))
            if ((!(respawnMethod[index] & HOOK_KILL)) || (respawnMethod[index] & HOOK_CONSTANT))
                triggerReward(index,client,inflictor);
            if (respawnMethod[index] & (HOOK_CONSTANT|HOOK_DEACTIVE))
            {
                damage = 0.0;
                return Plugin_Changed;
            }
            if (respawnMethod[index] & HOOK_KILL)
            {
                rewardKiller[index] = client;
                entDamage[index] += damage;
                CreateTimer(0.001, rewardTakeDamagePost, index);
            }
            else
            {
                if (respawnMethod[index] & HOOK_STATIC)
                {
                    respawnMethod[index] |= HOOK_DEACTIVE;
                    if (respawnMethod[index] & HOOK_TOUCH)
                        SDKUnhook(spawnEnts[index], SDKHook_StartTouch, mapRewardPickUp);
                }
                else
                    killReward(index);
                if (respawnTime[index] < 0.0)
                    CreateTimer(g_respawnTime, timerRespawnReward, index);
                else if (respawnTime[index] > 0.0)
                    CreateTimer(respawnTime[index], timerRespawnReward, index);
            }
        }
    }
    return Plugin_Continue;
}

// Only trigger if the reward was killed
public Action:rewardTakeDamagePost(Handle:Timer, any:index)
{
    if ((entHealth[index]) && (entHealth[index]-entDamage[index] <= 0.0))
        killReward(index);
    if (!IsValidEntity(spawnEnts[index]))
    {
        triggerReward(index,rewardKiller[index],rewardKiller[index]);
        respawnMethod[index] &= ~HOOK_DEACTIVE;
        if (respawnTime[index] < 0.0)
            CreateTimer(g_respawnTime, timerRespawnReward, index);
        else if (respawnTime[index] > 0.0)
            CreateTimer(respawnTime[index], timerRespawnReward, index);
    }
    /*else if ((entHealth[index] != NOHEALTH_TRACK) && (entHealth[index] < 1.0))
    {
        killReward(index);
        triggerReward(index,rewardKiller[index]);
        respawnMethod[index] &= ~HOOK_DEACTIVE;
        if (respawnTime[index] < 0.0)
            CreateTimer(g_respawnTime, timerRespawnReward, index);
        else if (respawnTime[index] > 0.0)
            CreateTimer(respawnTime[index], timerRespawnReward, index);
    }*/
    return Plugin_Stop;
}

//mass,0.1,inertia,1000.0?modelscale,float=2.0&DisableMotion

//proper format:    overridescript?key,type=value&key,type=value&...&input&input&...

// Thanks to GottZ for this: https://sm.alliedmods.net/api/index.php?fastload=show&id=398&
stock GetRealClientCount(bool:inGameOnly = true)
{
    new clients = 0;
    for (new i = 1; i <= GetMaxClients(); i++)
    {
        if (((inGameOnly) ? IsClientInGame(i) : IsClientConnected(i)) && !IsFakeClient(i))
        {
            clients++;
        }
    }
    return clients;
}

spawnReward(index)
{
    if ((strlen(entType[index]) == 0) || (GetRealClientCount() < 1))
        return;
    
    entDamage[index] = 0.0;
    
    if (respawnMethod[index] & HOOK_DEACTIVE)
    {
        respawnMethod[index] &= ~HOOK_DEACTIVE;
        if (IsValidEntity(spawnEnts[index]))
        {
            decl String:temp[32];
            GetEntPropString(spawnEnts[index], Prop_Data, "m_iName", temp, 32);
            if (strcmp(entName[index],temp) == 0)
            {
                if (respawnMethod[index] & HOOK_TOUCH)
                    SDKHook(spawnEnts[index], SDKHook_StartTouch, mapRewardPickUp);
                return;
            } // Don't return here incase the reward does not match so it can be made from scratch
        }
        else if (!(respawnMethod[index] & HOOK_STATIC))
        {
            if (respawnTime[index] < 0.0)
                CreateTimer(g_respawnTime, timerRespawnReward, index);
            else if (respawnTime[index] > 0.0)
                CreateTimer(respawnTime[index], timerRespawnReward, index);
            return;
        }
    }
    
    killReward(index);
    
    new entReward = CreateEntityByName(entType[index]);
    
    if (IsValidEntity(entReward))
    {
        SetEntPropString(entReward, Prop_Data, "m_iName", entName[index]);
        if ((strlen(model[index]) > 0) && (strcmp(model[index],"null") != 0))
            DispatchKeyValue(entReward, "model", model[index]);
        //DispatchKeyValueFloat(entReward, "solid", 0.0);
        //DispatchKeyValueFloat(entReward, "modelscale", 2.0);
        new spawned = 0;
        if (strlen(script[index][0]) > 0)
        {
            if (StrContains(script[index][0],"?") != -1)
            {
                new String:strMain[2][64];
                new String:strCurrent[64];
                new String:strKeys[2][64];
                new String:strType[16];
                new String:strTemp[64];
                ExplodeString(script[index][0],"?",strMain,2,64,true);
                Format(strMain[1],64,"%s&",strMain[1]);
                if (strcmp(strMain[0],"null") != 0)
                    DispatchKeyValue(entReward, "overridescript", strMain[0]);
                //PrintToServer("[SM] Debug0: %s | %s",strMain[0],strMain[1]);
                while (SplitString(strMain[1],"&",strCurrent,64) > -1)
                {
                    //PrintToServer("[SM] Debug1: %s",strCurrent);
                    if (StrContains(strCurrent,",") == -1)
                    {
                        if (!spawned)
                        {
                            DispatchSpawn(entReward);
                            spawned = 1;
                        }
                        AcceptEntityInput(entReward,strCurrent);
                    }
                    else
                    {
                        ExplodeString(strCurrent,",",strKeys,2,64,true);
                        //PrintToServer("[SM] Debug2: %s | %s",strKeys[0],strKeys[1]);
                        SplitString(strKeys[1],"=",strType,16);
                        Format(strType,16,"%s=",strType);
                        ReplaceStringEx(strKeys[1],64,strType,"",-1,0);
                        //PrintToServer("[SM] Debug3: %s | %s",strType,strKeys[1]);
                        if ((strcmp(strType,"float=") == 0) || (strcmp(strType,"int=") == 0))
                            DispatchKeyValueFloat(entReward,strKeys[0],StringToFloat(strKeys[1]));
                        else if (strcmp(strType,"string=") == 0)
                            DispatchKeyValue(entReward,strKeys[0],strKeys[1]);
                        else
                            DispatchKeyValue(entReward,strKeys[0],strKeys[1]);
                    }
                    Format(strTemp,64,"%s&",strCurrent);
                    ReplaceStringEx(strMain[1],64,strTemp,"",-1,0);
                    ReplaceStringEx(strMain[1],64,strCurrent,"",-1,0);
                    //PrintToServer("[SM] Debug4: %s",strMain[1]);
                }
            }
            else
                DispatchKeyValue(entReward, "overridescript", script[index][0]);
        }
        if (strlen(script[index][1]) > 0)
        {
            //[prop_type:]key,[type=]value&[prop_type:]key,[type=]value
            decl String:strMain[65];
            decl String:strCurrent[64];
            decl String:strKeys[2][64];
            decl String:strType[16];
            decl String:strTemp[65];
            strcopy(strMain,65,script[index][1]);
            StrCat(strMain,65,"&");
            new PropType:propType;
            while (SplitString(strMain,"&",strCurrent,64) > -1)
            {
                if (StrContains(strCurrent,",") > -1)
                {
                    propType = Prop_Data;
                    if ((strlen(strCurrent) > 2) && (strCurrent[1] == ':'))
                    {
                        if (strCurrent[0] == '1')
                            propType = Prop_Send;
                        StrErase(strCurrent,0,2);
                    }
                    if (!spawned)
                    {
                        DispatchSpawn(entReward);
                        spawned = 1;
                    }
                    ExplodeString(strCurrent,",",strKeys,2,64,true);
                    SplitString(strKeys[1],"=",strType,16);
                    StrCat(strType,16,"=");
                    ReplaceStringEx(strKeys[1],64,strType,"",-1,0);
                    if (strcmp(strType,"float=") == 0)
                        SetEntPropFloat(entReward, propType, strKeys[0], StringToFloat(strKeys[1]));
                    else if (strcmp(strType,"int=") == 0)
                        SetEntProp(entReward, propType, strKeys[0], StringToInt(strKeys[1]));
                    else if (strcmp(strType,"vec=") == 0)
                    {
                        new Float:vec[3];
                        decl String:strVec[3][16];
                        //strcopy(strTemp,65,strMain + strlen(strKeys[0]));
                        /*new x = strlen(strKeys[0]), y = 0;
                        for (new z = strlen(strMain);(x+y) < z;y++)
                            strTemp[y] = strMain[x+y];
                        strTemp[y] = '\0';*/
                        //StrErase(strKeys[1],0,4);
                        //ExplodeString(strTemp,",",strVec,3,16,true);
                        ExplodeString(strKeys[1],",",strVec,3,16,true);
                        for (new i = 0;i < 3;i++)
                            vec[i] = StringToFloat(strVec[i]);
                        SetEntPropVector(entReward, propType, strKeys[0], vec);
                    }
                    else if (strcmp(strType,"ent=") == 0)
                        SetEntPropEnt(entReward, propType, strKeys[0], StringToInt(strKeys[1]));
                    else
                        SetEntPropString(entReward, propType, strKeys[0], strKeys[1]);
                }
                strcopy(strTemp,65,strCurrent);
                StrCat(strTemp,65,"&");
                ReplaceStringEx(strMain,64,strTemp,"",-1,0);
                ReplaceStringEx(strMain,64,strCurrent,"",-1,0);
            }
        }
        if (!spawned)
            DispatchSpawn(entReward);
        TeleportEntity(entReward, defSpawnCoords[index], defSpawnAngles[index], NULL_VECTOR);
//        if (ignorePhys[index] != 0)
//            AcceptEntityInput(entReward, "DisableMotion");
        //SetEntityGravity(entReward, 1.0); //Doesn't seem to work.
        //HookSingleEntityOutput(entReward, "OnStartTouch", mapRewardPickUp);
        if (respawnMethod[index] & HOOK_DEACTIVE)
        {
            if (respawnTime[index] < 0.0)
                CreateTimer(g_respawnTime, timerRespawnReward, index);
            else if (respawnTime[index] > 0.0)
                CreateTimer(respawnTime[index], timerRespawnReward, index);
        }
        else
        {
            if (respawnMethod[index] & HOOK_TOUCH)
                SDKHook(entReward, SDKHook_StartTouch, mapRewardPickUp);
            if (respawnMethod[index] & HOOK_HURT)
                SDKHook(entReward, SDKHook_OnTakeDamage, mapRewardTakeDamage);
        }
        /*if (respawnMethod[index] == 22)
        {
            if (respawnTime[index] < 0.0)
                CreateTimer(g_respawnTime, timerRespawnReward, index);
            else if (respawnTime[index] > 0.0)
                CreateTimer(respawnTime[index], timerRespawnReward, index);
        }
        else if (respawnMethod[index] > -1)
            SDKHook(entReward, SDKHook_StartTouch, mapRewardPickUp);*/
        if (entSpinInt[index] > 0.0)
        {
            entSpinAngles[index] = defSpawnAngles[index];
            entTimers[index] = CreateTimer(entSpinInt[index], timerSpinEnt, index, TIMER_REPEAT);
        }
        spawnEnts[index] = entReward;
    }
    else
    {
        PrintToChatAll("[SM] maprewards: Error, unable to spawn reward #%i",index);
        PrintToServer("[SM] maprewards: Error, unable to spawn reward #%i",index);
    }
}

/*
sm_maprewards_add_here gift null null?DisableMotion&modelscale,float:2.0
[SM] Debug0: null | DisableMotion&modelscale,float&
[SM] Debug1: DisableMotion
[SM] Debug2: DisableMotion | 
[SM] Debug3: : | 
[SM] Debug4: modelscale,float&
[SM] Debug1: modelscale,float
[SM] Debug2: modelscale | float
[SM] Debug3: :: | float
[SM] Debug4: 

NIGathan: !maprewards_add_here gift null null?DisableMotion&modelscale,float=2.0
[SM] Debug0: null | DisableMotion&modelscale,float=2.0&
[SM] Debug1: DisableMotion
[SM] Debug2: DisableMotion |
[SM] Debug3: = |
[SM] Debug4: modelscale,float=2.0&
[SM] Debug1: modelscale,float=2.0
[SM] Debug2: modelscale | float=2.0
[SM] Debug3: float= | 2.0
[SM] Debug4:

*/

respawnReward(index)
{
    /*if (respawnMethod[index] == 22)
        respawnMethod[index] = 1;*/
    //respawnMethod[index] &= ~HOOK_DEACTIVE;
    spawnReward(index);
}

public Action:timerRespawnReward(Handle:Timer, any:index)
{
    if (g_enable)
    {
        if (index == -1)
            spawnRewards();
        else
            respawnReward(index);
    }
    return Plugin_Stop;
}

public Action:timerSpinEnt(Handle:Timer, any:index)
{
    if (g_enable)
    {
        if ((index < 0) || (spawnEnts[index] < 0) || (!IsValidEntity(spawnEnts[index])))
        {
            entTimers[index] = INVALID_HANDLE;
            return Plugin_Stop;
        }
        for (new i = 0;i < 3;i++)
        {
            entSpinAngles[index][i] += entSpin[index][i];
            if (entSpinAngles[index][i] > 360.0)
                entSpinAngles[index][i] -= 360.0;
            if (entSpinAngles[index][i] < -360.0)
                entSpinAngles[index][i] += 360.0;
        }
        TeleportEntity(spawnEnts[index],NULL_VECTOR,entSpinAngles[index],NULL_VECTOR);
        return Plugin_Continue;
    }
    return Plugin_Stop;
}

// Borrowed from pumpkin.sp by linux_lover aka pheadxdll: https://forums.alliedmods.net/showthread.php?p=976177
// From pheadxdll: "Credits to Spaz & Arg for the positioning code. Taken from FuncommandsX."
// Slightly modified to remove globals.
stock bool:SetTeleportEndPoint(client, Float:pos[3])
{
	decl Float:vAngles[3];
	decl Float:vOrigin[3];
	decl Float:vBuffer[3];
	decl Float:vStart[3];
	decl Float:Distance;
	
	GetClientEyePosition(client,vOrigin);
	GetClientEyeAngles(client, vAngles);
	
    //get endpoint for teleport
	new Handle:trace = TR_TraceRayFilterEx(vOrigin, vAngles, MASK_SHOT, RayType_Infinite, TraceEntityFilterPlayer);

	if(TR_DidHit(trace))
	{   	 
   	 	TR_GetEndPosition(vStart, trace);
		GetVectorDistance(vOrigin, vStart, false);
		Distance = -35.0;
   	 	GetAngleVectors(vAngles, vBuffer, NULL_VECTOR, NULL_VECTOR);
		pos[0] = vStart[0] + (vBuffer[0]*Distance);
		pos[1] = vStart[1] + (vBuffer[1]*Distance);
		pos[2] = vStart[2] + (vBuffer[2]*Distance);
	}
	else
	{
		CloseHandle(trace);
		return false;
	}
	
	CloseHandle(trace);
	return true;
}

public bool:TraceEntityFilterPlayer(entity, contentsMask)
{
	return entity > GetMaxClients() || !entity;
}

