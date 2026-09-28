local _, ns = ...

-- Clickable quest item buttons shown next to a quest (where depends on the
-- style), spanning the quest name row and the row below it.
--
-- Using a quest item is a protected action, so these are secure action
-- buttons. Secure frames can't be shown, hidden, moved or reconfigured in
-- combat, and anything they are parented or anchored to becomes restricted
-- too. To keep the tracker's own rows free to update in combat, the buttons
-- are parented to UIParent and anchored to the tracker frame by offset, and
-- all changes are deferred until combat ends.
local ItemButtons = {}
ns.ItemButtons = ItemButtons

-- Blizzard's quest item frame art is 42px around a 26px button.
local BORDER_ATLAS = "UI-QuestTrackerButton-QuestItem-Frame"
local BORDER_SCALE = 42 / 26

local buttons = {}
local pending = false
local lastFrame, lastEntries

local function UpdateCooldown(button)
	if not button.logIndex then return end
	local start, duration, enable = GetQuestLogSpecialItemCooldown(button.logIndex)
	if start then
		CooldownFrame_Set(button.cooldown, start, duration, enable)
	end
end

local function CreateButton(index)
	local button = CreateFrame("Button", "EnhancedQuestTrackerItem" .. index, UIParent,
		"SecureActionButtonTemplate")
	button:RegisterForClicks("AnyUp", "AnyDown")
	button:SetAttribute("type", "item")

	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetAllPoints()
	button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(BORDER_ATLAS) then
		button.border = button:CreateTexture(nil, "OVERLAY")
		button.border:SetAtlas(BORDER_ATLAS)
		button.border:SetPoint("CENTER")
	else
		-- Fallback: a plain 1px dark outline.
		button.outline = CreateFrame("Frame", nil, button, "BackdropTemplate")
		button.outline:SetPoint("TOPLEFT", -1, 1)
		button.outline:SetPoint("BOTTOMRIGHT", 1, -1)
		button.outline:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
		button.outline:SetBackdropBorderColor(0, 0, 0, 1)
	end

	button.count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	button.count:SetPoint("BOTTOMRIGHT", 2, -1)
	ns:RegisterText(button.count)

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
	buttons[index] = button
	return button
end

-- entries: list of { quest = quest, y = offset of the quest row from the top of
-- the scroll content, x = optional offset from its left }, plus layout fields:
-- size (button size), topInset and leftInset (offset of the scroll content from
-- the frame's top-left).
function ItemButtons:Update(frame, entries)
	lastFrame, lastEntries = frame, entries
	if InCombatLockdown() then
		pending = true
		return
	end
	pending = false

	local scroll = frame.scroll
	local scrollOffset = scroll:GetVerticalScroll()
	local viewHeight = scroll:GetHeight()
	local topInset = entries.topInset or 0
	local leftInset = entries.leftInset or 0
	local size = entries.size

	local shown = 0
	for _, entry in ipairs(entries) do
		local rowTop = entry.y - scrollOffset
		-- Skip rows scrolled out of view rather than drawing over the frame edges.
		if frame:IsShown() and rowTop >= 0 and rowTop + size <= viewHeight then
			shown = shown + 1
			local button = buttons[shown] or CreateButton(shown)
			local item = entry.quest.item

			button.logIndex = entry.quest.logIndex
			button:SetAttribute("item", item.link)
			button.icon:SetTexture(item.texture)
			button.count:SetText(item.charges and item.charges > 1 and item.charges or "")
			UpdateCooldown(button)

			button:SetFrameStrata(frame:GetFrameStrata())
			button:SetFrameLevel(frame:GetFrameLevel() + 20)
			button:SetSize(size, size)
			if button.border then
				button.border:SetSize(size * BORDER_SCALE, size * BORDER_SCALE)
			end
			button:ClearAllPoints()
			button:SetPoint("TOPLEFT", frame, "TOPLEFT", leftInset + (entry.x or 0), -(topInset + rowTop))
			button:Show()
		end
	end

	for i = shown + 1, #buttons do
		buttons[i]:Hide()
		buttons[i].logIndex = nil
	end
end

function ItemButtons:OnCombatEnded()
	if pending and lastFrame then
		self:Update(lastFrame, lastEntries)
	end
end

function ItemButtons:UpdateCooldowns()
	for _, button in ipairs(buttons) do
		if button:IsShown() then UpdateCooldown(button) end
	end
end
