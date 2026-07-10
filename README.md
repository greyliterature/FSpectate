# Summary
This is a fork of FSpectate made by FPtje with some added features / changes <br/>
If the fork seems to have odd changes / plans, that is because I am trying to shift it away from being a purely utilitarian admin mod tool. <br/>

The fork intends to make it a bit more similar to a competitive game's spectate system. <br/>
The system it is planned to be modelled after is Quake live. <br/>
Quake live's spectate has multiple differences from FSpectate that make it more fair and less "ghosty": 
1. No beams <br/>
2. No ESP <br/>
3. No third person <br/>
etc.

# Additions / changes 

## Beams come from shootpos instead of gunpos
Player beams coming from the barrel of their gun was odd (especially with the physgun) and not very useful. <br/>
Beams have been changed to start from the shootpos of the player instead to be more intuitive. <br/>

## Players can be forced into spectate and made unable to exit
This allows developers to force their players into spectate for custom gamemodes instead of using the, in my experience, worse gmod Player:Spectate() system <br/>

## drawInputs()
All of the spectated player's inputs are shown on screen to the spectator as a keyboard. <br/>

## Spectating while dead
Any player that is spectating while dead will have their viewangle set to where they were last looking before spectating. <br/>
This solves the problem of players knowing when someone is spectating by spectating them and watching them look around (or using cheats to get their eyetrace?) <br/>

## hideHUD()
hideHUD() function was added to hide HUD elements like health, armor, and ammo. <br/>
Elements like those are not useful while spectating because they are not the health, armor, or ammo of the player being spectated. <br/>

# Hooks
Some hooks are planned on being added, but currently the only hooks in the fork are the ones that FPTje made originally. <br/>

## Prexisting hooks

### FSpectate_canSpectate, ply, target (serverside)
Called in startSpectating() whenever a client requests to spectate. <br/>
This is called AFTER CAMI.PlayerHasAccess(ply), so if the player does not have access according to CAMI, the hook is not run. <br/>

### FSpectate_start, ply, target (serverside)
Called after FSpectate_canSpectate in startSpectating() <br/>

### FSpectate_stop, ply (serverside)
Called in endSpectate <br/>

### Planned hooks
FSpectate_canFreeRoam (clientside) -- self explanatory <br/>
FSpectate_canSpecPlayer, obj (clientside) -- this is a redundancy of FSpectate_canSpectate (serverside), because it is more convenient for the client to know who they can and cannot spectate without extra networking (this allows the client to make a table of players they can spectate very simply) <br/>
FSpectate_canThirdPerson (clientside) <br/>
FSpectate_canShowBeams (clientside) <br/>
FSpectate_canShowESP (clientside) <br/>
