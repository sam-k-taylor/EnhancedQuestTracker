local _, ns = ...

local Tracker = {}
ns.Tracker = Tracker

local PADDING = 8
-- Row heights, indents and item sizes are for 100% font size; Layout scales
-- them with ns:Scale.
local ZONE_HEIGHT = 18
local QUEST_HEIGHT = 16
local OBJECTIVE_HEIGHT = 14
local OBJECTIVE_INDENT = 14
local QUEST_INDENT = 14 -- quests sit this far in from their zone header
-- Quest item buttons span the quest name row and the row below it.
local ITEM_SIZE = QUEST_HEIGHT + OBJECTIVE_HEIGHT
-- The item border art extends ~9px past the button, so leave room for it.
local ITEM_GAP = 12
-- Space after each quest; quests with an item need more room for its border.
local QUEST_SPACING = 2
local ITEM_QUEST_SPACING = 6
local ZONE_SPACING = 8 -- after each zone's quests
local MIN_WIDTH, MAX_WIDTH = 180, 600
local MIN_HEIGHT, MAX_HEIGHT = 80, 1000
local SCROLL_STEP = 30

-- Default look: sizes and art from Blizzard's objective tracker
-- (Blizzard_ObjectiveTracker in the forever UI source). Also for 100% font size.
local BLIZZ_HEADER_ATLAS = "ui-questtracker-primary-objective-header"
local BLIZZ_ZONE_ATLAS = "UI-QuestTracker-Secondary-Objective-Header"
local BLIZZ_HEADER_HEIGHT = 32
local BLIZZ_HEADER_GAP = 6 -- between the top header and the first zone header
local BLIZZ_ZONE_HEIGHT = 26
local BLIZZ_ZONE_TEXT_X = 7
local BLIZZ_BLOCK_X = 30 -- quest text inset; the POI bubble sits in this space
local BLIZZ_HEADER_TO_BLOCK = 10 -- zone header to first quest
local BLIZZ_BLOCK_SPACING = 10 -- between quests
local BLIZZ_ZONE_SPACING = 10 -- after each zone's quests
local BLIZZ_LINE_SPACING = 4
local BLIZZ_MIN_LINE_HEIGHT = 12
local BLIZZ_POI_SIZE = 20
local BLIZZ_POI_X, BLIZZ_POI_Y = -7, 5 -- POI bubble's top-right, from the quest text's top-left
local BLIZZ_CHECK_SIZE = 16
local BLIZZ_CHECK_X, BLIZZ_CHECK_Y = -10, 2 -- check mark's top-left, from the objective dash's
local BLIZZ_ITEM_SIZE = 26
local BLIZZ_ITEM_BORDER = 8 -- item border art extends this far past the button
local BLIZZ_RIGHT_PADDING = 8
-- Blizzard's OBJECTIVE_TRACKER_COLOR values.
local BLIZZ_OBJECTIVE_COLOR = { 0.8, 0.8, 0.8 }
local BLIZZ_COMPLETE_COLOR = { 0.6, 0.6, 0.6 }
local BLIZZ_HEADER_COLOR = { 1, 0.82, 0 }

-- Simple row pools so we don't create frames on every refresh.
local zoneRows, questRows, objectiveRows = {}, {}, {} -- objective rows are { text, dash, check }
local used = { zone = 0, quest = 0, objective = 0 }

-- Locked trackers can still be moved/resized while holding Shift.
-- Never in combat: the secure quest item buttons are anchored to the tracker.
local function CanMoveOrResize()
	if InCombatLockdown() then return false end
	return not ns.db.locked or IsShiftKeyDown()
end

local function LevelColor(level)
	if GetQuestDifficultyColor then
		local c = GetQuestDifficultyColor(level)
		if c then return c.r, c.g, c.b end
	end
	return 1, 0.82, 0
end

-- Inserts the quest link into an open chat edit box. Returns false if the
-- player isn't typing in chat.
local function InsertQuestLink(questID)
	local link = GetQuestLink and GetQuestLink(questID)
	if not link then return false end
	if ChatFrameUtil and ChatFrameUtil.InsertLink then
		return ChatFrameUtil.InsertLink(link)
	elseif ChatEdit_InsertLink then
		return ChatEdit_InsertLink(link)
	end
	return false
end

local function ShareInChat(questID)
	if InsertQuestLink(questID) then return end
	local link = GetQuestLink and GetQuestLink(questID)
	if link and ChatFrameUtil and ChatFrameUtil.OpenChat then
		ChatFrameUtil.OpenChat(link)
	end
end

local function ShowQuestMenu(owner, questID)
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle(C_QuestLog.GetTitleForQuestID(questID) or "")

		if C_SuperTrack.GetSuperTrackedQuestID() ~= questID then
			root:CreateButton("Focus", function() C_SuperTrack.SetSuperTrackedQuestID(questID) end)
		else
			root:CreateButton("Unfocus", function() C_SuperTrack.SetSuperTrackedQuestID(0) end)
		end

		root:CreateButton("Untrack", function()
			C_QuestLog.RemoveQuestWatch(questID)
			ns:RequestRefresh()
		end)

		local share = root:CreateButton("Share Quest", function() QuestUtil.ShareQuest(questID) end)
		share:SetEnabled(IsInGroup() and C_QuestLog.IsPushableQuest(questID))

		root:CreateButton("Share In Chat", function() ShareInChat(questID) end)

		-- Blizzard's handler shows the abandon confirmation popup.
		root:CreateButton("Abandon", function() QuestMapQuestOptions_AbandonQuest(questID) end)
	end)
end

-- Class colour for each player in the party, keyed by name (with and without
-- realm, since tooltip lines may show either).
local function GetGroupClassColors()
	local colors = {}
	local units = { "player" }
	for i = 1, GetNumSubgroupMembers() do
		units[#units + 1] = "party" .. i
	end
	for _, unit in ipairs(units) do
		local _, class = UnitClass(unit)
		local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
		if color then
			local name, realm = UnitName(unit)
			if name then
				colors[name] = color
				if realm and realm ~= "" then
					colors[name .. "-" .. realm] = color
				end
			end
		end
	end
	return colors
end

-- Recolours the tooltip lines that are just a group member's name.
local function ColorNamesInTooltip(colors)
	for i = 1, GameTooltip:NumLines() do
		local line = _G["GameTooltipTextLeft" .. i]
		local color = line and colors[line:GetText() or ""]
		if color then
			line:SetTextColor(color.r, color.g, color.b)
		end
	end
end

-- Adds the player's own name and objective progress to the tooltip.
local function AddPlayerProgress(quest, colors)
	local color = colors[UnitName("player")]
	local r, g, b = 1, 1, 1
	if color then r, g, b = color.r, color.g, color.b end
	GameTooltip:AddLine(UnitName("player"), r, g, b)
	if quest.isComplete then
		GameTooltip:AddLine("  Complete", 0.2, 1, 0.2)
		return
	end
	for _, obj in ipairs(quest.objectives) do
		if obj.text and obj.text ~= "" then
			if obj.finished then
				GameTooltip:AddLine("  " .. obj.text, 0.5, 0.5, 0.5)
			else
				GameTooltip:AddLine("  " .. obj.text, 0.9, 0.9, 0.9)
			end
		end
	end
end

local function ShowPartyTooltip(row)
	local quest = row.quest
	if not quest or #quest.partyMembers == 0 then return end
	GameTooltip:SetOwner(row, "ANCHOR_LEFT")
	local colors = GetGroupClassColors()
	if GameTooltip.SetQuestPartyProgress then
		-- Blizzard's tooltip lists every party member's objective progress,
		-- including ours.
		GameTooltip:SetQuestPartyProgress(quest.questID)
		ColorNamesInTooltip(colors)
	else
		GameTooltip:SetText(quest.title)
		for _, name in ipairs(quest.partyMembers) do
			local color = colors[name]
			if color then
				GameTooltip:AddLine(name, color.r, color.g, color.b)
			else
				GameTooltip:AddLine(name, 1, 1, 1)
			end
		end
		AddPlayerProgress(quest, colors)
	end
	GameTooltip:Show()
end

-- Sets an atlas at its own size scaled by the font size option.
local function SetAtlasScaled(texture, atlas)
	texture:SetAtlas(atlas, true)
	local w, h = texture:GetSize()
	texture:SetSize(ns:Scale(w), ns:Scale(h))
end

local function ToggleFocus(questID)
	if C_SuperTrack.GetSuperTrackedQuestID() == questID then
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
		C_SuperTrack.SetSuperTrackedQuestID(0)
	else
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		C_SuperTrack.SetSuperTrackedQuestID(questID)
	end
end

local function OpenQuest(questID)
	if QuestMapFrame_OpenToQuestDetails then
		QuestMapFrame_OpenToQuestDetails(questID)
	elseif ToggleQuestLog then
		ToggleQuestLog()
	end
end

-- Row factories ---------------------------------------------------------------
-- Rows carry the parts for every look; each look's layout shows the ones it uses.

local function AcquireZoneRow(parent)
	used.zone = used.zone + 1
	local row = zoneRows[used.zone]
	if not row then
		row = CreateFrame("Button", nil, parent)
		row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		row.text:SetJustifyH("LEFT")
		ns:RegisterText(row.text, { blizzard = 14 })

		-- Default look: header bar with a collapse/expand button on the right.
		row.bg = row:CreateTexture(nil, "BACKGROUND")
		row.bg:SetAllPoints()
		row.bg:SetAtlas(BLIZZ_ZONE_ATLAS)
		row.toggle = row:CreateTexture(nil, "ARTWORK")
		row.toggle:SetPoint("RIGHT", 1, 0)
		row.toggleHighlight = row:CreateTexture(nil, "HIGHLIGHT")
		row.toggleHighlight:SetPoint("CENTER", row.toggle)
		row.toggleHighlight:SetBlendMode("ADD")

		row:SetScript("OnClick", function(self)
			local collapsed = ns.db.collapsed
			collapsed[self.zoneName] = not collapsed[self.zoneName] or nil
			Tracker:Refresh()
		end)
		zoneRows[used.zone] = row
	end
	row:Show()
	return row
end

local function AcquireQuestRow(parent)
	used.quest = used.quest + 1
	local row = questRows[used.quest]
	if not row then
		row = CreateFrame("Button", nil, parent)
		row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		row.text:SetJustifyH("LEFT")
		ns:RegisterText(row.text)

		-- Focus indicator: gold highlight behind the row with an accent bar on the left.
		row.focusBg = row:CreateTexture(nil, "BACKGROUND")
		row.focusBg:SetPoint("BOTTOMRIGHT")
		row.focusBg:SetColorTexture(1, 0.82, 0, 0.18)
		row.focusBar = row:CreateTexture(nil, "ARTWORK")
		row.focusBar:SetPoint("TOPLEFT", row.focusBg, "TOPLEFT")
		row.focusBar:SetPoint("BOTTOMLEFT", row.focusBg, "BOTTOMLEFT")
		row.focusBar:SetWidth(2)
		row.focusBar:SetColorTexture(1, 0.82, 0, 0.9)

		-- Default look: quest POI bubble to the left of the name; click to focus.
		row.poi = CreateFrame("Button", nil, row)
		row.poi.bg = row.poi:CreateTexture(nil, "BACKGROUND")
		row.poi.bg:SetPoint("CENTER")
		row.poi.icon = row.poi:CreateTexture(nil, "ARTWORK")
		row.poi.icon:SetPoint("CENTER")
		row.poi.highlight = row.poi:CreateTexture(nil, "HIGHLIGHT")
		row.poi.highlight:SetPoint("CENTER")
		row.poi.highlight:SetBlendMode("ADD")
		row.poi:SetScript("OnClick", function(self) ToggleFocus(self:GetParent().questID) end)

		row:SetScript("OnEnter", ShowPartyTooltip)
		row:SetScript("OnLeave", GameTooltip_Hide)
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		row:SetScript("OnClick", function(self, button)
			if button == "RightButton" then
				ShowQuestMenu(self, self.questID)
			elseif IsShiftKeyDown() then
				if not InsertQuestLink(self.questID) then
					C_QuestLog.RemoveQuestWatch(self.questID)
					ns:RequestRefresh()
				end
			else
				OpenQuest(self.questID)
			end
		end)
		questRows[used.quest] = row
	end
	row:Show()
	return row
end

local function AcquireObjectiveRow(parent)
	used.objective = used.objective + 1
	local line = objectiveRows[used.objective]
	if not line then
		line = {}
		line.text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		line.text:SetJustifyH("LEFT")
		ns:RegisterText(line.text, { blizzard = 12 })
		-- Default look: separate dash so wrapped lines indent past it, and a check
		-- mark in its place once the objective is done.
		line.dash = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		line.dash:SetText(QUEST_DASH or "- ")
		ns:RegisterText(line.dash, { blizzard = 12 })
		line.check = parent:CreateTexture(nil, "ARTWORK")
		line.check:SetAtlas("ui-questtracker-tracker-check")
		objectiveRows[used.objective] = line
	end
	line.text:Show()
	line.dash:Hide()
	line.check:Hide()
	return line
end

local function ReleaseAll()
	for _, r in ipairs(zoneRows) do r:Hide() end
	for _, r in ipairs(questRows) do r:Hide() end
	for _, line in ipairs(objectiveRows) do
		line.text:Hide()
		line.dash:Hide()
		line.check:Hide()
	end
	used.zone, used.quest, used.objective = 0, 0, 0
end

-- Frame -----------------------------------------------------------------------

function Tracker:Init()
	local f = CreateFrame("Frame", "EnhancedQuestTrackerFrame", UIParent, "BackdropTemplate")
	f:SetWidth(ns.db.width)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self)
		if CanMoveOrResize() then self:StartMoving() end
	end)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		Tracker:SavePosition()
	end)
	if f.SetBackdrop then
		f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
	end

	-- QuestieLike title.
	f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.title:SetPoint("TOPLEFT", PADDING, -PADDING)
	f.title:SetText("Quests")
	ns:RegisterText(f.title)

	-- Default look title: header bar with a collapse/expand all button.
	f.header = CreateFrame("Frame", nil, f)
	f.header.bg = f.header:CreateTexture(nil, "BACKGROUND")
	f.header.bg:SetAllPoints()
	f.header.bg:SetAtlas(BLIZZ_HEADER_ATLAS)
	f.header.text = f.header:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	f.header.text:SetPoint("LEFT", BLIZZ_ZONE_TEXT_X, 0)
	f.header.text:SetText("Quests")
	f.header.text:SetTextColor(unpack(BLIZZ_HEADER_COLOR))
	ns:RegisterText(f.header.text, { blizzard = 14 })
	f.header.toggle = CreateFrame("Button", nil, f.header)
	f.header.toggle:SetPoint("RIGHT", -1, 0)
	f.header.toggle:SetScript("OnClick", function() Tracker:ToggleAllZones() end)

	-- Quest rows live in a scroll child so the window can be shorter than its content.
	f.scroll = CreateFrame("ScrollFrame", nil, f)
	f.scroll:EnableMouseWheel(true)
	f.scroll:SetScript("OnMouseWheel", function(self, delta)
		local offset = self:GetVerticalScroll() - delta * SCROLL_STEP
		offset = math.max(0, math.min(offset, self:GetVerticalScrollRange()))
		self:SetVerticalScroll(offset)
		Tracker:UpdateItemButtons()
	end)

	f.content = CreateFrame("Frame", nil, f.scroll)
	f.content:SetSize(1, 1)
	f.scroll:SetScrollChild(f.content)

	-- Bottom-right resize grip.
	f:SetResizable(true)
	if f.SetResizeBounds then
		f:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT)
	else
		f:SetMinResize(MIN_WIDTH, MIN_HEIGHT)
		f:SetMaxResize(MAX_WIDTH, MAX_HEIGHT)
	end

	local grip = CreateFrame("Button", nil, f)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", -2, 2)
	grip:SetFrameLevel(f:GetFrameLevel() + 10)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	grip:SetScript("OnMouseDown", function()
		if CanMoveOrResize() then f:StartSizing("BOTTOMRIGHT") end
	end)
	grip:SetScript("OnMouseUp", function()
		f:StopMovingOrSizing()
		ns.db.width = math.floor(f:GetWidth() + 0.5)
		ns.db.height = math.floor(f:GetHeight() + 0.5)
		Tracker:SavePosition()
	end)
	f.grip = grip

	f:SetScript("OnSizeChanged", function() Tracker:Layout() end)

	self.frame = f
	f:SetHeight(ns.db.height)
	self:RestorePosition()
end

-- Shows the title, background and scroll area for the current look. Re-applied
-- when the look or font size changes.
function Tracker:ApplyChrome(look)
	local f = self.frame
	local key = look .. ns.db.fontScale
	if self.chromeKey == key then return end
	self.chromeKey = key

	local isBlizzard = look == "blizzard"
	f.title:SetShown(not isBlizzard)
	f.header:SetShown(isBlizzard)
	if f.SetBackdropColor then
		f:SetBackdropColor(0, 0, 0, isBlizzard and 0 or 0.35)
	end

	f.scroll:ClearAllPoints()
	if isBlizzard then
		f.header:SetPoint("TOPLEFT")
		f.header:SetPoint("TOPRIGHT")
		f.header:SetHeight(ns:Scale(BLIZZ_HEADER_HEIGHT))
		f.scroll:SetPoint("TOPLEFT", f.header, "BOTTOMLEFT", 0, -ns:Scale(BLIZZ_HEADER_GAP))
		f.scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -BLIZZ_RIGHT_PADDING, PADDING)
	else
		f.scroll:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4)
		f.scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PADDING, PADDING)
	end
end

-- Collapses every zone, or expands them all if they're all collapsed already.
function Tracker:ToggleAllZones()
	local zones = self.zones or {}
	local collapse = not self:AllZonesCollapsed()
	for _, zone in ipairs(zones) do
		ns.db.collapsed[zone.name] = collapse or nil
	end
	self:Layout()
end

function Tracker:AllZonesCollapsed()
	local zones = self.zones or {}
	for _, zone in ipairs(zones) do
		if not ns.db.collapsed[zone.name] then return false end
	end
	return #zones > 0
end

function Tracker:SavePosition()
	local point, _, relPoint, x, y = self.frame:GetPoint()
	ns.db.point = { point, "UIParent", relPoint, x, y }
end

function Tracker:RestorePosition()
	local f = self.frame
	if not f then return end
	local p = ns.db.point
	f:ClearAllPoints()
	f:SetPoint(p[1], _G[p[2]] or UIParent, p[3], p[4], p[5])
end

function Tracker:RestoreSize()
	if not self.frame or InCombatLockdown() then return end
	self.frame:SetSize(ns.db.width, ns.db.height)
end

function Tracker:ApplyWidth()
	if not self.frame or InCombatLockdown() then return end
	self.frame:SetWidth(ns.db.width)
end

function Tracker:Toggle()
	if not self.frame then return end
	if InCombatLockdown() then
		ns:Print("Can't show or hide the tracker in combat.")
		return
	end
	self.frame:SetShown(not self.frame:IsShown())
	self:UpdateItemButtons()
end

function Tracker:UpdateItemButtons()
	if self.frame and self.itemEntries then
		ns.ItemButtons:Update(self.frame, self.itemEntries)
	end
end

function Tracker:Refresh()
	if not self.frame then return end
	self.zones = ns.Data:GetZones()
	self:Layout()
end

-- QuestieLike look ------------------------------------------------------------
-- Compact rows: zone headers, "[level] title" quest rows and "- objective" lines,
-- with quest item buttons on the left.

-- Each look's layout returns the content width and height and the item button
-- entries (see ItemButtons:Update).

local function LayoutQuestie(f, zones)
	local content = f.content
	local width = f:GetWidth() - PADDING * 2
	local y = 0

	local zoneHeight, questHeight, objectiveHeight = ns:Scale(ZONE_HEIGHT), ns:Scale(QUEST_HEIGHT), ns:Scale(OBJECTIVE_HEIGHT)
	local questIndent, objectiveIndent = ns:Scale(QUEST_INDENT), ns:Scale(OBJECTIVE_INDENT)
	local itemSize, itemGap = ns:Scale(ITEM_SIZE), ns:Scale(ITEM_GAP)

	local totalQuests = 0
	local focusedQuestID = C_SuperTrack.GetSuperTrackedQuestID()
	-- topInset: distance from the top of the frame to the top of the scroll area
	-- (matches the title/scroll anchors in ApplyChrome).
	local itemEntries = {
		size = itemSize,
		topInset = PADDING + f.title:GetStringHeight() + 4,
		leftInset = PADDING + questIndent,
	}

	for _, zone in ipairs(zones) do
		totalQuests = totalQuests + #zone.quests
		local collapsed = ns.db.collapsed[zone.name]

		local zr = AcquireZoneRow(content)
		zr.zoneName = zone.name
		zr:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
		zr:SetSize(width, zoneHeight)
		zr.bg:Hide()
		zr.toggle:Hide()
		zr.toggleHighlight:Hide()
		zr.text:ClearAllPoints()
		zr.text:SetPoint("LEFT")
		zr.text:SetTextColor(1, 1, 1) -- white so zone headers stand out from quests
		zr.text:SetFormattedText("%s %s |cff888888(%d)|r", collapsed and "+" or "-", zone.name, #zone.quests)
		y = y + zoneHeight

		if not collapsed then
			for _, quest in ipairs(zone.quests) do
				local qr = AcquireQuestRow(content)
				qr.questID = quest.questID
				qr.quest = quest
				qr:SetPoint("TOPLEFT", content, "TOPLEFT", questIndent, -y)
				qr:SetSize(width - questIndent, questHeight)
				qr.poi:Hide()

				-- Shift the quest's text right to make room for its item button.
				local itemIndent = quest.item and (itemSize + itemGap) or 0
				local blockTop = y
				qr.text:ClearAllPoints()
				qr.text:SetPoint("LEFT", qr, "LEFT", itemIndent, 0)
				qr.text:SetPoint("RIGHT")
				qr.text:SetWordWrap(false)
				-- Focus highlight starts at the quest name, after any item button.
				qr.focusBg:SetPoint("TOPLEFT", qr, "TOPLEFT", itemIndent - 4, 0)
				if quest.item then
					itemEntries[#itemEntries + 1] = { quest = quest, y = y }
				end

				local suffix = ""
				if quest.isFailed then
					suffix = " |cffff2020(Failed)|r"
				elseif quest.isComplete then
					suffix = " |cff20ff20(Complete)|r"
				end
				local elite = quest.isElite and "+" or ""
				local party = #quest.partyMembers > 0 and (" |cff66ccff(+%d)|r"):format(#quest.partyMembers) or ""
				local isFocused = quest.questID == focusedQuestID
				qr.focusBg:SetShown(isFocused)
				qr.focusBar:SetShown(isFocused)
				qr.text:SetFormattedText("[%d%s] %s%s%s", quest.level, elite, quest.title, party, suffix)
				qr.text:SetTextColor(LevelColor(quest.level))
				y = y + questHeight

				if not quest.isComplete then
					for _, obj in ipairs(quest.objectives) do
						if obj.text and obj.text ~= "" then
							local fs = AcquireObjectiveRow(content).text
							local indent = questIndent + math.max(objectiveIndent, itemIndent)
							fs:ClearAllPoints()
							fs:SetPoint("TOPLEFT", content, "TOPLEFT", indent, -y)
							fs:SetWidth(width - indent)
							fs:SetWordWrap(false)
							fs:SetText("- " .. obj.text)
							if obj.finished then
								fs:SetTextColor(0.5, 0.5, 0.5)
							else
								fs:SetTextColor(0.9, 0.9, 0.9)
							end
							y = y + objectiveHeight
						end
					end
				end
				-- Make sure the item button doesn't overlap the next quest.
				if quest.item then
					y = math.max(y, blockTop + itemSize)
				end
				y = y + (quest.item and ITEM_QUEST_SPACING or QUEST_SPACING)
			end
		end
		y = y + ZONE_SPACING
	end

	f.title:SetFormattedText("Quests |cff888888(%d)|r", totalQuests)
	return width, y, itemEntries
end

-- Default look ----------------------------------------------------------------
-- Blizzard's objective tracker: header bars, quest POI bubbles, wrapped
-- objective lines with check marks and item buttons on the right, plus our
-- collapsible zone groups.

-- Sets a font string's text at the given width and returns its height.
local function SetWrappedText(fs, text, width, maxLines)
	fs:SetWidth(width)
	fs:SetWordWrap(true)
	if fs.SetMaxLines then fs:SetMaxLines(maxLines or 0) end
	fs:SetText(text)
	return math.max(fs:GetStringHeight(), ns:Scale(BLIZZ_MIN_LINE_HEIGHT))
end

local function UpdatePOI(poi, quest, isFocused)
	local size = ns:Scale(BLIZZ_POI_SIZE)
	poi:SetSize(size, size)
	SetAtlasScaled(poi.bg, isFocused and "UI-QuestPoi-QuestNumber-SuperTracked" or "UI-QuestPoi-QuestNumber")
	SetAtlasScaled(poi.highlight, "UI-QuestPoi-InnerGlow")
	if quest.isComplete then
		SetAtlasScaled(poi.icon, "UI-QuestIcon-TurnIn-Normal")
	else
		SetAtlasScaled(poi.icon, isFocused and "Quest-In-Progress-Icon-Brown" or "Quest-In-Progress-Icon-yellow")
	end
	poi:Show()
end

local function LayoutBlizzard(f, zones)
	local content = f.content
	local width = f:GetWidth() - BLIZZ_RIGHT_PADDING
	local y = 0

	local zoneHeight = ns:Scale(BLIZZ_ZONE_HEIGHT)
	local blockX = ns:Scale(BLIZZ_BLOCK_X)
	local lineSpacing = ns:Scale(BLIZZ_LINE_SPACING)
	local itemSize = ns:Scale(BLIZZ_ITEM_SIZE)
	local itemBorder = ns:Scale(BLIZZ_ITEM_BORDER)
	local checkSize = ns:Scale(BLIZZ_CHECK_SIZE)
	local focusedQuestID = C_SuperTrack.GetSuperTrackedQuestID()
	local itemEntries = {
		size = itemSize,
		topInset = ns:Scale(BLIZZ_HEADER_HEIGHT) + ns:Scale(BLIZZ_HEADER_GAP),
		leftInset = 0,
	}

	-- Top header button collapses or expands every zone.
	local toggle = f.header.toggle
	local allCollapsed = Tracker:AllZonesCollapsed()
	local state = allCollapsed and "expand" or "collapse"
	toggle:SetNormalAtlas("ui-questtrackerbutton-" .. state .. "-all")
	toggle:SetPushedAtlas("ui-questtrackerbutton-" .. state .. "-all-pressed")
	toggle:SetHighlightAtlas("ui-questtrackerbutton-red-highlight", "ADD")
	toggle:SetSize(ns:Scale(18), ns:Scale(19))

	for _, zone in ipairs(zones) do
		local collapsed = ns.db.collapsed[zone.name]

		local zr = AcquireZoneRow(content)
		zr.zoneName = zone.name
		zr:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
		zr:SetSize(width, zoneHeight)
		zr.bg:Show()
		SetAtlasScaled(zr.toggle, collapsed and "ui-questtrackerbutton-secondary-expand" or "ui-questtrackerbutton-secondary-collapse")
		SetAtlasScaled(zr.toggleHighlight, "ui-questtrackerbutton-yellow-highlight")
		zr.toggle:Show()
		zr.toggleHighlight:Show()
		zr.text:ClearAllPoints()
		zr.text:SetPoint("LEFT", ns:Scale(BLIZZ_ZONE_TEXT_X), 0)
		zr.text:SetPoint("RIGHT", zr.toggle, "LEFT", -4, 0)
		zr.text:SetWordWrap(false)
		zr.text:SetTextColor(unpack(BLIZZ_HEADER_COLOR))
		zr.text:SetFormattedText("%s |cffb0b0b0(%d)|r", zone.name, #zone.quests)
		y = y + zoneHeight

		if not collapsed then
			y = y + ns:Scale(BLIZZ_HEADER_TO_BLOCK)
			for i, quest in ipairs(zone.quests) do
				local isFocused = quest.questID == focusedQuestID
				local blockTop = y
				local blockWidth = width - blockX
				-- Lines stop short of the item button, as in Blizzard's tracker.
				local textWidth = blockWidth
				if quest.item then
					textWidth = blockWidth - itemSize - itemBorder * 2
					itemEntries[#itemEntries + 1] = { quest = quest, y = y, x = width - itemSize - itemBorder }
				end

				local qr = AcquireQuestRow(content)
				qr.questID = quest.questID
				qr.quest = quest
				qr.focusBg:Hide()
				qr.focusBar:Hide()
				qr.text:ClearAllPoints()
				qr.text:SetPoint("TOPLEFT")
				local elite = quest.isElite and "+" or ""
				local party = #quest.partyMembers > 0 and (" |cff66ccff(+%d)|r"):format(#quest.partyMembers) or ""
				local title = ("[%d%s] %s%s"):format(quest.level, elite, quest.title, party)
				local titleHeight = SetWrappedText(qr.text, title, textWidth, 2)
				qr.text:SetTextColor(LevelColor(quest.level))
				qr:SetPoint("TOPLEFT", content, "TOPLEFT", blockX, -y)
				qr:SetSize(textWidth, titleHeight)
				qr.poi:ClearAllPoints()
				qr.poi:SetPoint("TOPRIGHT", qr, "TOPLEFT", ns:Scale(BLIZZ_POI_X), ns:Scale(BLIZZ_POI_Y))
				UpdatePOI(qr.poi, quest, isFocused)
				y = y + titleHeight

				-- text: line text; color: {r, g, b}; dash: "dash", "check" or nil
				local function AddLine(text, color, dash)
					local line = AcquireObjectiveRow(content)
					y = y + lineSpacing
					line.dash:ClearAllPoints()
					line.dash:SetPoint("TOPLEFT", content, "TOPLEFT", blockX, -y + 1)
					local dashWidth = line.dash:GetStringWidth()
					line.dash:SetTextColor(unpack(BLIZZ_OBJECTIVE_COLOR))
					line.dash:SetShown(dash == "dash")
					if dash == "check" then
						line.check:ClearAllPoints()
						line.check:SetPoint("TOPLEFT", line.dash, "TOPLEFT", ns:Scale(BLIZZ_CHECK_X), ns:Scale(BLIZZ_CHECK_Y))
						line.check:SetSize(checkSize, checkSize)
						line.check:Show()
					end
					line.text:ClearAllPoints()
					line.text:SetPoint("TOPLEFT", content, "TOPLEFT", blockX + dashWidth, -y)
					line.text:SetTextColor(unpack(color))
					y = y + SetWrappedText(line.text, text, textWidth - dashWidth)
				end

				if quest.isFailed then
					AddLine(FAILED or "Failed", { DIM_RED_FONT_COLOR:GetRGB() })
				elseif quest.isComplete then
					local completionText = GetQuestLogCompletionText and GetQuestLogCompletionText(quest.logIndex)
					if completionText and completionText ~= "" then
						AddLine(completionText, BLIZZ_OBJECTIVE_COLOR)
					else
						AddLine(QUEST_WATCH_QUEST_READY or "Ready for turn-in", BLIZZ_COMPLETE_COLOR)
					end
				else
					for _, obj in ipairs(quest.objectives) do
						if obj.text and obj.text ~= "" then
							if obj.finished then
								AddLine(obj.text, BLIZZ_COMPLETE_COLOR, "check")
							else
								AddLine(obj.text, BLIZZ_OBJECTIVE_COLOR, "dash")
							end
						end
					end
				end

				-- Make sure the item button doesn't overlap the next quest.
				if quest.item then
					y = math.max(y, blockTop + itemSize + itemBorder)
				end
				if i < #zone.quests then
					y = y + ns:Scale(BLIZZ_BLOCK_SPACING)
				end
			end
		end
		y = y + ns:Scale(BLIZZ_ZONE_SPACING)
	end

	return width, y, itemEntries
end

local LAYOUTS = { questie = LayoutQuestie, blizzard = LayoutBlizzard }

function Tracker:Layout()
	local f = self.frame
	if not f or not self.zones then return end

	local look = ns:GetStyle().look
	self:ApplyChrome(look)
	ReleaseAll()
	local width, height, itemEntries = LAYOUTS[look](f, self.zones)
	f.content:SetSize(width, math.max(height, 1))

	-- Keep the scroll offset valid when content shrinks or the window grows.
	local scroll = f.scroll
	scroll:UpdateScrollChildRect()
	if scroll:GetVerticalScroll() > scroll:GetVerticalScrollRange() then
		scroll:SetVerticalScroll(scroll:GetVerticalScrollRange())
	end

	self.itemEntries = itemEntries
	self:UpdateItemButtons()
end
