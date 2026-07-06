FSpectate = {}

local stopSpectating, startFreeRoam
local isSpectating = false
local specEnt
local thirdperson = true
local isRoaming = false
local roamPos -- the position when roaming free
local roamVelocity = Vector(0)
local thirdPersonDistance = 100

/*---------------------------------------------------------------------------
Returns if the localplayer is spectating
---------------------------------------------------------------------------*/
function FSpectate.isSpectating()
    return isSpectating
end

/*---------------------------------------------------------------------------
Retrieve the current spectated player
---------------------------------------------------------------------------*/
function FSpectate.getSpecEnt()
    if isSpectating and not isRoaming then
        return IsValid(specEnt) and specEnt or nil
    else
        return nil
    end
end

/*---------------------------------------------------------------------------
startHooks
FAdmin tab buttons
---------------------------------------------------------------------------*/
hook.Add("Initialize", "FSpectate", function()
    surface.CreateFont("UiBold", {
        size = 16,
        weight = 800,
        antialias = true,
        shadow = false,
        font = "Verdana"})

    if not FAdmin then return end
    FAdmin.StartHooks["zzSpectate"] = function()
        FAdmin.Commands.AddCommand("Spectate", nil, "<Player>")

        -- Right click option
        FAdmin.ScoreBoard.Main.AddPlayerRightClick("Spectate", function(ply)
            if not IsValid(ply) then return end
            RunConsoleCommand("FSpectate", ply:UserID())
        end)

        local canSpectate = false
        local function calcAccess()
            CAMI.PlayerHasAccess(LocalPlayer(), "FSpectate", function(b, _)
                canSpectate = b
            end)
        end

        -- Spectate option in player menu
        FAdmin.ScoreBoard.Player:AddActionButton("Spectate", "fadmin/icons/spectate", Color(0, 200, 0, 255), function(ply) calcAccess() return canSpectate and ply ~= LocalPlayer() end, function(ply)
            if not IsValid(ply) then return end
            RunConsoleCommand("FSpectate", ply:UserID())
        end)
    end
end)

/*---------------------------------------------------------------------------
Get the thirdperson position
---------------------------------------------------------------------------*/
local function getThirdPersonPos(ent)
    local aimvector = LocalPlayer():GetAimVector()
    local startPos = ent:IsPlayer() and ent:GetShootPos() or ent:LocalToWorld(ent:OBBCenter())
    local endpos = startPos - aimvector * thirdPersonDistance

    local tracer = {
        start = startPos,
        endpos = endpos,
        filter = specEnt
    }

    local trace = util.TraceLine(tracer)

    return trace.HitPos + trace.HitNormal * 10
end

/*---------------------------------------------------------------------------
Get the CalcView table
---------------------------------------------------------------------------*/
local view = {}
local function getCalcView()
    if not isRoaming then
        if thirdperson then
            view.origin = getThirdPersonPos(specEnt)
            view.angles = LocalPlayer():EyeAngles()
        else
            view.origin = specEnt:IsPlayer() and specEnt:GetShootPos() or specEnt:LocalToWorld(specEnt:OBBCenter())
            view.angles = specEnt:IsPlayer() and specEnt:EyeAngles() or specEnt:GetAngles()
        end

        roamPos = view.origin
        view.drawviewer = false

        return view
    end

    view.origin = roamPos
    view.angles = LocalPlayer():EyeAngles()
    view.drawviewer = true

    return view
end

/*---------------------------------------------------------------------------
specCalcView
Override the view for the player to look through the spectated player's eyes
---------------------------------------------------------------------------*/
local function specCalcView(ply, origin, angles, fov)
    if not IsValid(specEnt) and not isRoaming then
        startFreeRoam()
        return
    end

    view = getCalcView()

    if IsValid(specEnt) then
        specEnt:SetNoDraw(not thirdperson)
    end

    return view
end

/*---------------------------------------------------------------------------
Find the right player to spectate
---------------------------------------------------------------------------*/
local function findNearestObject()
    local aimvec = LocalPlayer():GetAimVector()

    local fromPos = not isRoaming and IsValid(specEnt) and specEnt:EyePos() or roamPos

    local lookingAt = util.QuickTrace(fromPos, aimvec * 5000, LocalPlayer())
    local ent = lookingAt.Entity

    if IsValid(ent) then return ent end

    local foundPly, foundDot = nil, 0

    for _, ply in ipairs(player.GetAll()) do
        if not IsValid(ply) or ply == LocalPlayer() then continue end

        local pos = ply:GetShootPos()
        local dot = (pos - fromPos):GetNormalized():Dot(aimvec)

        -- Discard players you're not looking at
        if dot < 0.97 then continue end
        -- not a better alternative
        if dot < foundDot then continue end

        local trace = util.QuickTrace(fromPos, pos - fromPos, ply)

        if trace.Hit then continue end

        foundPly, foundDot = ply, dot
    end

    return foundPly
end

/*---------------------------------------------------------------------------
Spectate the person you're looking at while you're roaming
---------------------------------------------------------------------------*/
local function spectateLookingAt()
    local obj = findNearestObject()

    if not IsValid(obj) then return end

    isRoaming = false
    specEnt = obj

    net.Start("FSpectateTarget")
        net.WriteEntity(obj)
    net.SendToServer()
end

/*---------------------------------------------------------------------------
specBinds
Change binds to perform spectate specific tasks
---------------------------------------------------------------------------*/
-- Manual keysDown table, so I can return true in plyBindPress and still detect key presses
local keysDown = {}
local function specBinds(ply, bind, pressed)
    local key = input.LookupBinding(bind)

    if bind == "+jump" and pressed then
        stopSpectating()
        return true
    elseif bind == "+reload" and pressed then
        local pos = getCalcView().origin - Vector(0, 0, 64)
        RunConsoleCommand("FTPToPos", string.format("%d, %d, %d", pos.x, pos.y, pos.z),
            string.format("%d, %d, %d", roamVelocity.x, roamVelocity.y, roamVelocity.z))
        stopSpectating()
    elseif bind == "+attack" and pressed then
        if not isRoaming then
            startFreeRoam()
        else
            spectateLookingAt()
        end
        return true
    elseif bind == "+attack2" and pressed then
        if isRoaming then
            roamPos = roamPos + LocalPlayer():GetAimVector() * 500
            return true
        end
        thirdperson = not thirdperson

        return true
    elseif isRoaming and not LocalPlayer():KeyDown(IN_USE) then
        local keybind = string.upper(string.match(bind, "+([a-z A-Z 0-9]+)") or "")
        if not keybind or keybind == "USE" or keybind == "SHOWSCORES" or string.find(bind, "messagemode") then return end

        keysDown[keybind] = pressed

        return true
    elseif not isRoaming and thirdperson and (key == "MWHEELDOWN" or key == "MWHEELUP") then
        thirdPersonDistance = thirdPersonDistance + 10 * (key == "MWHEELDOWN" and 1 or -1)
    end
    -- Do not return otherwise, spectating admins should be able to move to avoid getting detected
end

/*---------------------------------------------------------------------------
Scoreboardshow
Set to main view when roaming, open on a player when spectating
---------------------------------------------------------------------------*/
local function fadminmenushow()
    if isRoaming then
        FAdmin.ScoreBoard.ChangeView("Main")
    elseif IsValid(specEnt) and specEnt:IsPlayer() then
        FAdmin.ScoreBoard.ChangeView("Main")
        FAdmin.ScoreBoard.ChangeView("Player", specEnt)
    end
end


/*---------------------------------------------------------------------------
RenderScreenspaceEffects
Draws the lines from players' eyes to where they are looking
---------------------------------------------------------------------------*/
local LineMat = Material("cable/new_cable_lit")
local linesToDraw = {}
local function lookingLines()
    if not linesToDraw[0] then return end

    render.SetMaterial(LineMat)

    cam.Start3D(view.origin, view.angles)
        for i = 0, #linesToDraw, 3 do
            render.DrawBeam(linesToDraw[i], linesToDraw[i + 1], 4, 0.01, 10, linesToDraw[i + 2])
        end
    cam.End3D()
end

/*---------------------------------------------------------------------------
gunpos
Gets the position of a player's gun
---------------------------------------------------------------------------*/
/*
local function gunpos(ply)
    local wep = ply:GetActiveWeapon()
    if not IsValid(wep) then return ply:EyePos() end
    local att = wep:GetAttachment(1)
    if not att then return ply:EyePos() end
    return att.Pos
end
*/

/*---------------------------------------------------------------------------
Spectate think
Free roaming position updates
---------------------------------------------------------------------------*/
local function specThink()
    local ply = LocalPlayer()

    -- Update linesToDraw
    local pls = player.GetAll()
    local lastPly = 0
    local skip = 0
    for i = 0, #pls - 1 do
        local p = pls[i + 1]
        if not IsValid(p) then continue end
        if not isRoaming and p == specEnt and not thirdperson then skip = skip + 3 continue end

        local tr = p:GetEyeTrace()
        local sp = p:GetShootPos()

        local pos = i * 3 - skip

        linesToDraw[pos] = tr.HitPos
        linesToDraw[pos + 1] = sp
        linesToDraw[pos + 2] = team.GetColor(p:Team())
        lastPly = i
    end

    -- Remove entries from linesToDraw that don't match with a player anymore
    for i = #linesToDraw, lastPly * 3 + 3, -1 do linesToDraw[i] = nil end

    if not isRoaming or keysDown["USE"] then return end

    local roamSpeed = 1000
    local aimVec = ply:GetAimVector()
    local direction
    local frametime = RealFrameTime()

    if keysDown["FORWARD"] then
        direction = aimVec
    elseif keysDown["BACK"] then
        direction = -aimVec
    end

    if keysDown["MOVELEFT"] then
        local right = aimVec:Angle():Right()
        direction = direction and (direction - right):GetNormalized() or -right
    elseif keysDown["MOVERIGHT"] then
        local right = aimVec:Angle():Right()
        direction = direction and (direction + right):GetNormalized() or right
    end

    if keysDown["SPEED"] then
        roamSpeed = 2500
    elseif keysDown["WALK"] or keysDown["DUCK"] then
        roamSpeed = 300
    end

    roamVelocity = (direction or Vector(0, 0, 0)) * roamSpeed

    roamPos = roamPos + roamVelocity * frametime
end

/*---------------------------------------------------------------------------
drawInputs
Draw spectated player's inputs on screen
---------------------------------------------------------------------------*/
CreateClientConVar("fspectate_showinputs_positionx", "50", true, false)
local fspectate_showinputs_positionxValue = GetConVar("fspectate_showinputs_positionx"):GetFloat()
cvars.AddChangeCallback("fspectate_showinputs_positionx", function(convar, oldValue, newValue)
    --
    fspectate_showinputs_positionxValue = newValue
end, "fspectate_showinputs_positionx")

CreateClientConVar("fspectate_showinputs_positiony", "115", true, false)
local fspectate_showinputs_positionyValue = GetConVar("fspectate_showinputs_positiony"):GetFloat()
cvars.AddChangeCallback("fspectate_showinputs_positiony", function(convar, oldValue, newValue)
    --
    fspectate_showinputs_positionyValue = newValue
end, "fspectate_showinputs_positiony")

CreateClientConVar("fspectate_showinputs_percentsize", "0.1", true, false)
local fspectate_showinputs_percentsizeValue = GetConVar("fspectate_showinputs_percentsize"):GetFloat()
cvars.AddChangeCallback("fspectate_showinputs_percentsize", function(convar, oldValue, newValue)
    --
    fspectate_showinputs_percentsizeValue = newValue
end, "fspectate_showinputs_percentsize")

surface.CreateFont("KeyboardFont", {
    font = "Trebuchet MS",
    extended = false,
    size = ScreenScale(54 * fspectate_showinputs_percentsizeValue),
    weight = 500,
    blursize = 0,
    scanlines = 0,
    antialias = true,
    underline = false,
    italic = false,
    strikeout = false,
    symbol = false,
    rotary = false,
    shadow = false,
    additive = false,
    outline = false,
})

local KeyboardInputs = {
    ["Esc"] = {
        input = KEY_ESCAPE,
        positionx = 0,
        positiony = 0,
        keysize = 100
    },
    ["F1"] = {
        input = KEY_F1,
        positionx = 100,
        positiony = 0,
        keysize = 100
    },
    ["F2"] = {
        input = KEY_F2,
        positionx = 200,
        positiony = 0,
        keysize = 100
    },
    ["F3"] = {
        input = KEY_F3,
        positionx = 300,
        positiony = 0,
        keysize = 100
    },
    ["F4"] = {
        input = KEY_F4,
        positionx = 400,
        positiony = 0,
        keysize = 100
    },
    ["F5"] = {
        input = KEY_F5,
        positionx = 500,
        positiony = 0,
        keysize = 100
    },
    ["F6"] = {
        input = KEY_F6,
        positionx = 600,
        positiony = 0,
        keysize = 100
    },
    ["F7"] = {
        input = KEY_F7,
        positionx = 700,
        positiony = 0,
        keysize = 100
    },
    ["F8"] = {
        input = KEY_F8,
        positionx = 800,
        positiony = 0,
        keysize = 100
    },
    ["F9"] = {
        input = KEY_F9,
        positionx = 900,
        positiony = 0,
        keysize = 100
    },
    ["F10"] = {
        input = KEY_F10,
        positionx = 1000,
        positiony = 0,
        keysize = 100
    },
    ["F11"] = {
        input = KEY_F11,
        positionx = 1100,
        positiony = 0,
        keysize = 100
    },
    ["F12"] = {
        input = KEY_F12,
        positionx = 1200,
        positiony = 0,
        keysize = 100
    },
    ["ScrLk"] = {
        input = KEY_SCROLLLOCK,
        positionx = 1650,
        positiony = 0,
        keysize = 100
    },
    ["Pause"] = {
        input = KEY_BREAK,
        positionx = 1750,
        positiony = 0,
        keysize = 100
    },
    ["`"] = {
        input = KEY_BACKQUOTE,
        positionx = 0,
        positiony = 100,
        keysize = 100
    },
    ["1"] = {
        input = KEY_1,
        positionx = 100,
        positiony = 100,
        keysize = 100
    },
    ["2"] = {
        input = KEY_2,
        positionx = 200,
        positiony = 100,
        keysize = 100
    },
    ["3"] = {
        input = KEY_3,
        positionx = 300,
        positiony = 100,
        keysize = 100
    },
    ["4"] = {
        input = KEY_4,
        positionx = 400,
        positiony = 100,
        keysize = 100
    },
    ["5"] = {
        input = KEY_5,
        positionx = 500,
        positiony = 100,
        keysize = 100
    },
    ["6"] = {
        input = KEY_6,
        positionx = 600,
        positiony = 100,
        keysize = 100
    },
    ["7"] = {
        input = KEY_7,
        positionx = 700,
        positiony = 100,
        keysize = 100
    },
    ["8"] = {
        input = KEY_8,
        positionx = 800,
        positiony = 100,
        keysize = 100
    },
    ["9"] = {
        input = KEY_9,
        positionx = 900,
        positiony = 100,
        keysize = 100
    },
    ["0"] = {
        input = KEY_0,
        positionx = 1000,
        positiony = 100,
        keysize = 100
    },
    ["-"] = {
        input = KEY_MINUS,
        positionx = 1100,
        positiony = 100,
        keysize = 100
    },
    ["="] = {
        input = KEY_EQUAL,
        positionx = 1200,
        positiony = 100,
        keysize = 100
    },
    ["Backspace"] = {
        input = KEY_BACKSPACE,
        positionx = 1300,
        positiony = 100,
        keysize = 200
    },
    ["Tab"] = {
        input = KEY_TAB,
        positionx = 0,
        positiony = 200,
        keysize = 150
    },
    ["Q"] = {
        input = KEY_Q,
        positionx = 150,
        positiony = 200,
        keysize = 100
    },
    ["W"] = {
        input = KEY_W,
        positionx = 250,
        positiony = 200,
        keysize = 100
    },
    ["E"] = {
        input = KEY_E,
        positionx = 350,
        positiony = 200,
        keysize = 100
    },
    ["R"] = {
        input = KEY_R,
        positionx = 450,
        positiony = 200,
        keysize = 100
    },
    ["T"] = {
        input = KEY_T,
        positionx = 550,
        positiony = 200,
        keysize = 100
    },
    ["Y"] = {
        input = KEY_Y,
        positionx = 650,
        positiony = 200,
        keysize = 100
    },
    ["U"] = {
        input = KEY_U,
        positionx = 750,
        positiony = 200,
        keysize = 100
    },
    ["I"] = {
        input = KEY_I,
        positionx = 850,
        positiony = 200,
        keysize = 100
    },
    ["O"] = {
        input = KEY_O,
        positionx = 950,
        positiony = 200,
        keysize = 100
    },
    ["P"] = {
        input = KEY_P,
        positionx = 1050,
        positiony = 200,
        keysize = 100
    },
    ["["] = {
        input = KEY_LBRACKET,
        positionx = 1150,
        positiony = 200,
        keysize = 100
    },
    ["]"] = {
        input = KEY_RBRACKET,
        positionx = 1250,
        positiony = 200,
        keysize = 100
    },
    ["\\"] = {
        input = KEY_BACKSLASH,
        positionx = 1350,
        positiony = 200,
        keysize = 150
    },
    ["Capslock"] = {
        input = KEY_CAPSLOCK,
        positionx = 0,
        positiony = 300,
        keysize = 175
    },
    ["A"] = {
        input = KEY_A,
        positionx = 175,
        positiony = 300,
        keysize = 100
    },
    ["S"] = {
        input = KEY_S,
        positionx = 275,
        positiony = 300,
        keysize = 100
    },
    ["D"] = {
        input = KEY_D,
        positionx = 375,
        positiony = 300,
        keysize = 100
    },
    ["F"] = {
        input = KEY_F,
        positionx = 475,
        positiony = 300,
        keysize = 100
    },
    ["G"] = {
        input = KEY_G,
        positionx = 575,
        positiony = 300,
        keysize = 100
    },
    ["H"] = {
        input = KEY_H,
        positionx = 675,
        positiony = 300,
        keysize = 100
    },
    ["J"] = {
        input = KEY_J,
        positionx = 775,
        positiony = 300,
        keysize = 100
    },
    ["K"] = {
        input = KEY_K,
        positionx = 875,
        positiony = 300,
        keysize = 100
    },
    ["L"] = {
        input = KEY_L,
        positionx = 975,
        positiony = 300,
        keysize = 100
    },
    [";"] = {
        input = KEY_SEMICOLON,
        positionx = 1075,
        positiony = 300,
        keysize = 100
    },
    ["'"] = {
        input = KEY_APOSTROPHE,
        positionx = 1175,
        positiony = 300,
        keysize = 100
    },
    ["Enter"] = {
        input = KEY_ENTER,
        positionx = 1275,
        positiony = 300,
        keysize = 225
    },
    ["LShift"] = {
        input = KEY_LSHIFT,
        positionx = 0,
        positiony = 400,
        keysize = 225
    },
    ["Z"] = {
        input = KEY_Z,
        positionx = 225,
        positiony = 400,
        keysize = 100
    },
    ["X"] = {
        input = KEY_X,
        positionx = 325,
        positiony = 400,
        keysize = 100
    },
    ["C"] = {
        input = KEY_C,
        positionx = 425,
        positiony = 400,
        keysize = 100
    },
    ["V"] = {
        input = KEY_V,
        positionx = 525,
        positiony = 400,
        keysize = 100
    },
    ["B"] = {
        input = KEY_B,
        positionx = 625,
        positiony = 400,
        keysize = 100
    },
    ["N"] = {
        input = KEY_N,
        positionx = 725,
        positiony = 400,
        keysize = 100
    },
    ["M"] = {
        input = KEY_M,
        positionx = 825,
        positiony = 400,
        keysize = 100
    },
    [","] = {
        input = KEY_COMMA,
        positionx = 925,
        positiony = 400,
        keysize = 100
    },
    ["."] = {
        input = KEY_PERIOD,
        positionx = 1025,
        positiony = 400,
        keysize = 100
    },
    ["/"] = {
        input = KEY_SLASH,
        positionx = 1125,
        positiony = 400,
        keysize = 100
    },
    ["RShift"] = {
        input = KEY_RSHIFT,
        positionx = 1225,
        positiony = 400,
        keysize = 275
    },
    ["LCtrl"] = {
        input = KEY_LCONTROL,
        positionx = 0,
        positiony = 500,
        keysize = 125
    },
    ["LWin"] = {
        input = KEY_LWIN,
        positionx = 125,
        positiony = 500,
        keysize = 125
    },
    ["LAlt"] = {
        input = KEY_LALT,
        positionx = 250,
        positiony = 500,
        keysize = 125
    },
    ["Space"] = {
        input = KEY_SPACE,
        positionx = 375,
        positiony = 500,
        keysize = 625
    },
    ["RAlt"] = {
        input = KEY_RALT,
        positionx = 1000,
        positiony = 500,
        keysize = 125
    },
    ["RWin"] = {
        input = KEY_RWIN,
        positionx = 1125,
        positiony = 500,
        keysize = 125
    },
    ["Menu"] = {
        input = KEY_APP,
        positionx = 1250,
        positiony = 500,
        keysize = 125
    },
    ["RCtrl"] = {
        input = KEY_RCONTROL,
        positionx = 1375,
        positiony = 500,
        keysize = 125
    },
    ["Ins"] = {
        input = KEY_INSERT,
        positionx = 1550,
        positiony = 100,
        keysize = 100
    },
    ["Home"] = {
        input = KEY_HOME,
        positionx = 1650,
        positiony = 100,
        keysize = 100
    },
    ["PgUp"] = {
        input = KEY_PAGEUP,
        positionx = 1750,
        positiony = 100,
        keysize = 100
    },
    ["Del"] = {
        input = KEY_DELETE,
        positionx = 1550,
        positiony = 200,
        keysize = 100
    },
    ["End"] = {
        input = KEY_END,
        positionx = 1650,
        positiony = 200,
        keysize = 100
    },
    ["PgDn"] = {
        input = KEY_PAGEDOWN,
        positionx = 1750,
        positiony = 200,
        keysize = 100
    },
    ["Up"] = {
        input = KEY_UP,
        positionx = 1650,
        positiony = 400,
        keysize = 100
    },
    ["Left"] = {
        input = KEY_LEFT,
        positionx = 1550,
        positiony = 500,
        keysize = 100
    },
    ["Down"] = {
        input = KEY_DOWN,
        positionx = 1650,
        positiony = 500,
        keysize = 100
    },
    ["Right"] = {
        input = KEY_RIGHT,
        positionx = 1750,
        positiony = 500,
        keysize = 100
    },
    ["NumLk"] = {
        input = KEY_NUMLOCK,
        positionx = 1950,
        positiony = 100,
        keysize = 100
    },
    ["Num/"] = {
        input = KEY_PAD_DIVIDE,
        positionx = 2050,
        positiony = 100,
        keysize = 100
    },
    ["Num*"] = {
        input = KEY_PAD_MULTIPLY,
        positionx = 2150,
        positiony = 100,
        keysize = 100
    },
    ["Num-"] = {
        input = KEY_PAD_MINUS,
        positionx = 2250,
        positiony = 100,
        keysize = 100
    },
    ["Num7"] = {
        input = KEY_PAD_7,
        positionx = 1950,
        positiony = 200,
        keysize = 100
    },
    ["Num8"] = {
        input = KEY_PAD_8,
        positionx = 2050,
        positiony = 200,
        keysize = 100
    },
    ["Num9"] = {
        input = KEY_PAD_9,
        positionx = 2150,
        positiony = 200,
        keysize = 100
    },
    ["Num+"] = {
        input = KEY_PAD_PLUS,
        positionx = 2250,
        positiony = 200,
        keysize = 100
    },
    ["Num4"] = {
        input = KEY_PAD_4,
        positionx = 1950,
        positiony = 300,
        keysize = 100
    },
    ["Num5"] = {
        input = KEY_PAD_5,
        positionx = 2050,
        positiony = 300,
        keysize = 100
    },
    ["Num6"] = {
        input = KEY_PAD_6,
        positionx = 2150,
        positiony = 300,
        keysize = 100
    },
    ["Num1"] = {
        input = KEY_PAD_1,
        positionx = 1950,
        positiony = 400,
        keysize = 100
    },
    ["Num2"] = {
        input = KEY_PAD_2,
        positionx = 2050,
        positiony = 400,
        keysize = 100
    },
    ["Num3"] = {
        input = KEY_PAD_3,
        positionx = 2150,
        positiony = 400,
        keysize = 100
    },
    ["NEnter"] = {
        input = KEY_PAD_ENTER,
        positionx = 2250,
        positiony = 400,
        keysize = 100
    },
    ["Num0"] = {
        input = KEY_PAD_0,
        positionx = 1950,
        positiony = 500,
        keysize = 200
    },
    ["Num."] = {
        input = KEY_PAD_DECIMAL,
        positionx = 2150,
        positiony = 500,
        keysize = 100
    },
}
 
local MouseInputs = {
    ["ScU"] = {
        input = MOUSE_WHEEL_UP,
        positionx = 1750,
        positiony = 200,
        keysize = 100
    },
    ["LMB"] = {
        input = MOUSE_LEFT,
        positionx = 1650,
        positiony = 300,
        keysize = 100
    },
    ["MMB"] = {
        input = MOUSE_MIDDLE,
        positionx = 1750,
        positiony = 300,
        keysize = 100
    },
    ["RMB"] = {
        input = MOUSE_RIGHT,
        positionx = 1850,
        positiony = 300,
        keysize = 100
    },
    ["ScD"] = {
        input = MOUSE_WHEEL_DOWN,
        positionx = 1750,
        positiony = 400,
        keysize = 100
    },
    ["SMB"] = {
        input = MOUSE_4,
        positionx = 1750,
        positiony = 500,
        keysize = 100
    },
}

local Black = Color(0, 0, 0)
local White = Color(255, 255, 255)
local function drawInputs()
    if not IsValid(specEnt) then return end
    if not specEnt:IsPlayer() or specEnt:IsBot() then return end
    local OriginX = ScreenScale(fspectate_showinputs_positionxValue)
    local OriginY = ScreenScaleH(fspectate_showinputs_positionyValue)
    local MouseOffsetX = ScreenScale(250)
    local MouseOffsetY = 0
    for key, data in pairs(KeyboardInputs) do
        local chunk = math.floor(data.input / 32) + 1
        if not specEnt["pressedKeys" .. chunk] then continue end
        local IsKeyDown = bit.band(specEnt["pressedKeys" .. chunk], bit.lshift(1, data.input % 32)) ~= 0
        surface.SetDrawColor(IsKeyDown and White or Black)
        surface.DrawRect(ScreenScale(OriginX + (data.positionx * fspectate_showinputs_percentsizeValue)), ScreenScale(OriginY + (data.positiony * fspectate_showinputs_percentsizeValue)), ScreenScale(data.keysize * fspectate_showinputs_percentsizeValue), ScreenScale(100 * fspectate_showinputs_percentsizeValue))
        surface.SetDrawColor((IsKeyDown and Black) or White)
        surface.DrawOutlinedRect(ScreenScale(OriginX + (data.positionx * fspectate_showinputs_percentsizeValue)), ScreenScale(OriginY + (data.positiony * fspectate_showinputs_percentsizeValue)), ScreenScale(data.keysize * fspectate_showinputs_percentsizeValue), ScreenScale(100 * fspectate_showinputs_percentsizeValue, 1))
        surface.SetFont("KeyboardFont")
        local textHeight = select(2, surface.GetTextSize(key))
        draw.DrawText(key, "KeyboardFont", ScreenScale(OriginX + (data.positionx * fspectate_showinputs_percentsizeValue) + (data.keysize * fspectate_showinputs_percentsizeValue / 2)), ScreenScale(OriginY + (data.positiony * fspectate_showinputs_percentsizeValue) + (50 * fspectate_showinputs_percentsizeValue)) - textHeight / 2, (IsKeyDown and Black) or White, TEXT_ALIGN_CENTER)
    end

    for button, data in pairs(MouseInputs) do
        local chunk = math.floor(data.input / 32) + 1
        if not specEnt["pressedMouseButtons" .. chunk] then continue end
        local IsKeyDown = bit.band(specEnt["pressedMouseButtons" .. chunk], bit.lshift(1, data.input % 32)) ~= 0
        surface.SetDrawColor((IsKeyDown and White) or Black)
        surface.DrawRect(ScreenScale(OriginX + MouseOffsetX * fspectate_showinputs_percentsizeValue + (data.positionx * fspectate_showinputs_percentsizeValue)), ScreenScale(OriginY + MouseOffsetY * fspectate_showinputs_percentsizeValue + (data.positiony * fspectate_showinputs_percentsizeValue)), ScreenScale(data.keysize * fspectate_showinputs_percentsizeValue), ScreenScale(100 * fspectate_showinputs_percentsizeValue))
        surface.SetDrawColor((IsKeyDown and Black) or White)
        surface.DrawOutlinedRect(ScreenScale(OriginX + MouseOffsetX * fspectate_showinputs_percentsizeValue + (data.positionx * fspectate_showinputs_percentsizeValue)), ScreenScale(OriginY + MouseOffsetY * fspectate_showinputs_percentsizeValue + (data.positiony * fspectate_showinputs_percentsizeValue)), ScreenScale(data.keysize * fspectate_showinputs_percentsizeValue), ScreenScale(100 * fspectate_showinputs_percentsizeValue, 1))
        surface.SetFont("KeyboardFont")
        local _, Height = surface.GetTextSize(button)
        draw.DrawText(button, "KeyboardFont", ScreenScale(OriginX + MouseOffsetX * fspectate_showinputs_percentsizeValue + (data.positionx * fspectate_showinputs_percentsizeValue) + (data.keysize * fspectate_showinputs_percentsizeValue / 2)), ScreenScale(OriginY + MouseOffsetY * fspectate_showinputs_percentsizeValue + (data.positiony * fspectate_showinputs_percentsizeValue) + (50 * fspectate_showinputs_percentsizeValue)) - (Height / 2), (IsKeyDown and Black) or White, TEXT_ALIGN_CENTER)
    end
end


/*---------------------------------------------------------------------------
Draw help on the screen
---------------------------------------------------------------------------*/
local uiForeground, uiBackground = Color(240, 240, 255, 255), Color(20, 20, 20, 150)
local red = Color(255, 0, 0, 255)
local function drawHelp()
    local scrHalfH = math.floor(ScrH() / 2)
    draw.WordBox(2, 10, scrHalfH, "Left click: (Un)select player to spectate", "UiBold", uiBackground, uiForeground)
    draw.WordBox(2, 10, scrHalfH + 20, isRoaming and "Right click: quickly move forwards" or "Right click: toggle thirdperson", "UiBold", uiBackground, uiForeground)
    draw.WordBox(2, 10, scrHalfH + 40, "Jump: Stop spectating", "UiBold", uiBackground, uiForeground)
    draw.WordBox(2, 10, scrHalfH + 60, "Reload: Stop spectating and teleport", "UiBold", uiBackground, uiForeground)

    if FAdmin then
        draw.WordBox(2, 10, scrHalfH + 80, "Opening FAdmin's menu while spectating a player", "UiBold", uiBackground, uiForeground)
        draw.WordBox(2, 10, scrHalfH + 100, "\twill open their page!", "UiBold", uiBackground, uiForeground)
    end


    local target = findNearestObject()
    local pls = player.GetAll()
    for i = 1, #pls do
        local ply = pls[i]
        if not IsValid(ply) then continue end
        if not isRoaming and ply == specEnt then continue end

        local pos = ply:GetShootPos():ToScreen()
        if not pos.visible then continue end

        local x, y = pos.x, pos.y

        draw.RoundedBox(2, x, y - 6, 12, 12, team.GetColor(ply:Team()))
        draw.WordBox(2, x, y - 66, ply:Nick(), "UiBold", uiBackground, uiForeground)
        draw.WordBox(2, x, y - 46, "Health: " .. ply:Health(), "UiBold", uiBackground, uiForeground)
        draw.WordBox(2, x, y - 26, ply:GetUserGroup(), "UiBold", uiBackground, uiForeground)
    end

    if not isRoaming then return end

    if not IsValid(target) then return end

    local center = target:LocalToWorld(target:OBBCenter()):ToScreen()

    draw.RoundedBox(4, center.x, center.y, 16, 16, red)
    draw.WordBox(2, center.x + 16, center.y, "Left click to spectate!", "UiBold", uiBackground, uiForeground)
end

/*---------------------------------------------------------------------------
Start roaming free, rather than spectating a given player
---------------------------------------------------------------------------*/
startFreeRoam = function()
    roamPos = isSpectating and roamPos or LocalPlayer():GetShootPos()

    if IsValid(specEnt) then
        if specEnt:IsPlayer() then
            roamPos = thirdperson and getThirdPersonPos(specEnt) or specEnt:GetShootPos()
        end
        specEnt:SetNoDraw(false)
    end

    specEnt = nil
    isRoaming = true
    keysDown = {}
end

/*---------------------------------------------------------------------------
specEnt
Spectate a player
---------------------------------------------------------------------------*/
local canExitSpectate = true
local function startSpectate(um)
    canExitSpectate = net.ReadBool()
    isRoaming = net.ReadBool()
    specEnt = net.ReadEntity()
    specEnt = IsValid(specEnt) and specEnt or nil
    if isRoaming then startFreeRoam() end
    isSpectating = true
    keysDown = {}
    hook.Add("CalcView", "FSpectate", specCalcView)
    hook.Add("PlayerBindPress", "FSpectate", specBinds)
    hook.Add("ShouldDrawLocalPlayer", "FSpectate", function() return isRoaming or thirdperson end)
    hook.Add("Think", "FSpectate", specThink)
    hook.Add("HUDPaint", "FSpectate", drawHelp)
    hook.Add("HUDPaint", "FspectateDrawInputs", drawInputs)
    hook.Add("FAdmin_ShowFAdminMenu", "FSpectate", fadminmenushow)
    hook.Add("RenderScreenspaceEffects", "FSpectate", lookingLines)
    timer.Create("FSpectatePosUpdate", 0.5, 0, function()
        if not isRoaming then return end
        RunConsoleCommand("_FSpectatePosUpdate", roamPos.x, roamPos.y, roamPos.z)
    end)
end

net.Receive("FSpectate", startSpectate)

/*---------------------------------------------------------------------------
stopSpectating
Stop spectating a player
---------------------------------------------------------------------------*/
stopSpectating = function(forced)
    if canExitSpectate ~= true and forced ~= true then
        chat.AddText("Can't exit spectate right now")
        return
    end

    hook.Remove("CalcView", "FSpectate")
    hook.Remove("PlayerBindPress", "FSpectate")
    hook.Remove("ShouldDrawLocalPlayer", "FSpectate")
    hook.Remove("Think", "FSpectate")
    hook.Remove("HUDPaint", "FSpectate")
    hook.Remove("HUDPaint", "FspectateDrawInputs")
    hook.Remove("FAdmin_ShowFAdminMenu", "FSpectate")
    hook.Remove("RenderScreenspaceEffects", "FSpectate")
    timer.Remove("FSpectatePosUpdate")
    if IsValid(specEnt) then
        specEnt:SetNoDraw(false)
    end
    RunConsoleCommand("FSpectate_StopSpectating")
    isSpectating = false
end

net.Receive("FSpectateForceUnspectate", function() stopSpectating(true) end)
/*---------------------------------------------------------------------------
Recieve inputs of other players from server
---------------------------------------------------------------------------*/
net.Receive("FSpectateNetworkPlayerInputs", function()
    local ply = net.ReadPlayer()
    local numKeysPressed = net.ReadUInt(7)
    local keyChunksAmount = math.floor(KEY_LAST / 32) + 1 -- uint32 isnt precise enough for a large bitflag, KEY_LAST (107) has to be made into 4 bitflags 
    for chunk = 1, keyChunksAmount do
        ply["pressedKeys" .. chunk] = 0
    end

    --ply.pressedKeysBitFlag = 0
    for i = 1, numKeysPressed do
        local key = net.ReadUInt(8)
        --print(key)
        local chunk = math.floor(key / 32) + 1
        ply["pressedKeys" .. chunk] = bit.bor(ply["pressedKeys" .. chunk], bit.lshift(1, key % 32))
    end

    local numMouseButtonsPressed = net.ReadUInt(3)
    local mouseChunksAmount = math.floor(MOUSE_LAST - MOUSE_FIRST / 32) + 1 -- MOUSE_LAST (113) - MOUSE_FIRST (107) can be stored in 1 uint32 chunk
    for chunk = 1, mouseChunksAmount do
        ply["pressedMouseButtons" .. chunk] = 0
    end

    for i = 1, numMouseButtonsPressed do
        local mouseButton = net.ReadUInt(3)
        local shiftedInt = mouseButton + MOUSE_FIRST -- we shifted down by MOUSE_FIRST write to server cheaper, now shift it back to be correct 
        local chunk = math.floor(shiftedInt / 32) + 1
        ply["pressedMouseButtons" .. chunk] = bit.bor(ply["pressedMouseButtons" .. chunk], bit.lshift(1, shiftedInt % 32))
    end
end)

/*---------------------------------------------------------------------------
Send inputs of localplayer to server
---------------------------------------------------------------------------*/
hook.Add("StartCommand", "FSpectateTrackInputs", function(ply, ucmd)
    if isSpectating == true and LocalPlayer:Alive() == false then return end
    net.Start("FSpectateSendInputs")
    local numKeysPressed = 0
    for i = KEY_FIRST, KEY_LAST do
        if input.IsButtonDown(i) then numKeysPressed = numKeysPressed + 1 end
    end

    net.WriteUInt(numKeysPressed, 7) -- KEY_FIRST (0) - KEY_LAST (106), 7 bits is enough
    local numMouseButtonsPressed = 0
    for i = MOUSE_FIRST, MOUSE_LAST do
        if input.IsButtonDown(i) then numMouseButtonsPressed = numMouseButtonsPressed + 1 end
    end

    net.WriteUInt(numMouseButtonsPressed, 3) -- MOUSE_FIRST (107) - KEY_LAST (113), 3 bits is enough
    for pressedKey = KEY_FIRST, KEY_LAST do -- redo the for loops to send 8 bit uints of whether or not key is down
        if input.IsButtonDown(pressedKey) then net.WriteUInt(pressedKey, 8) end
    end

    for pressedMouseButton = MOUSE_FIRST, MOUSE_LAST do
        if input.IsButtonDown(pressedMouseButton) then
            local cheapInt = pressedMouseButton - MOUSE_FIRST -- shift down so that it costs less bits, then shift up on the server later
            net.WriteUInt(cheapInt, 3)
        end
    end

    net.SendToServer()
end)
