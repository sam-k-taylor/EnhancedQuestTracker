local addonName, ns = ...

ns.name = addonName

local DEFAULTS = {
	point = { "TOPRIGHT", "UIParent", "TOPRIGHT", -80, -220 },
	width = 260,
	height = 400,
	locked = false,
	hideBlizzardTracker = true,
	announceParty = true,
	announceAccepted = false,
	autoShare = false,
	showRewards = false,
	tomtomButton = true, -- only shown when TomTom is installed
	style = "Default",
	fontScale = 100, -- percent of the default font sizes
	bgOpacity = 0, -- percent opacity of the tracker background
	groupByZone = true,
	currentZoneFirst = false,
	collapsed = {}, -- [zone key] = true (see Data:GetZones)
}
ns.defaults = DEFAULTS

-- Visual styles for the tracker, in the order shown in the Style dropdown.
-- look picks the tracker's layout and art (see Tracker.lua); textOutline is the
-- font flag applied to all tracker text.
ns.styles = {
	{ key = "Default", name = "Default", look = "blizzard", textOutline = "" },
	{ key = "QuestieLike", name = "QuestieLike", look = "questie", textOutline = "" },
	{ key = "QuestieLikeHighContrast", name = "QuestieLike - High Contrast", look = "questie", textOutline = "OUTLINE" },
}

local function FindStyle(key)
	for _, style in ipairs(ns.styles) do
		if style.key == key then return style end
	end
end

function ns:GetStyle()
	return FindStyle(ns.db.style) or FindStyle(DEFAULTS.style)
end

local function ApplyDefaults(db, defaults)
	for k, v in pairs(defaults) do
		if db[k] == nil then
			db[k] = type(v) == "table" and CopyTable(v) or v
		elseif type(v) == "table" and type(db[k]) == "table" and k ~= "point" then
			ApplyDefaults(db[k], v)
		end
	end
end

function ns:Print(...)
	print("|cff33ff99" .. addonName .. "|r:", ...)
end

-- Debounced refresh: QUEST_LOG_UPDATE can fire many times per second.
local refreshPending = false
function ns:RequestRefresh()
	if refreshPending then return end
	refreshPending = true
	C_Timer.After(0.1, function()
		refreshPending = false
		ns.Announce:Scan()
		ns.TomTom:Update()
		ns.Tracker:Refresh()
	end)
end

-- Text styling ---------------------------------------------------------------

-- Every tracker font string is registered here, with its template's font size,
-- so the style's text outline and the font size option can be applied to
-- existing text. A font string can use a different base size per look.
local styledText = {} -- [fontString] = { size = base font size, looks = { [look] = size } }

-- Scales a font-relative size (row heights, indents) by the font size option.
function ns:Scale(value)
	return math.floor(value * ns.db.fontScale / 100 + 0.5)
end

local function ApplyTextStyle(fontString, info)
	local style = ns:GetStyle()
	local size = info.looks and info.looks[style.look] or info.size
	local font = fontString:GetFont()
	fontString:SetFont(font, size * ns.db.fontScale / 100, style.textOutline)
end

-- lookSizes: optional { [look] = base font size } overriding the template's size.
function ns:RegisterText(fontString, lookSizes)
	local _, size = fontString:GetFont()
	local info = { size = size, looks = lookSizes }
	styledText[fontString] = info
	ApplyTextStyle(fontString, info)
end

function ns:UpdateTextStyle()
	for fontString, info in pairs(styledText) do
		ApplyTextStyle(fontString, info)
	end
end

-- Blizzard tracker hiding ---------------------------------------------------

local hiddenParent = CreateFrame("Frame")
hiddenParent:Hide()

local originalParent -- where Blizzard had the tracker before we hid it
local hooked = false
local updating = false

function ns:UpdateBlizzardTracker()
	local blizz = ObjectiveTrackerFrame
	if not blizz or updating then return end

	-- Blizzard's managed frame / Edit Mode layout re-parents the tracker during
	-- login, which would undo our hiding, so re-apply whenever that happens.
	if not hooked then
		hooked = true
		hooksecurefunc(blizz, "SetParent", function(_, parent)
			if parent ~= hiddenParent then
				originalParent = parent
				if ns.db.hideBlizzardTracker then ns:UpdateBlizzardTracker() end
			end
		end)
	end

	if InCombatLockdown() then return end -- retried on PLAYER_REGEN_ENABLED

	updating = true
	if ns.db.hideBlizzardTracker then
		if blizz:GetParent() ~= hiddenParent then
			originalParent = blizz:GetParent()
			blizz:SetParent(hiddenParent)
		end
	elseif blizz:GetParent() == hiddenParent then
		blizz:SetParent(originalParent or UIParent)
	end
	updating = false
end

-- Events --------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("QUEST_LOG_UPDATE")
events:RegisterEvent("QUEST_ACCEPTED")
events:RegisterEvent("QUEST_DETAIL")
events:RegisterEvent("QUEST_POI_UPDATE") -- quest locations loaded, for TomTom buttons
events:RegisterEvent("QUEST_REMOVED")
events:RegisterEvent("QUEST_WATCH_LIST_CHANGED")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
events:RegisterEvent("SUPER_TRACKING_CHANGED")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:RegisterEvent("BAG_UPDATE_COOLDOWN")

events:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 == addonName then
			EnhancedQuestTrackerDB = EnhancedQuestTrackerDB or {}
			ns.db = EnhancedQuestTrackerDB
			-- The old High Contrast Mode checkbox is now a style. Players from before
			-- styles existed keep the QuestieLike look they had.
			if ns.db.highContrast ~= nil then
				if ns.db.style == nil then
					ns.db.style = ns.db.highContrast and "QuestieLikeHighContrast" or "QuestieLike"
				end
				ns.db.highContrast = nil
			end
			-- The background used to be fixed per style: none for Default, 35% for
			-- QuestieLike. Players from before the opacity option keep what they had.
			if ns.db.bgOpacity == nil and ns.db.style ~= nil and ns.db.style ~= "Default" then
				ns.db.bgOpacity = 35
			end
			ApplyDefaults(ns.db, DEFAULTS)
			ns.Options:Init()
		elseif arg1 == "Blizzard_ObjectiveTracker" and ns.db then
			ns:UpdateBlizzardTracker()
		end
	elseif event == "PLAYER_LOGIN" then
		ns.Tracker:Init()
		ns:UpdateBlizzardTracker()
		ns:RequestRefresh()
	elseif event == "PLAYER_ENTERING_WORLD" then
		ns:UpdateBlizzardTracker()
		ns:RequestRefresh()
	elseif event == "PLAYER_REGEN_ENABLED" then
		ns:UpdateBlizzardTracker()
		ns.ItemButtons:OnCombatEnded()
	elseif event == "QUEST_DETAIL" then
		ns.Announce:OnQuestDetail()
	elseif event == "QUEST_ACCEPTED" then
		ns.Announce:OnQuestAccepted(arg1)
		ns:RequestRefresh()
	elseif event == "SUPER_TRACKING_CHANGED" then
		ns.TomTom:OnSuperTrackingChanged()
		ns:RequestRefresh()
	elseif event == "BAG_UPDATE_COOLDOWN" then
		ns.ItemButtons:UpdateCooldowns()
	else
		ns:RequestRefresh()
	end
end)

-- Slash commands ------------------------------------------------------------

SLASH_ENHANCEDQUESTTRACKER1 = "/eqt"
SLASH_ENHANCEDQUESTTRACKER2 = "/enhancedquesttracker"
SlashCmdList.ENHANCEDQUESTTRACKER = function(msg)
	local cmd = strtrim(msg or ""):lower()
	if cmd == "lock" then
		ns.db.locked = not ns.db.locked
		ns:Print(ns.db.locked and "Tracker locked (hold Shift to move/resize)." or "Tracker unlocked.")
	elseif cmd == "blizz" then
		ns.db.hideBlizzardTracker = not ns.db.hideBlizzardTracker
		ns:UpdateBlizzardTracker()
		ns:Print(ns.db.hideBlizzardTracker and "Blizzard tracker hidden." or "Blizzard tracker shown.")
	elseif cmd == "announce" then
		ns.db.announceParty = not ns.db.announceParty
		ns:Print(ns.db.announceParty and "Party quest completion announcements on." or "Party quest completion announcements off.")
	elseif cmd == "announceaccept" then
		ns.db.announceAccepted = not ns.db.announceAccepted
		ns:Print(ns.db.announceAccepted and "Party quest accepted announcements on." or "Party quest accepted announcements off.")
	elseif cmd == "share" then
		ns.db.autoShare = not ns.db.autoShare
		ns:Print(ns.db.autoShare and "Auto-sharing accepted quests with party on." or "Auto-sharing accepted quests with party off.")
	elseif cmd == "expand" then
		wipe(ns.db.collapsed)
		ns:RequestRefresh()
	elseif cmd == "reset" then
		ns.db.point = CopyTable(DEFAULTS.point)
		ns.db.width, ns.db.height = DEFAULTS.width, DEFAULTS.height
		ns.Tracker:RestoreSize()
		ns.Tracker:RestorePosition()
	elseif cmd == "options" or cmd == "config" then
		ns.Options:Open()
	elseif cmd == "toggle" or cmd == "" then
		ns.Tracker:Toggle()
	else
		ns:Print("Commands: toggle, options, lock, blizz, announce, announceaccept, share, expand, reset")
	end
end
