local _, ns = ...

-- A second tracker window for tracked profession recipes, listing each
-- recipe's required reagents and how many the player has. Forever's default
-- tracker shows these as a Professions section; here they get their own
-- window, hidden while no recipes are tracked. It follows the quest tracker's
-- style, font size, background and width, and fits its height to its contents.
local RecipeTracker = {}
ns.RecipeTracker = RecipeTracker

local PADDING = 8
-- QuestieLike look, for 100% font size (scaled with ns:Scale).
local RECIPE_HEIGHT = 16
local REAGENT_HEIGHT = 14
local REAGENT_INDENT = 14
local RECIPE_SPACING = 2

-- Default look: Blizzard's objective tracker module settings and art.
local BLIZZ_HEADER_ATLAS = "ui-questtracker-primary-objective-header"
local BLIZZ_HEADER_HEIGHT = 32
local BLIZZ_HEADER_TEXT_X = 7
local BLIZZ_HEADER_TO_BLOCK = 10 -- fromHeaderOffsetY
local BLIZZ_BLOCK_X = 20 -- blockOffsetX
local BLIZZ_BLOCK_SPACING = 10 -- fromBlockOffsetY
local BLIZZ_LINE_SPACING = 4
local BLIZZ_MIN_LINE_HEIGHT = 12
local BLIZZ_CHECK_SIZE = 16
local BLIZZ_CHECK_X, BLIZZ_CHECK_Y = -10, 2 -- check mark's top-left, from the dash's
local BLIZZ_RIGHT_PADDING = 8
-- Blizzard's OBJECTIVE_TRACKER_COLOR values.
local BLIZZ_REAGENT_COLOR = { 0.8, 0.8, 0.8 }
local BLIZZ_COMPLETE_COLOR = { 0.6, 0.6, 0.6 }
local BLIZZ_HEADER_COLOR = { 1, 0.82, 0 }

local HEADER_TEXT = PROFESSIONS_TRACKER_HEADER_PROFESSION or "Professions"

local recipeRows, reagentLines = {}, {} -- reagent lines are { text, dash, check }
local used = { recipe = 0, reagent = 0 }

local function CanMove()
	return not ns.db.locked or IsShiftKeyDown()
end

-- The window fits its contents, so the title and recipe rows cover nearly all
-- of it; dragging them moves the window too (a drag doesn't also click).
local function EnableDragToMove(frame)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function()
		if CanMove() then RecipeTracker.frame:StartMoving() end
	end)
	frame:SetScript("OnDragStop", function()
		RecipeTracker.frame:StopMovingOrSizing()
		RecipeTracker:SavePosition()
	end)
end

local function SetAtlasScaled(texture, atlas)
	texture:SetAtlas(atlas, true)
	local w, h = texture:GetSize()
	texture:SetSize(ns:Scale(w), ns:Scale(h))
end

local function GetRecipeLink(recipeID)
	if C_TradeSkillUI.GetRecipeLink then
		return C_TradeSkillUI.GetRecipeLink(recipeID)
	end
	return C_Spell.GetSpellLink(recipeID)
end

-- Inserts the recipe link into an open chat edit box. Returns false if the
-- player isn't typing in chat.
local function InsertRecipeLink(recipeID)
	local link = GetRecipeLink(recipeID)
	if not link then return false end
	if ChatFrameUtil and ChatFrameUtil.InsertLink then
		return ChatFrameUtil.InsertLink(link)
	elseif ChatEdit_InsertLink then
		return ChatEdit_InsertLink(link)
	end
	return false
end

local function Untrack(recipe)
	C_TradeSkillUI.SetRecipeTracked(recipe.recipeID, false, recipe.isRecraft)
	ns:RequestRefresh()
end

-- Opens the recipe in the professions window, or inspects it when the player
-- doesn't have the profession (as the default tracker).
local function OpenRecipe(recipe)
	if recipe.isRecraft then return end
	if not ProfessionsFrame and ProfessionsFrame_LoadUI then
		ProfessionsFrame_LoadUI()
	end
	if C_TradeSkillUI.IsRecipeProfessionLearned(recipe.recipeID) then
		C_TradeSkillUI.OpenRecipe(recipe.recipeID)
	elseif Professions and Professions.InspectRecipe then
		Professions.InspectRecipe(recipe.recipeID)
	end
end

local function ShowRecipeMenu(owner, recipe)
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle(recipe.name)
		local spellBank = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
		if not recipe.isRecraft and C_SpellBook.IsSpellInSpellBook(recipe.recipeID, spellBank, false) then
			root:CreateButton(PROFESSIONS_TRACKING_VIEW_RECIPE or "View Recipe", function() OpenRecipe(recipe) end)
		end
		root:CreateButton(PROFESSIONS_UNTRACK_RECIPE or "Untrack Recipe", function() Untrack(recipe) end)
	end)
end

-- Row pools --------------------------------------------------------------------

local function AcquireRecipeRow(parent)
	used.recipe = used.recipe + 1
	local row = recipeRows[used.recipe]
	if not row then
		row = CreateFrame("Button", nil, parent)
		row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		row.text:SetJustifyH("LEFT")
		ns:RegisterText(row.text)

		-- Faint highlight behind the whole recipe while the mouse is over it.
		row.hoverBg = row:CreateTexture(nil, "HIGHLIGHT")
		row.hoverBg:SetPoint("BOTTOMRIGHT")
		row.hoverBg:SetColorTexture(1, 1, 1, 0.08)

		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		row:SetScript("OnClick", function(self, button)
			if button == "RightButton" then
				ShowRecipeMenu(self, self.recipe)
			elseif IsShiftKeyDown() then
				if not InsertRecipeLink(self.recipe.recipeID) then
					Untrack(self.recipe)
				end
			else
				OpenRecipe(self.recipe)
			end
		end)
		EnableDragToMove(row)
		recipeRows[used.recipe] = row
	end
	row:Show()
	return row
end

local function AcquireReagentLine(parent)
	used.reagent = used.reagent + 1
	local line = reagentLines[used.reagent]
	if not line then
		line = {}
		line.text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		line.text:SetJustifyH("LEFT")
		ns:RegisterText(line.text, { blizzard = 12 })
		-- Default look: separate dash so wrapped lines indent past it, and a check
		-- mark in its place once the player has enough.
		line.dash = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		line.dash:SetText(QUEST_DASH or "- ")
		ns:RegisterText(line.dash, { blizzard = 12 })
		line.check = parent:CreateTexture(nil, "ARTWORK")
		line.check:SetAtlas("ui-questtracker-tracker-check")
		reagentLines[used.reagent] = line
	end
	line.text:Show()
	line.dash:Hide()
	line.check:Hide()
	return line
end

local function ReleaseAll()
	for _, row in ipairs(recipeRows) do row:Hide() end
	for _, line in ipairs(reagentLines) do
		line.text:Hide()
		line.dash:Hide()
		line.check:Hide()
	end
	used.recipe, used.reagent = 0, 0
end

-- Frame -------------------------------------------------------------------------

local function ToggleCollapsed()
	ns.db.recipesCollapsed = not ns.db.recipesCollapsed
	RecipeTracker:Layout()
end

function RecipeTracker:Init()
	local f = CreateFrame("Frame", "EnhancedQuestTrackerRecipeFrame", UIParent, "BackdropTemplate")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	EnableDragToMove(f)
	if f.SetBackdrop then
		f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
	end

	-- QuestieLike title; click to collapse or expand.
	f.title = CreateFrame("Button", nil, f)
	f.title:SetPoint("TOPLEFT", PADDING, -PADDING)
	f.title.text = f.title:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.title.text:SetPoint("LEFT")
	ns:RegisterText(f.title.text)
	f.title:SetScript("OnClick", ToggleCollapsed)
	EnableDragToMove(f.title)

	-- Default look title: header bar with a collapse/expand button.
	f.header = CreateFrame("Frame", nil, f)
	f.header.bg = f.header:CreateTexture(nil, "BACKGROUND")
	f.header.bg:SetAllPoints()
	f.header.bg:SetAtlas(BLIZZ_HEADER_ATLAS)
	f.header.text = f.header:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	f.header.text:SetPoint("LEFT", BLIZZ_HEADER_TEXT_X, 0)
	f.header.text:SetText(HEADER_TEXT)
	f.header.text:SetTextColor(unpack(BLIZZ_HEADER_COLOR))
	ns:RegisterText(f.header.text, { blizzard = 14 })
	f.header.toggle = CreateFrame("Button", nil, f.header)
	f.header.toggle:SetPoint("RIGHT", -1, 0)
	f.header.toggle:SetScript("OnClick", ToggleCollapsed)

	f.content = CreateFrame("Frame", nil, f)

	f:Hide()
	self.frame = f
	self:ApplyWidth()
	self:ApplyBackground()
	self:RestorePosition()
end

function RecipeTracker:SavePosition()
	local point, _, relPoint, x, y = self.frame:GetPoint()
	ns.db.recipePoint = { point, "UIParent", relPoint, x, y }
end

function RecipeTracker:RestorePosition()
	local f = self.frame
	if not f then return end
	local p = ns.db.recipePoint
	f:ClearAllPoints()
	f:SetPoint(p[1], _G[p[2]] or UIParent, p[3], p[4], p[5])
end

function RecipeTracker:ApplyWidth()
	if not self.frame then return end
	self.frame:SetWidth(ns.db.width)
	self:Layout()
end

function RecipeTracker:ApplyBackground()
	local f = self.frame
	if f and f.SetBackdropColor then
		f:SetBackdropColor(0, 0, 0, ns.db.bgOpacity / 100)
	end
end

function RecipeTracker:Refresh()
	if not self.frame then return end
	self.recipes = ns.RecipeData:GetRecipes()
	self:Layout()
end

-- QuestieLike look --------------------------------------------------------------
-- Each look's layout returns the height of the whole frame.

local function LayoutQuestie(f, recipes)
	local content = f.content
	local width = f:GetWidth() - PADDING * 2
	local recipeHeight, reagentHeight = ns:Scale(RECIPE_HEIGHT), ns:Scale(REAGENT_HEIGHT)
	local reagentIndent = ns:Scale(REAGENT_INDENT)
	local collapsed = ns.db.recipesCollapsed

	f.title:Show()
	f.header:Hide()
	f.title.text:SetFormattedText("%s %s |cff888888(%d)|r", collapsed and "+" or "-", HEADER_TEXT, #recipes)
	f.title:SetSize(f.title.text:GetStringWidth(), f.title.text:GetStringHeight())
	content:ClearAllPoints()
	content:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4)
	content:SetWidth(width)

	local y = 0
	if not collapsed then
		for _, recipe in ipairs(recipes) do
			local row = AcquireRecipeRow(content)
			row.recipe = recipe
			row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
			row:SetWidth(width)
			row.text:ClearAllPoints()
			row.text:SetPoint("LEFT", row, "TOPLEFT", 0, -recipeHeight / 2)
			row.text:SetPoint("RIGHT", row, "TOPRIGHT", 0, -recipeHeight / 2)
			row.text:SetWordWrap(false)
			row.text:SetText(recipe.name)
			row.text:SetTextColor(1, 0.82, 0)
			row.hoverBg:SetPoint("TOPLEFT", -4, 0)
			local blockTop = y
			y = y + recipeHeight

			for _, reagent in ipairs(recipe.reagents) do
				local fs = AcquireReagentLine(content).text
				fs:ClearAllPoints()
				fs:SetPoint("TOPLEFT", content, "TOPLEFT", reagentIndent, -y)
				fs:SetWidth(width - reagentIndent)
				fs:SetWordWrap(false)
				fs:SetText("- " .. reagent.text)
				if reagent.finished then
					fs:SetTextColor(0.5, 0.5, 0.5)
				else
					fs:SetTextColor(0.9, 0.9, 0.9)
				end
				y = y + reagentHeight
			end
			-- Stretch the row over the reagents so hover and clicks cover the whole recipe.
			row:SetHeight(y - blockTop)
			y = y + RECIPE_SPACING
		end
	end

	return PADDING + f.title:GetHeight() + 4 + y + PADDING
end

-- Default look ------------------------------------------------------------------
-- Blizzard's Professions tracker section: header bar, recipe names and reagent
-- lines with check marks once the player has enough.

local function SetWrappedText(fs, text, width)
	fs:SetWidth(width)
	fs:SetWordWrap(true)
	if fs.SetMaxLines then fs:SetMaxLines(0) end
	fs:SetText(text)
	return math.max(fs:GetStringHeight(), ns:Scale(BLIZZ_MIN_LINE_HEIGHT))
end

local function LayoutBlizzard(f, recipes)
	local content = f.content
	local width = f:GetWidth() - BLIZZ_RIGHT_PADDING
	local headerHeight = ns:Scale(BLIZZ_HEADER_HEIGHT)
	local blockX = ns:Scale(BLIZZ_BLOCK_X)
	local textWidth = width - blockX
	local lineSpacing = ns:Scale(BLIZZ_LINE_SPACING)
	local checkSize = ns:Scale(BLIZZ_CHECK_SIZE)
	local collapsed = ns.db.recipesCollapsed

	f.title:Hide()
	f.header:Show()
	f.header:ClearAllPoints()
	f.header:SetPoint("TOPLEFT")
	f.header:SetPoint("TOPRIGHT")
	f.header:SetHeight(headerHeight)
	local toggle = f.header.toggle
	local state = collapsed and "expand" or "collapse"
	toggle:SetNormalAtlas("ui-questtrackerbutton-secondary-" .. state)
	toggle:SetHighlightAtlas("ui-questtrackerbutton-yellow-highlight", "ADD")
	toggle:SetSize(ns:Scale(18), ns:Scale(19))
	content:ClearAllPoints()
	content:SetPoint("TOPLEFT", f.header, "BOTTOMLEFT", 0, -ns:Scale(BLIZZ_HEADER_TO_BLOCK))
	content:SetWidth(width)

	if collapsed then return headerHeight end

	local y = 0
	for i, recipe in ipairs(recipes) do
		local blockTop = y
		local row = AcquireRecipeRow(content)
		row.recipe = recipe
		row:SetPoint("TOPLEFT", content, "TOPLEFT", blockX, -y)
		row:SetWidth(textWidth)
		row.text:ClearAllPoints()
		row.text:SetPoint("TOPLEFT")
		row.text:SetTextColor(unpack(BLIZZ_HEADER_COLOR))
		row.hoverBg:SetPoint("TOPLEFT", -2, 0)
		y = y + SetWrappedText(row.text, recipe.name, textWidth)

		for _, reagent in ipairs(recipe.reagents) do
			local line = AcquireReagentLine(content)
			y = y + lineSpacing
			line.dash:ClearAllPoints()
			line.dash:SetPoint("TOPLEFT", content, "TOPLEFT", blockX, -y + 1)
			line.dash:SetTextColor(unpack(BLIZZ_REAGENT_COLOR))
			local dashWidth = line.dash:GetStringWidth()
			-- The default tracker swaps the dash for a check mark once there's enough.
			if reagent.finished then
				line.check:ClearAllPoints()
				line.check:SetPoint("TOPLEFT", line.dash, "TOPLEFT", ns:Scale(BLIZZ_CHECK_X), ns:Scale(BLIZZ_CHECK_Y))
				line.check:SetSize(checkSize, checkSize)
				line.check:Show()
			else
				line.dash:Show()
			end
			line.text:ClearAllPoints()
			line.text:SetPoint("TOPLEFT", content, "TOPLEFT", blockX + dashWidth, -y)
			line.text:SetTextColor(unpack(reagent.finished and BLIZZ_COMPLETE_COLOR or BLIZZ_REAGENT_COLOR))
			y = y + SetWrappedText(line.text, reagent.text, textWidth - dashWidth)
		end
		row:SetHeight(y - blockTop)
		if i < #recipes then
			y = y + ns:Scale(BLIZZ_BLOCK_SPACING)
		end
	end

	return headerHeight + ns:Scale(BLIZZ_HEADER_TO_BLOCK) + y + PADDING
end

local LAYOUTS = { questie = LayoutQuestie, blizzard = LayoutBlizzard }

function RecipeTracker:Layout()
	local f = self.frame
	if not f or not self.recipes then return end

	-- Hidden while nothing is tracked, and along with the quest tracker.
	local questFrame = ns.Tracker.frame
	local shown = #self.recipes > 0 and (not questFrame or questFrame:IsShown())
	f:SetShown(shown)
	ReleaseAll()
	if not shown then return end

	local height = LAYOUTS[ns:GetStyle().look](f, self.recipes)
	f.content:SetHeight(1)
	f:SetHeight(height)
end
