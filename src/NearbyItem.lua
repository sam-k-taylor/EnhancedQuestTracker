local _, ns = ...

-- A single quest item button that appears when you're near a quest objective
-- whose item you can use: the item's target is in range, or you're standing in
-- the quest's objective area on the map. Hidden the rest of the time. It can be
-- moved in Edit Mode, where a placeholder shows where it sits.
--
-- Using a quest item is a protected action, so this is a secure action button.
-- Like the tracker's item buttons (see ItemButtons.lua), it can't be shown,
-- hidden or changed in combat; it keeps whatever it had and catches up when
-- combat ends.
local NearbyItem = {}
ns.NearbyItem = NearbyItem

local LABEL = "Nearby Quest Item"
local SIZE = 40
local UPDATE_INTERVAL = 0.25
local PLACEHOLDER_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
-- Blizzard's quest item frame art is 42px around a 26px button.
local BORDER_ATLAS = "UI-QuestTrackerButton-QuestItem-Frame"
local BORDER_SCALE = 42 / 26
local OUT_OF_RANGE_COLOR = { 1, 0.3, 0.3 }

-- Edit Mode's selection box (EditModeSystemSelectionLayout in
-- Blizzard_EditMode, which isn't global).
local SELECTION_LAYOUT = {
	["TopRightCorner"] = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = 8, y = 8 },
	["TopLeftCorner"] = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = -8, y = 8 },
	["BottomLeftCorner"] = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = -8, y = -8 },
	["BottomRightCorner"] = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = 8, y = -8 },
	["TopEdge"] = { atlas = "_%s-NineSlice-EdgeTop" },
	["BottomEdge"] = { atlas = "_%s-NineSlice-EdgeBottom" },
	["LeftEdge"] = { atlas = "!%s-NineSlice-EdgeLeft" },
	["RightEdge"] = { atlas = "!%s-NineSlice-EdgeRight" },
	["Center"] = { atlas = "%s-NineSlice-Center", x = -8, y = 8, x1 = 8, y1 = -8 },
}
local HIGHLIGHT_KIT = "editmode-actionbar-highlight"
local SELECTED_KIT = "editmode-actionbar-selected"

local holder, button, overlay, driver
local candidates = {} -- quests with a usable item (see Refresh)
local shownKey -- what the button is set up for, so ticks only change it when needed
local editMode = false
local pending = false -- a change waiting for combat to end

local function IsEnabled()
	return ns.db and ns.db.nearbyItemButton
end

-- The quest to show: one whose item target is in range beats one whose
-- objective area you're in; ties go to the closest quest.
local function PickQuest()
	local best, bestScore, bestDist
	for _, quest in ipairs(candidates) do
		local score
		if IsQuestLogSpecialItemInRange(quest.logIndex) == 1 then
			score = 2
		elseif C_Minimap and C_Minimap.IsInsideQuestBlob and C_Minimap.IsInsideQuestBlob(quest.questID) then
			score = 1
		end
		if score then
			local dist = C_QuestLog.GetDistanceSqToQuest and C_QuestLog.GetDistanceSqToQuest(quest.questID) or math.huge
			if not best or score > bestScore or (score == bestScore and dist < bestDist) then
				best, bestScore, bestDist = quest, score, dist
			end
		end
	end
	return best
end

local function UpdateCooldown()
	if not button.logIndex then return end
	local start, duration, enable = GetQuestLogSpecialItemCooldown(button.logIndex)
	if start then
		CooldownFrame_Set(button.cooldown, start, duration, enable)
	end
end

-- Tints the icon red when the item has a target that's out of range.
local function UpdateRange()
	if not button.logIndex then return end
	if IsQuestLogSpecialItemInRange(button.logIndex) == 0 then
		button.icon:SetVertexColor(unpack(OUT_OF_RANGE_COLOR))
	else
		button.icon:SetVertexColor(1, 1, 1)
	end
end

-- Sets the button up for quest (nil hides it). Deferred in combat.
local function ShowQuest(quest)
	local key = quest and (quest.questID .. ":" .. quest.link .. ":" .. (quest.charges or 0)) or nil
	if key == shownKey then
		UpdateRange()
		return
	end
	if InCombatLockdown() then
		pending = true
		return
	end
	shownKey = key

	if not quest then
		button:Hide()
		button.logIndex = nil
		return
	end
	button.logIndex = quest.logIndex
	button:SetAttribute("item", quest.link)
	button.icon:SetTexture(quest.texture)
	button.count:SetText(quest.charges and quest.charges > 1 and quest.charges or "")
	UpdateCooldown()
	UpdateRange()
	button:Show()
end

local function Update()
	if not button then return end
	if editMode or not IsEnabled() then
		ShowQuest(nil)
	else
		ShowQuest(PickQuest())
	end
end

-- Range and objective areas change as you move, so check them a few times a
-- second while there's anything that could be shown.
local function UpdateDriver()
	local active = IsEnabled() and not editMode and #candidates > 0
	driver:SetScript("OnUpdate", active and function(self, elapsed)
		self.elapsed = (self.elapsed or 0) + elapsed
		if self.elapsed < UPDATE_INTERVAL then return end
		self.elapsed = 0
		Update()
	end or nil)
end

-- Edit Mode -------------------------------------------------------------------

local function ApplySelection(kit)
	if NineSliceUtil and overlay.kit ~= kit then
		NineSliceUtil.ApplyLayout(overlay, SELECTION_LAYOUT, kit)
		overlay.kit = kit
	end
end

local function CreateOverlay()
	overlay = CreateFrame("Frame", nil, holder)
	overlay:SetAllPoints()
	overlay:SetFrameStrata("MEDIUM")
	overlay:SetFrameLevel(1000)
	overlay:EnableMouse(true)
	overlay:RegisterForDrag("LeftButton")
	overlay:Hide()

	overlay.icon = overlay:CreateTexture(nil, "ARTWORK")
	overlay.icon:SetAllPoints()
	overlay.icon:SetTexture(PLACEHOLDER_ICON)
	overlay.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	overlay.icon:SetAlpha(0.6)

	overlay.label = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	overlay.label:SetPoint("TOP", overlay, "BOTTOM", 0, -10)
	overlay.label:SetText(LABEL)
	overlay.label:Hide()

	ApplySelection(HIGHLIGHT_KIT)

	overlay:SetScript("OnEnter", function(self)
		ApplySelection(SELECTED_KIT)
		self.label:Show()
		GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
		GameTooltip:SetText(LABEL)
		GameTooltip:AddLine("Shows the item of a quest whose objective you're near. Drag to move.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	overlay:SetScript("OnLeave", function(self)
		if not self.moving then
			ApplySelection(HIGHLIGHT_KIT)
			self.label:Hide()
		end
		GameTooltip_Hide()
	end)
	overlay:SetScript("OnDragStart", function(self)
		if InCombatLockdown() then return end
		self.moving = true
		GameTooltip_Hide()
		holder:StartMoving()
	end)
	overlay:SetScript("OnDragStop", function(self)
		self.moving = false
		holder:StopMovingOrSizing()
		NearbyItem:SavePosition()
		if not self:IsMouseOver() then
			ApplySelection(HIGHLIGHT_KIT)
			self.label:Hide()
		end
	end)
end

function NearbyItem:SetEditMode(active)
	editMode = active
	if not holder then return end
	ApplySelection(HIGHLIGHT_KIT)
	overlay.label:Hide()
	overlay:SetShown(active and IsEnabled())
	Update()
	UpdateDriver()
end

-- Frame -----------------------------------------------------------------------

function NearbyItem:Init()
	-- The secure button is anchored to this plain frame, which only moves in
	-- Edit Mode (never in combat).
	holder = CreateFrame("Frame", "EnhancedQuestTrackerNearbyItemHolder", UIParent)
	holder:SetSize(SIZE, SIZE)
	holder:SetMovable(true)
	holder:SetClampedToScreen(true)
	self:RestorePosition()

	button = CreateFrame("Button", "EnhancedQuestTrackerNearbyItem", UIParent, "SecureActionButtonTemplate")
	button:SetAllPoints(holder)
	button:RegisterForClicks("AnyUp", "AnyDown")
	button:SetAttribute("type", "item")
	button:SetFrameStrata("MEDIUM")

	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetAllPoints()
	button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(BORDER_ATLAS) then
		button.border = button:CreateTexture(nil, "OVERLAY")
		button.border:SetAtlas(BORDER_ATLAS)
		button.border:SetPoint("CENTER")
		button.border:SetSize(SIZE * BORDER_SCALE, SIZE * BORDER_SCALE)
	end

	button.count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	button.count:SetPoint("BOTTOMRIGHT", -2, 2)

	button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	button.cooldown:SetAllPoints()

	button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	button:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")

	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetQuestLogSpecialItem(self.logIndex)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	button:Hide()

	driver = CreateFrame("Frame")
	CreateOverlay()

	if EventRegistry then
		EventRegistry:RegisterCallback("EditMode.Enter", function() NearbyItem:SetEditMode(true) end, NearbyItem)
		EventRegistry:RegisterCallback("EditMode.Exit", function() NearbyItem:SetEditMode(false) end, NearbyItem)
	end
	if EditModeManagerFrame and EditModeManagerFrame.IsEditModeActive and EditModeManagerFrame:IsEditModeActive() then
		self:SetEditMode(true)
	end
end

function NearbyItem:SavePosition()
	local point, _, relPoint, x, y = holder:GetPoint()
	ns.db.nearbyItemPoint = { point, "UIParent", relPoint, x, y }
end

function NearbyItem:RestorePosition()
	if not holder or InCombatLockdown() then return end
	local p = ns.db.nearbyItemPoint
	holder:ClearAllPoints()
	holder:SetPoint(p[1], _G[p[2]] or UIParent, p[3], p[4], p[5])
end

-- Rebuilds the list of quests with a usable item. Every quest in the log
-- counts, tracked or not.
function NearbyItem:Refresh()
	if not button then return end
	wipe(candidates)
	if IsEnabled() then
		for i = 1, C_QuestLog.GetNumQuestLogEntries() do
			local info = C_QuestLog.GetInfo(i)
			if info and not info.isHeader and not info.isHidden then
				local questID = info.questID
				-- Like the tracker, hide the item once the quest is complete.
				if not (C_QuestLog.IsComplete(questID) or C_QuestLog.ReadyForTurnIn(questID)) then
					local link, texture, charges = GetQuestLogSpecialItemInfo(i)
					if link then
						candidates[#candidates + 1] = {
							questID = questID, logIndex = i, link = link, texture = texture, charges = charges,
						}
					end
				end
			end
		end
	end
	-- Log indexes may have shifted, so set the button up again.
	shownKey = false
	Update()
	UpdateDriver()
end

-- Called when the option is toggled.
function NearbyItem:ApplyEnabled()
	if not holder then return end
	overlay:SetShown(editMode and IsEnabled())
	self:Refresh()
end

function NearbyItem:OnCombatEnded()
	if pending then
		pending = false
		shownKey = false
		Update()
	end
end

function NearbyItem:UpdateCooldowns()
	if button and button:IsShown() then UpdateCooldown() end
end
