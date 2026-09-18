local ADDON_NAME = ...

local addon = CreateFrame("Frame")
local groups = {}
local initialized = false
local paused = false
local editModeOpen = false
local hideTimer = nil
local pauseTimer = nil
local xpHideTimer = nil
local xpRevealActive = false
local lastXP = nil
local heartbeat = 0
local rescanTimer = 0
local gamepadPollTimer = 0
local gamepadModifierActive = false
local gamepadButtonIndexes = {}
local gamepadButtonIndexesDirty = true

local GAMEPAD_REVEAL_BUTTONS = {
    "PADLSHOULDER",
    "PADLTRIGGER",
    "PADRSHOULDER",
    "PADRTRIGGER",
}

-- Forever is its own product/flavor, but the 1.60 client uses the modern UI
-- architecture. Keep the detection interface-based rather than assuming that
-- WOW_PROJECT_MAINLINE means "modern"; Forever currently reports Interface 16001.
local CLIENT_VERSION, CLIENT_BUILD, CLIENT_BUILD_DATE, CLIENT_INTERFACE = GetBuildInfo()
local CLIENT_INTERFACE_NUMBER = tonumber(CLIENT_INTERFACE) or 0
local IS_FOREVER = CLIENT_INTERFACE_NUMBER >= 16000 and CLIENT_INTERFACE_NUMBER < 17000

local DEFAULTS = {
    enabled = true,
    explorationAlpha = 0.0,
    fadeInDuration = 0.20,
    fadeOutDuration = 0.50,
    fadeOutDelay = 1.25,

    -- XP is contextual rather than part of combat mode: reveal it briefly
    -- when the player actually gains XP, then let it fade away again.
    xpRevealDuration = 4.0,

    -- v0.2: Swallow mouse clicks over fully-faded managed controls without
    -- modifying Blizzard's protected action buttons themselves.
    interactionBlockers = true,

    -- Per-group exploration opacity overrides. Groups not listed here use
    -- explorationAlpha above. Chat intentionally remains faintly readable.
    explorationAlphas = {
        chat = 0.12,
    },

    groups = {
        actionBars = true,
        actionBarArt = true,
        playerFrame = true,
        microMenu = true,
        cooldowns = true,
        swingTimer = true,
        controllerUI = true,
        chat = true,
        experienceBar = true,
        performanceBar = true,

        -- Available but deliberately OFF by default.
        -- These are things you may actively use outside combat.
        petActionBar = false,
        stanceBar = false,
        petFrame = false,
    },
}

-- Each entry represents one semantic UI element. The first existing candidate
-- is used, so the same code can tolerate Classic/modern frame-name differences.
-- Candidate names may be global names or dotted paths such as
-- MainActionBar.EndCaps.LeftEndCap.
local GROUP_DEFINITIONS = {
    actionBars = {
        label = "Action bars",
        blockMouse = true,
        elements = {
            { "MainActionBar", "MainMenuBar" },
            { "MultiBarBottomLeft" },
            { "MultiBarBottomRight" },
            { "MultiBarRight" },
            { "MultiBarLeft" },
            { "MultiBar5" },
            { "MultiBar6" },
            { "MultiBar7" },
            { "ActionBarUpButton" },
            { "ActionBarDownButton" },
        },
    },
    actionBarArt = {
        label = "Action-bar artwork",
        blockMouse = false,
        elements = {
            -- Classic-era main bar artwork. Immersive handled these regions
            -- separately from MainMenuBar, which is why the stone background
            -- could remain visible after the buttons themselves were faded.
            { "MainMenuBarTexture0" },
            { "MainMenuBarTexture1" },
            { "MainMenuBarTexture2" },
            { "MainMenuBarTexture3" },
            { "MainMenuBarTextureExtender" },
            { "MainMenuBarArtFrameBackground" },

            -- Modern / Forever (1.60) action-bar hierarchy. BorderArt and the
            -- page controls are child regions rather than old global frames.
            { "MainActionBar.BorderArt" },
            { "MainActionBar.EndCaps" },
            { "MainActionBar.ActionBarPageNumber" },

            -- Classic fallbacks / individual modern end-cap textures.
            { "MainMenuBarLeftEndCap", "MainActionBar.EndCaps.LeftEndCap" },
            { "MainMenuBarRightEndCap", "MainActionBar.EndCaps.RightEndCap" },
            { "MainMenuBarPageNumber" },
        },
    },
    playerFrame = {
        label = "Player frame",
        blockMouse = true,
        elements = {
            { "PlayerFrame" },
        },
    },
    microMenu = {
        label = "Micro menu and bags",
        blockMouse = true,
        elements = {
            { "MicroMenu", "MicroMenuContainer", "MicroButtonAndBagsBar" },
            { "BagsBar", "MicroButtonAndBagsBar" },
            -- Classic clients expose the individual buttons directly.
            { "CharacterMicroButton" },
            { "SpellbookMicroButton" },
            { "TalentMicroButton" },
            { "AchievementMicroButton" },
            { "QuestLogMicroButton" },
            { "SocialsMicroButton" },
            { "PVPMicroButton" },
            { "LFGMicroButton" },
            { "WorldMapMicroButton" },
            { "HelpMicroButton" },
            { "MainMenuMicroButton" },
            { "KeyRingButton" },
            { "MainMenuBarBackpackButton" },
            { "CharacterBag0Slot" },
            { "CharacterBag1Slot" },
            { "CharacterBag2Slot" },
            { "CharacterBag3Slot" },
        },
    },
    cooldowns = {
        label = "Cooldown viewers",
        blockMouse = false,
        elements = {
            { "EssentialCooldownViewer" },
            { "UtilityCooldownViewer" },
            { "BuffIconCooldownViewer" },
            { "BuffBarCooldownViewer" },
            { "GroupBuffCooldownViewer" },
        },
    },
    swingTimer = {
        label = "Swing timer",
        blockMouse = false,
        elements = {
            -- Forever beta: Blizzard_SwingTimer creates this top-level frame.
            -- Fading the parent also fades its StatusBar, Background, Border,
            -- and TypeLabelShadow children shown by /fstack.
            { "SwingTimerMainHandFrame" },

            -- Defensive fallback for a possible off-hand timer on dual-wield
            -- characters. This is harmless when the frame does not exist.
            { "SwingTimerOffHandFrame", "SwingTimerOffhandFrame" },
        },
    },
    controllerUI = {
        label = "Controller action UI",
        blockMouse = false,
        mode = "gamepadModifier",
        elements = {
            -- Forever beta: the large controller action overlay is rooted here.
            -- Fading the parent keeps all page units, icons, labels, and helper
            -- artwork in sync without touching its protected child buttons.
            { "GamepadMainActionBarFrame" },
        },
    },
    chat = {
        label = "Chat",
        blockMouse = false,
        elements = {
            { "ChatFrame1" }, { "ChatFrame1Tab" }, { "ChatFrame1ButtonFrame" },
            { "ChatFrame2" }, { "ChatFrame2Tab" }, { "ChatFrame2ButtonFrame" },
            { "ChatFrame3" }, { "ChatFrame3Tab" }, { "ChatFrame3ButtonFrame" },
            { "ChatFrame4" }, { "ChatFrame4Tab" }, { "ChatFrame4ButtonFrame" },
            { "ChatFrame5" }, { "ChatFrame5Tab" }, { "ChatFrame5ButtonFrame" },
            { "ChatFrame6" }, { "ChatFrame6Tab" }, { "ChatFrame6ButtonFrame" },
            { "ChatFrame7" }, { "ChatFrame7Tab" }, { "ChatFrame7ButtonFrame" },
            { "ChatFrame8" }, { "ChatFrame8Tab" }, { "ChatFrame8ButtonFrame" },
            { "ChatFrame9" }, { "ChatFrame9Tab" }, { "ChatFrame9ButtonFrame" },
            { "ChatFrame10" }, { "ChatFrame10Tab" }, { "ChatFrame10ButtonFrame" },
            { "ChatFrameMenuButton" },
            { "ChatFrameChannelButton" },
            { "QuickJoinToastButton" },
        },
    },
    petActionBar = {
        label = "Pet action bar",
        blockMouse = true,
        elements = {
            { "PetActionBar", "PetActionBarFrame" },
        },
    },
    stanceBar = {
        label = "Stance bar",
        blockMouse = true,
        elements = {
            { "StanceBar", "StanceBarFrame" },
        },
    },
    experienceBar = {
        label = "Experience bar",
        blockMouse = true,
        mode = "experience",
        elements = {
            -- Classic / Forever uses MainMenuExpBar. The later names are
            -- conservative fallbacks for clients using newer status-bar code.
            { "MainMenuExpBar", "MainStatusTrackingBarContainer", "StatusTrackingBarManager" },
        },
    },
    performanceBar = {
        label = "Performance / latency bar",
        blockMouse = true,
        mode = "alwaysHidden",
        elements = {
            -- Confirmed by /fstack on the Forever client. Keep the parent,
            -- fill bar, and its mouse-enabled button together.
            { "MainMenuBarPerformanceBarFrame" },
            { "MainMenuBarPerformanceBar" },
            { "MainMenuBarPerformanceBarFrameButton" },
        },
    },
    petFrame = {
        label = "Pet unit frame",
        blockMouse = true,
        elements = {
            { "PetFrame" },
        },
    },
}

local GROUP_ORDER = {
    "actionBars",
    "actionBarArt",
    "playerFrame",
    "microMenu",
    "cooldowns",
    "swingTimer",
    "controllerUI",
    "chat",
    "experienceBar",
    "performanceBar",
    "petActionBar",
    "stanceBar",
    "petFrame",
}

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cffd7a84bImmersionFade:|r " .. tostring(message))
end

local function DeepCopyDefaults(source, target)
    target = type(target) == "table" and target or {}
    for key, value in pairs(source) do
        if type(value) == "table" then
            target[key] = DeepCopyDefaults(value, target[key])
        elseif target[key] == nil then
            target[key] = value
        end
    end
    return target
end

local function Clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

local function IsSecretValue(value)
    if type(issecretvalue) ~= "function" then
        return false
    end
    local ok, secret = pcall(issecretvalue, value)
    return ok and secret and true or false
end

local function SafeTruthyCall(func, ...)
    if type(func) ~= "function" then
        return false
    end

    local ok, value = pcall(func, ...)
    if not ok or IsSecretValue(value) then
        return false
    end
    return value and true or false
end

local function RebuildGamePadButtonIndexes()
    gamepadButtonIndexes = {}
    gamepadButtonIndexesDirty = false

    if not C_GamePad or type(C_GamePad.ButtonBindingToIndex) ~= "function" then
        return
    end

    for _, bindingName in ipairs(GAMEPAD_REVEAL_BUTTONS) do
        local ok, buttonIndex = pcall(C_GamePad.ButtonBindingToIndex, bindingName)
        if ok and type(buttonIndex) == "number" and not IsSecretValue(buttonIndex) then
            gamepadButtonIndexes[bindingName] = buttonIndex
        end
    end
end

local function IsGamePadBindingDown(bindingName)
    -- Direct input-state polling is the most reliable path on the modern client.
    -- In particular, Forever can route PADRTRIGGER through cursor-click handling,
    -- which may make it disappear from the combined mapped-state button table.
    if type(IsKeyDown) == "function" then
        local ok, down = pcall(IsKeyDown, bindingName)
        if ok and not IsSecretValue(down) and down then
            return true
        end
    end

    return false
end

local function IsMappedGamePadButtonDown(state, buttonIndex)
    if type(state) ~= "table" or IsSecretValue(state) then
        return false
    end

    local buttons = state.buttons
    if type(buttons) ~= "table" or IsSecretValue(buttons) then
        return false
    end

    local okButton, isDown = pcall(function()
        return buttons[buttonIndex]
    end)
    return okButton and not IsSecretValue(isDown) and isDown and true or false
end

local function GetMappedGamePadStates()
    local states = {}
    local seenDeviceIDs = {}

    if not C_GamePad or type(C_GamePad.GetDeviceMappedState) ~= "function" then
        return states
    end

    -- Ask the client for the default/combined state first, preserving the path
    -- that already worked for LB/LT/RB in v0.6.0.
    local okDefault, defaultState = pcall(C_GamePad.GetDeviceMappedState)
    if okDefault and type(defaultState) == "table" and not IsSecretValue(defaultState) then
        table.insert(states, defaultState)
    end

    -- Forever may route a trigger through cursor handling on the active physical
    -- device even when the combined virtual device does not expose that button.
    if type(C_GamePad.GetActiveDeviceID) == "function" then
        local okID, deviceID = pcall(C_GamePad.GetActiveDeviceID)
        if okID and type(deviceID) == "number" and not IsSecretValue(deviceID) then
            seenDeviceIDs[deviceID] = true
            local okState, state = pcall(C_GamePad.GetDeviceMappedState, deviceID)
            if okState and type(state) == "table" and not IsSecretValue(state) then
                table.insert(states, state)
            end
        end
    end

    if type(C_GamePad.GetCombinedDeviceID) == "function" then
        local okID, deviceID = pcall(C_GamePad.GetCombinedDeviceID)
        if okID and type(deviceID) == "number" and not IsSecretValue(deviceID) and not seenDeviceIDs[deviceID] then
            local okState, state = pcall(C_GamePad.GetDeviceMappedState, deviceID)
            if okState and type(state) == "table" and not IsSecretValue(state) then
                table.insert(states, state)
            end
        end
    end

    return states
end

local function IsGamePadModifierHeld()
    if not C_GamePad then
        return false
    end

    if type(C_GamePad.IsEnabled) == "function" then
        local okEnabled, enabled = pcall(C_GamePad.IsEnabled)
        if okEnabled and not IsSecretValue(enabled) and not enabled then
            return false
        end
    end

    -- Prefer a direct key-state query. This catches PADRTRIGGER on Forever even
    -- when it is consumed by GamePadCursorLeftClick and absent from the combined
    -- mapped-state table.
    for _, bindingName in ipairs(GAMEPAD_REVEAL_BUTTONS) do
        if IsGamePadBindingDown(bindingName) then
            return true
        end
    end

    if gamepadButtonIndexesDirty then
        RebuildGamePadButtonIndexes()
    end

    local states = GetMappedGamePadStates()
    for _, bindingName in ipairs(GAMEPAD_REVEAL_BUTTONS) do
        local buttonIndex = gamepadButtonIndexes[bindingName]
        if type(buttonIndex) == "number" then
            for _, state in ipairs(states) do
                if IsMappedGamePadButtonDown(state, buttonIndex) then
                    return true
                end
            end
        end
    end

    return false
end

local function ResolveGlobalPath(path)
    if type(path) ~= "string" or path == "" then
        return nil
    end

    local first, rest = path:match("^([^.]+)%.?(.*)$")
    local value = first and _G[first] or nil
    if not value then
        return nil
    end

    if rest and rest ~= "" then
        for part in rest:gmatch("[^.]+") do
            local current = value
            local ok, nextValue = pcall(function()
                return current[part]
            end)
            if not ok or nextValue == nil then
                return nil
            end
            value = nextValue
        end
    end

    return value
end

local function IsRegionAccessible(region)
    if not region or type(region.SetAlpha) ~= "function" then
        return false
    end

    if type(region.IsForbidden) == "function" then
        local ok, forbidden = pcall(region.IsForbidden, region)
        if ok and forbidden then
            return false
        end
    end

    -- 12.1+ exposes this context-access check. Older clients simply do not.
    if type(region.CanBeAccessedInContext) == "function" then
        local ok, accessible = pcall(region.CanBeAccessedInContext, region)
        if ok and accessible == false then
            return false
        end
    end

    return true
end

local function SafeSetAlpha(region, alpha)
    if not IsRegionAccessible(region) then
        return false
    end
    return pcall(region.SetAlpha, region, Clamp(alpha, 0, 1))
end

local function GetRegionName(region, fallback)
    if region and type(region.GetName) == "function" then
        local ok, name = pcall(region.GetName, region)
        if ok and name then
            return name
        end
    end
    return fallback or "<unnamed region>"
end

local function IsInCombatLockdown()
    if type(InCombatLockdown) ~= "function" then
        return false
    end
    local ok, value = pcall(InCombatLockdown)
    return ok and value and true or false
end

local function GetExplorationAlpha(key)
    if ImmersionFadeDB
        and type(ImmersionFadeDB.explorationAlphas) == "table"
        and ImmersionFadeDB.explorationAlphas[key] ~= nil then
        return Clamp(tonumber(ImmersionFadeDB.explorationAlphas[key]) or 0, 0, 1)
    end
    return Clamp((ImmersionFadeDB and ImmersionFadeDB.explorationAlpha) or 0, 0, 1)
end

local function CancelHideTimer()
    if hideTimer then
        hideTimer:Cancel()
        hideTimer = nil
    end
end

local function CancelPauseTimer()
    if pauseTimer then
        pauseTimer:Cancel()
        pauseTimer = nil
    end
end

local function CancelXPHideTimer()
    if xpHideTimer then
        xpHideTimer:Cancel()
        xpHideTimer = nil
    end
end

local function BuildGroups()
    for key, definition in pairs(GROUP_DEFINITIONS) do
        groups[key] = groups[key] or {
            key = key,
            label = definition.label,
            blockMouse = definition.blockMouse and true or false,
            mode = definition.mode,
            frames = {},
            frameSet = {},
            frameNames = {},
            blockers = {},
            currentAlpha = 1,
            targetAlpha = 1,
            startAlpha = 1,
            startedAt = 0,
            duration = 0,
            animating = false,
        }
    end
end

local function CreateInteractionBlocker(group, frame)
    if not group.blockMouse or group.blockers[frame] or IsInCombatLockdown() then
        return
    end

    -- Only actual Frames need mouse shielding. Textures/font strings have no
    -- independent mouse interaction and may not expose frame-level APIs.
    if type(frame.GetFrameStrata) ~= "function"
        or type(frame.GetFrameLevel) ~= "function"
        or type(frame.IsShown) ~= "function" then
        return
    end

    local blocker = CreateFrame("Frame", nil, UIParent)
    blocker:SetAllPoints(frame)
    blocker:EnableMouse(true)

    if type(blocker.EnableMouseWheel) == "function" then
        blocker:EnableMouseWheel(true)
    end
    if type(blocker.SetPropagateMouseClicks) == "function" then
        pcall(blocker.SetPropagateMouseClicks, blocker, false)
    end
    if type(blocker.SetPropagateMouseMotion) == "function" then
        pcall(blocker.SetPropagateMouseMotion, blocker, false)
    end

    -- Empty handlers intentionally swallow the event. The blocker is our own
    -- unprotected frame; Blizzard action buttons themselves remain untouched.
    blocker:SetScript("OnMouseDown", function() end)
    blocker:SetScript("OnMouseUp", function() end)
    blocker:SetScript("OnMouseWheel", function() end)

    local okStrata, strata = pcall(frame.GetFrameStrata, frame)
    if okStrata and strata then
        pcall(blocker.SetFrameStrata, blocker, strata)
    end

    local okLevel, level = pcall(frame.GetFrameLevel, frame)
    if okLevel and type(level) == "number" then
        pcall(blocker.SetFrameLevel, blocker, level + 100)
    end

    blocker:Hide()
    group.blockers[frame] = blocker
end

local function EnsureInteractionBlockers()
    if IsInCombatLockdown() then
        return
    end

    for _, key in ipairs(GROUP_ORDER) do
        local group = groups[key]
        if group and group.blockMouse then
            for _, frame in ipairs(group.frames) do
                CreateInteractionBlocker(group, frame)
            end
        end
    end
end

local function HideAllInteractionBlockers()
    for _, key in ipairs(GROUP_ORDER) do
        local group = groups[key]
        if group then
            for _, blocker in pairs(group.blockers) do
                blocker:Hide()
            end
        end
    end
end

local function ShouldShowFullHUD()
    if not ImmersionFadeDB or not ImmersionFadeDB.enabled then
        return true
    end
    if paused or editModeOpen then
        return true
    end

    -- InCombatLockdown is the authoritative addon-facing signal and remains a
    -- plain, safe boolean on the modern client. UnitAffectingCombat is retained
    -- only as a guarded fallback for older clients.
    if IsInCombatLockdown() or SafeTruthyCall(UnitAffectingCombat, "player") then
        return true
    end

    -- Forever uses the modern action-bar controller. Its override/vehicle/temp
    -- shapeshift state moved under C_ActionBar, while older Classic clients expose
    -- equivalent globals. In any of these states we force the full HUD so a quest
    -- vehicle or possessed creature can never present invisible controls.
    if C_ActionBar then
        if SafeTruthyCall(C_ActionBar.HasOverrideActionBar)
            or SafeTruthyCall(C_ActionBar.HasVehicleActionBar)
            or SafeTruthyCall(C_ActionBar.HasTempShapeshiftActionBar) then
            return true
        end
    end

    if SafeTruthyCall(_G.HasOverrideActionBar)
        or SafeTruthyCall(_G.HasVehicleActionBar)
        or SafeTruthyCall(_G.IsPossessBarVisible) then
        return true
    end

    local possessBar = ResolveGlobalPath("PossessActionBar") or ResolveGlobalPath("PossessBarFrame")
    if possessBar and type(possessBar.IsShown) == "function" then
        local ok, shown = pcall(possessBar.IsShown, possessBar)
        if ok and not IsSecretValue(shown) and shown then
            return true
        end
    end

    if C_PetBattles and SafeTruthyCall(C_PetBattles.IsInBattle) then
        return true
    end

    return false
end

local function GetDesiredGroupAlpha(key, showFullHUD)
    local group = groups[key]
    if not group or not ImmersionFadeDB.groups[key] then
        return 1
    end

    -- Pausing/editing is an explicit request to see the complete Blizzard HUD.
    if not ImmersionFadeDB.enabled or paused or editModeOpen then
        return 1
    end

    if group.mode == "experience" then
        return xpRevealActive and 1 or 0
    end

    if group.mode == "alwaysHidden" then
        return 0
    end

    if group.mode == "gamepadModifier" then
        -- The controller overlay is combat UI first and contextual exploration UI
        -- second: always visible in combat/full-HUD states, otherwise reveal it
        -- only while a shoulder/trigger modifier is held.
        if showFullHUD then
            return 1
        end
        return gamepadModifierActive and 1 or 0
    end

    return showFullHUD and 1 or GetExplorationAlpha(key)
end

local function RefreshInteractionBlockers()
    if not ImmersionFadeDB or not ImmersionFadeDB.interactionBlockers then
        HideAllInteractionBlockers()
        return
    end

    -- We only shield controls once they are effectively invisible. This avoids
    -- visible-but-dead buttons during most of the fade animation. Special
    -- contextual groups (XP/performance) can remain hidden even in combat, so
    -- evaluate each group's desired state instead of globally dropping every
    -- blocker just because combat mode is active.
    local invisibleThreshold = 0.025
    local showFullHUD = ShouldShowFullHUD()

    for _, key in ipairs(GROUP_ORDER) do
        local group = groups[key]
        if group and group.blockMouse then
            local desiredAlpha = GetDesiredGroupAlpha(key, showFullHUD)
            local shouldShieldGroup = ImmersionFadeDB.groups[key]
                and desiredAlpha <= invisibleThreshold
                and group.currentAlpha <= invisibleThreshold

            for frame, blocker in pairs(group.blockers) do
                local frameShown = false
                if shouldShieldGroup and type(frame.IsShown) == "function" then
                    local ok, shown = pcall(frame.IsShown, frame)
                    frameShown = ok and shown and true or false
                end

                if frameShown then
                    blocker:Show()
                else
                    blocker:Hide()
                end
            end
        end
    end
end

local function ResolveFrames()
    BuildGroups()

    for key, definition in pairs(GROUP_DEFINITIONS) do
        local group = groups[key]

        for _, candidates in ipairs(definition.elements) do
            local region = nil
            local resolvedFrom = nil
            for _, path in ipairs(candidates) do
                local candidate = ResolveGlobalPath(path)
                if IsRegionAccessible(candidate) then
                    region = candidate
                    resolvedFrom = path
                    break
                end
            end

            if region and not group.frameSet[region] then
                group.frameSet[region] = true
                group.frameNames[region] = resolvedFrom
                table.insert(group.frames, region)
                SafeSetAlpha(region, group.currentAlpha)
                CreateInteractionBlocker(group, region)
            end
        end
    end

    EnsureInteractionBlockers()
    RefreshInteractionBlockers()
end

local function SetGroupAlpha(group, alpha)
    alpha = Clamp(alpha, 0, 1)
    group.currentAlpha = alpha
    for _, region in ipairs(group.frames) do
        SafeSetAlpha(region, alpha)
    end
end

local function StartSingleGroupTransition(key, targetAlpha, duration)
    local group = groups[key]
    if not group then return end

    duration = math.max(0, duration or 0)
    targetAlpha = Clamp(targetAlpha, 0, 1)
    group.startAlpha = group.currentAlpha
    group.targetAlpha = targetAlpha
    group.startedAt = GetTime()
    group.duration = duration
    group.animating = duration > 0 and math.abs(group.currentAlpha - targetAlpha) > 0.001

    if not group.animating then
        SetGroupAlpha(group, targetAlpha)
    end

    RefreshInteractionBlockers()
end

local function SetAllManagedAlpha(alpha)
    for key, group in pairs(groups) do
        if ImmersionFadeDB.groups[key] then
            group.animating = false
            group.targetAlpha = alpha
            SetGroupAlpha(group, alpha)
        else
            -- If a group is not managed, make sure we leave it fully visible.
            group.animating = false
            group.targetAlpha = 1
            SetGroupAlpha(group, 1)
        end
    end
    RefreshInteractionBlockers()
end

local function SmoothStep(t)
    -- Smooth acceleration/deceleration without requiring animation groups.
    return t * t * (3 - 2 * t)
end

local function StartModeTransition(showFullHUD, duration)
    ResolveFrames()
    duration = math.max(0, duration or 0)

    for key, group in pairs(groups) do
        if ImmersionFadeDB.groups[key] then
            local targetAlpha = GetDesiredGroupAlpha(key, showFullHUD)
            group.startAlpha = group.currentAlpha
            group.targetAlpha = targetAlpha
            group.startedAt = GetTime()
            group.duration = duration
            group.animating = duration > 0 and math.abs(group.currentAlpha - targetAlpha) > 0.001
            if not group.animating then
                SetGroupAlpha(group, targetAlpha)
            end
        else
            group.animating = false
            group.targetAlpha = 1
            SetGroupAlpha(group, 1)
        end
    end

    RefreshInteractionBlockers()
end

local function EnterCombatMode(immediate)
    CancelHideTimer()

    -- Our blockers are unprotected, so we can remove them immediately when
    -- combat begins without touching Blizzard's protected action buttons.
    HideAllInteractionBlockers()

    if immediate then
        StartModeTransition(true, 0)
    else
        StartModeTransition(true, ImmersionFadeDB.fadeInDuration)
    end
end

local function EnterExplorationMode(immediate)
    CancelHideTimer()

    if ShouldShowFullHUD() then
        EnterCombatMode(immediate)
        return
    end

    EnsureInteractionBlockers()

    if immediate or ImmersionFadeDB.fadeOutDelay <= 0 then
        StartModeTransition(false, immediate and 0 or ImmersionFadeDB.fadeOutDuration)
        return
    end

    -- Keep the HUD visible briefly after combat before it settles back into the world.
    hideTimer = C_Timer.NewTimer(ImmersionFadeDB.fadeOutDelay, function()
        hideTimer = nil
        if not ShouldShowFullHUD() then
            EnsureInteractionBlockers()
            StartModeTransition(false, ImmersionFadeDB.fadeOutDuration)
        end
    end)
end

local function EvaluateMode(immediate)
    if ShouldShowFullHUD() then
        EnterCombatMode(immediate)
    else
        EnterExplorationMode(immediate)
    end
end

local function UpdateGamePadModifierState(force)
    local isHeld = IsGamePadModifierHeld()
    if not force and isHeld == gamepadModifierActive then
        return
    end

    gamepadModifierActive = isHeld

    if not initialized or not ImmersionFadeDB or not ImmersionFadeDB.groups.controllerUI then
        return
    end

    -- Combat/full-HUD states always reveal the controller overlay. During
    -- exploration, the overlay follows the shoulder/trigger buttons only.
    if ShouldShowFullHUD() or gamepadModifierActive then
        StartSingleGroupTransition("controllerUI", 1, ImmersionFadeDB.fadeInDuration)
    else
        StartSingleGroupTransition("controllerUI", 0, ImmersionFadeDB.fadeOutDuration)
    end
end

local function BeginTimedPause(seconds)
    seconds = Clamp(tonumber(seconds) or 5, 0.25, 60)

    -- Repeated presses restart the reveal window instead of stacking timers.
    CancelPauseTimer()
    paused = true
    CancelHideTimer()
    EnterCombatMode(false)

    pauseTimer = C_Timer.NewTimer(seconds, function()
        pauseTimer = nil
        paused = false
        EvaluateMode(false)
    end)
end

local editModeHooked = false
local editModeEventsHooked = false
local function TryHookEditMode()
    -- Modern UI exposes stable EditMode.Enter/EditMode.Exit callbacks. Prefer
    -- those when available, while retaining frame OnShow/OnHide hooks as a
    -- compatibility fallback for clients that do not publish EventRegistry.
    if not editModeEventsHooked and EventRegistry and type(EventRegistry.RegisterCallback) == "function" then
        local okEnter = pcall(EventRegistry.RegisterCallback, EventRegistry, "EditMode.Enter", function()
            editModeOpen = true
            EnterCombatMode(false)
        end, addon)
        local okExit = pcall(EventRegistry.RegisterCallback, EventRegistry, "EditMode.Exit", function()
            editModeOpen = false
            EvaluateMode(false)
        end, addon)
        editModeEventsHooked = okEnter and okExit
    end

    if editModeHooked or not EditModeManagerFrame then
        return
    end

    editModeHooked = true
    EditModeManagerFrame:HookScript("OnShow", function()
        editModeOpen = true
        EnterCombatMode(false)
    end)
    EditModeManagerFrame:HookScript("OnHide", function()
        editModeOpen = false
        EvaluateMode(false)
    end)
end

local function ApplyGroupSetting(key)
    local group = groups[key]
    if not group then return end

    if ImmersionFadeDB.groups[key] then
        local alpha = GetDesiredGroupAlpha(key, ShouldShowFullHUD())
        group.animating = false
        group.targetAlpha = alpha
        SetGroupAlpha(group, alpha)
    else
        group.animating = false
        group.targetAlpha = 1
        SetGroupAlpha(group, 1)
    end

    RefreshInteractionBlockers()
end

local function RevealExperienceBar()
    if not ImmersionFadeDB or not ImmersionFadeDB.enabled or paused or editModeOpen then
        return
    end
    if not ImmersionFadeDB.groups.experienceBar then
        return
    end

    CancelXPHideTimer()
    xpRevealActive = true
    StartSingleGroupTransition("experienceBar", 1, ImmersionFadeDB.fadeInDuration)

    xpHideTimer = C_Timer.NewTimer(ImmersionFadeDB.xpRevealDuration, function()
        xpHideTimer = nil
        xpRevealActive = false

        if not ImmersionFadeDB or not ImmersionFadeDB.enabled or paused or editModeOpen then
            return
        end
        if ImmersionFadeDB.groups.experienceBar then
            StartSingleGroupTransition("experienceBar", 0, ImmersionFadeDB.fadeOutDuration)
        end
    end)
end

local function CheckExperienceGain()
    if type(UnitXP) ~= "function" then
        return
    end

    local currentXP = UnitXP("player")
    if type(currentXP) ~= "number" then
        return
    end

    if lastXP ~= nil and currentXP > lastXP then
        RevealExperienceBar()
    end
    lastXP = currentXP
end

local function FindGroupKey(input)
    if not input then return nil end
    local needle = input:lower()
    for key in pairs(GROUP_DEFINITIONS) do
        if key:lower() == needle then
            return key
        end
    end
    return nil
end

local function PrintGroupList()
    Print("Managed groups:")
    for _, key in ipairs(GROUP_ORDER) do
        local enabled = ImmersionFadeDB.groups[key] and "|cff63d471ON|r" or "|cffaaaaaaOFF|r"
        local mode = GROUP_DEFINITIONS[key].mode
        if mode == "experience" then
            Print(string.format("  %-14s %s  XP-triggered  - %s", key, enabled, GROUP_DEFINITIONS[key].label))
        elseif mode == "alwaysHidden" then
            Print(string.format("  %-14s %s  hidden while active  - %s", key, enabled, GROUP_DEFINITIONS[key].label))
        elseif mode == "gamepadModifier" then
            Print(string.format("  %-14s %s  shoulder/trigger reveal  - %s", key, enabled, GROUP_DEFINITIONS[key].label))
        else
            local alpha = GetExplorationAlpha(key)
            Print(string.format("  %-14s %s  alpha %.2f  - %s", key, enabled, alpha, GROUP_DEFINITIONS[key].label))
        end
    end
end

local function PrintResolvedFrames()
    ResolveFrames()
    Print("Resolved Blizzard regions (useful for Forever beta debugging):")
    for _, key in ipairs(GROUP_ORDER) do
        local group = groups[key]
        local names = {}
        for _, region in ipairs(group.frames) do
            table.insert(names, GetRegionName(region, group.frameNames[region]))
        end
        if #names == 0 then
            Print("  " .. key .. ": |cffff9f43none found|r")
        else
            Print("  " .. key .. ": " .. table.concat(names, ", "))
        end
    end
end

local function PrintClientInfo()
    local flavor = IS_FOREVER and "Forever (modern UI architecture)" or "other WoW client"
    Print(string.format("Client: %s, version %s, build %s, interface %s.",
        flavor, tostring(CLIENT_VERSION), tostring(CLIENT_BUILD), tostring(CLIENT_INTERFACE)))
end

local function PrintStatus()
    PrintClientInfo()
    local state = ShouldShowFullHUD() and "COMBAT / FULL HUD" or "EXPLORATION"
    Print("Current mode: |cffffffff" .. state .. "|r")
    Print(string.format("Base alpha %.2f, chat alpha %.2f, fade-in %.2fs, fade-out %.2fs, delay %.2fs, XP reveal %.2fs",
        ImmersionFadeDB.explorationAlpha,
        GetExplorationAlpha("chat"),
        ImmersionFadeDB.fadeInDuration,
        ImmersionFadeDB.fadeOutDuration,
        ImmersionFadeDB.fadeOutDelay,
        ImmersionFadeDB.xpRevealDuration))
    Print("Invisible-control shielding: " .. (ImmersionFadeDB.interactionBlockers and "|cff63d471ON|r (swallow)" or "|cffaaaaaaOFF|r"))
    if paused then
        if pauseTimer then
            Print("Automatic fading is temporarily |cffffd166PAUSED|r by a timed reveal.")
        else
            Print("Automatic fading is temporarily |cffffd166PAUSED|r.")
        end
    end
end

local function PrintHelp()
    Print("Commands:")
    Print("  /imfade status - current mode, client and timing")
    Print("  /imfade client - print detected WoW build/interface")
    Print("  /imfade on | off - enable/disable automatic mode switching")
    Print("  /imfade pause - toggle an indefinite full-HUD pause")
    Print("  /imfade pause <seconds> - show the full HUD temporarily")
    Print("  /imfade peek [seconds] - silent macro-friendly temporary reveal (default 5s)")
    Print("  /imfade alpha 0-1 - base exploration opacity")
    Print("  /imfade alpha <group> 0-1 - per-group exploration opacity")
    Print("  /imfade delay seconds - delay before fading after combat")
    Print("  /imfade fadein seconds - combat-mode fade-in time")
    Print("  /imfade fadeout seconds - exploration fade-out time")
    Print("  /imfade xpseconds seconds - how long XP bar stays visible after XP gain")
    Print("  /imfade blockers on|off - swallow mouse input over invisible controls")
    Print("  /imfade groups - list configurable frame groups")
    Print("  /imfade group <name> on|off - manage/unmanage a group")
    Print("  /imfade frames - print the Blizzard regions we found")
    Print("  /imfade reset - restore defaults")
end

local function HandleSlashCommand(message)
    message = (message or ""):match("^%s*(.-)%s*$")
    local command, rest = message:match("^(%S+)%s*(.-)$")
    command = command and command:lower() or ""

    if command == "" or command == "help" then
        PrintHelp()
        return
    end

    if command == "status" then
        PrintStatus()
        return
    end

    if command == "client" or command == "build" then
        PrintClientInfo()
        return
    end

    if command == "on" then
        ImmersionFadeDB.enabled = true
        paused = false
        CancelPauseTimer()
        EvaluateMode(false)
        Print("Automatic mode switching enabled.")
        return
    end

    if command == "off" then
        ImmersionFadeDB.enabled = false
        paused = false
        CancelPauseTimer()
        CancelHideTimer()
        HideAllInteractionBlockers()
        SetAllManagedAlpha(1)
        Print("Automatic mode switching disabled; HUD restored.")
        return
    end

    if command == "pause" then
        local seconds = tonumber(rest)
        if rest ~= "" then
            if not seconds or seconds < 0.25 or seconds > 60 then
                Print("Usage: /imfade pause <seconds> (0.25-60)")
                return
            end
            BeginTimedPause(seconds)
            Print(string.format("Full HUD revealed for %.1fs.", seconds))
            return
        end

        CancelPauseTimer()
        paused = not paused
        EvaluateMode(false)
        Print(paused and "Paused; full HUD forced." or "Resumed automatic mode switching.")
        return
    end

    if command == "peek" or command == "reveal" then
        local seconds = rest ~= "" and tonumber(rest) or 5
        if not seconds or seconds < 0.25 or seconds > 60 then
            Print("Usage: /imfade peek [seconds] (0.25-60)")
            return
        end

        -- Intentionally silent: this command is designed for a frequently-used macro.
        BeginTimedPause(seconds)
        return
    end

    if command == "alpha" then
        local first, second = rest:match("^(%S+)%s*(%S*)$")
        local globalValue = tonumber(first)

        if globalValue and second == "" then
            if globalValue < 0 or globalValue > 1 then
                Print("Usage: /imfade alpha 0-1")
                return
            end
            ImmersionFadeDB.explorationAlpha = globalValue
            EvaluateMode(false)
            Print(string.format("Base exploration alpha set to %.2f.", globalValue))
            return
        end

        local key = FindGroupKey(first)
        local value = tonumber(second)
        if not key or not value or value < 0 or value > 1 then
            Print("Usage: /imfade alpha 0-1  OR  /imfade alpha <group> 0-1")
            return
        end

        ImmersionFadeDB.explorationAlphas[key] = value
        ApplyGroupSetting(key)
        Print(string.format("%s exploration alpha set to %.2f.", GROUP_DEFINITIONS[key].label, value))
        return
    end

    if command == "delay" or command == "fadein" or command == "fadeout" then
        local value = tonumber(rest)
        if not value or value < 0 or value > 10 then
            Print("Use a value between 0 and 10 seconds.")
            return
        end
        if command == "delay" then
            ImmersionFadeDB.fadeOutDelay = value
        elseif command == "fadein" then
            ImmersionFadeDB.fadeInDuration = value
        else
            ImmersionFadeDB.fadeOutDuration = value
        end
        Print(command .. " set to " .. value .. "s.")
        return
    end

    if command == "xpseconds" then
        local value = tonumber(rest)
        if not value or value < 0.5 or value > 30 then
            Print("Use an XP reveal duration between 0.5 and 30 seconds.")
            return
        end
        ImmersionFadeDB.xpRevealDuration = value
        Print(string.format("XP bar reveal duration set to %.2fs.", value))
        return
    end

    if command == "blockers" or command == "swallow" then
        local value = rest:lower()
        if value ~= "on" and value ~= "off" then
            Print("Usage: /imfade blockers on|off")
            return
        end
        ImmersionFadeDB.interactionBlockers = value == "on"
        EnsureInteractionBlockers()
        RefreshInteractionBlockers()
        Print("Invisible-control shielding " .. (value == "on" and "enabled (swallow mode)." or "disabled."))
        return
    end

    if command == "groups" then
        PrintGroupList()
        return
    end

    if command == "group" then
        local inputKey, value = rest:match("^(%S+)%s+(%S+)$")
        local key = FindGroupKey(inputKey)
        value = value and value:lower() or nil
        if not key or (value ~= "on" and value ~= "off") then
            Print("Usage: /imfade group <name> on|off")
            Print("Run /imfade groups to see names.")
            return
        end
        ImmersionFadeDB.groups[key] = value == "on"
        ResolveFrames()
        ApplyGroupSetting(key)
        Print(GROUP_DEFINITIONS[key].label .. " management " .. (value == "on" and "enabled." or "disabled."))
        return
    end

    if command == "frames" then
        PrintResolvedFrames()
        return
    end

    if command == "reset" then
        HideAllInteractionBlockers()
        ImmersionFadeDB = DeepCopyDefaults(DEFAULTS, {})
        paused = false
        CancelPauseTimer()
        ResolveFrames()
        EvaluateMode(false)
        Print("Settings reset to v0.6.1 defaults.")
        return
    end

    Print("Unknown command. Use /imfade help.")
end

local function Initialize()
    if initialized then return end
    initialized = true

    ImmersionFadeDB = DeepCopyDefaults(DEFAULTS, ImmersionFadeDB)
    if type(UnitXP) == "function" then
        lastXP = UnitXP("player")
    end
    BuildGroups()
    ResolveFrames()
    TryHookEditMode()

    SLASH_ImmersionFade1 = "/imfade"
    SLASH_ImmersionFade2 = "/ImmersionFade"
    SlashCmdList.ImmersionFade = HandleSlashCommand

    EvaluateMode(false)
    Print("v0.6.1 loaded. Forever controller UI support enabled. Type |cffffffff/imfade|r for controls.")
end

addon:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME then
            Initialize()
        elseif initialized then
            -- Blizzard UI components such as CooldownViewer/EditMode can load lazily.
            ResolveFrames()
            TryHookEditMode()
            EvaluateMode(true)
        end
        return
    end

    if not initialized then return end

    if event == "PLAYER_REGEN_DISABLED" then
        EnterCombatMode(false)
    elseif event == "PLAYER_REGEN_ENABLED" then
        EnsureInteractionBlockers()
        EnterExplorationMode(false)
    elseif event == "PLAYER_XP_UPDATE" then
        if arg1 == nil or arg1 == "player" then
            CheckExperienceGain()
        end
    elseif event == "PLAYER_LEVEL_UP" then
        RevealExperienceBar()
        if type(UnitXP) == "function" then
            lastXP = UnitXP("player")
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        ResolveFrames()
        TryHookEditMode()
        gamepadButtonIndexesDirty = true
        UpdateGamePadModifierState(true)
        if type(UnitXP) == "function" then
            lastXP = UnitXP("player")
        end
        EvaluateMode(false)
    elseif event == "GAME_PAD_CONFIGS_CHANGED"
        or event == "GAME_PAD_CONNECTED"
        or event == "GAME_PAD_DISCONNECTED"
        or event == "GAME_PAD_ACTIVE_CHANGED" then
        gamepadButtonIndexesDirty = true
        UpdateGamePadModifierState(true)
    else
        -- Vehicle/override UI state changed.
        EvaluateMode(false)
    end
end)

addon:SetScript("OnUpdate", function(_, elapsed)
    if not initialized then return end

    local now = GetTime()
    local anyAnimating = false

    -- Poll mapped controller state instead of enabling gamepad input on our own
    -- frame. WoW dispatches OnGamePadButtonDown/Up only to the top-most enabled
    -- receiver, so polling avoids stealing LB/LT/RB/RT from Blizzard's UI.
    gamepadPollTimer = gamepadPollTimer + elapsed
    if gamepadPollTimer >= 0.033 then
        gamepadPollTimer = 0
        UpdateGamePadModifierState(false)
    end

    for key, group in pairs(groups) do
        if ImmersionFadeDB.groups[key] and group.animating then
            anyAnimating = true
            local progress
            if group.duration <= 0 then
                progress = 1
            else
                progress = Clamp((now - group.startedAt) / group.duration, 0, 1)
            end
            local eased = SmoothStep(progress)
            local alpha = group.startAlpha + (group.targetAlpha - group.startAlpha) * eased
            SetGroupAlpha(group, alpha)

            if progress >= 1 then
                group.animating = false
                SetGroupAlpha(group, group.targetAlpha)
            end
        end
    end

    RefreshInteractionBlockers()

    -- A low-frequency heartbeat keeps Blizzard from silently resetting the alpha
    -- of managed regions after action-bar/layout updates. It also discovers lazily
    -- created frames without doing expensive work every rendered frame.
    heartbeat = heartbeat + elapsed
    rescanTimer = rescanTimer + elapsed

    if heartbeat >= 0.50 and not anyAnimating then
        heartbeat = 0
        for key, group in pairs(groups) do
            if ImmersionFadeDB.groups[key] then
                SetGroupAlpha(group, group.currentAlpha)
            end
        end
        RefreshInteractionBlockers()
    end

    if rescanTimer >= 5.0 then
        rescanTimer = 0
        ResolveFrames()
        TryHookEditMode()
    end
end)

addon:RegisterEvent("ADDON_LOADED")
addon:RegisterEvent("PLAYER_ENTERING_WORLD")
addon:RegisterEvent("PLAYER_REGEN_DISABLED")
addon:RegisterEvent("PLAYER_REGEN_ENABLED")
addon:RegisterEvent("PLAYER_XP_UPDATE")
addon:RegisterEvent("PLAYER_LEVEL_UP")
addon:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
addon:RegisterEvent("UPDATE_OVERRIDE_ACTIONBAR")
addon:RegisterEvent("UPDATE_POSSESS_BAR")
addon:RegisterEvent("UNIT_ENTERED_VEHICLE")
addon:RegisterEvent("UNIT_EXITED_VEHICLE")
addon:RegisterEvent("GAME_PAD_ACTIVE_CHANGED")
addon:RegisterEvent("GAME_PAD_CONFIGS_CHANGED")
addon:RegisterEvent("GAME_PAD_CONNECTED")
addon:RegisterEvent("GAME_PAD_DISCONNECTED")
