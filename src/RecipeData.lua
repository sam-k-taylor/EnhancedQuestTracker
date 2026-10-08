local _, ns = ...

-- Reads the tracked profession recipes and how many of each required reagent
-- the player has. Mirrors forever's Blizzard_ProfessionsRecipeTracker, using
-- the same ProfessionsUtil helpers so the counts match the default tracker.
local RecipeData = {}
ns.RecipeData = RecipeData

local IS_RECRAFT = true

-- Item names that weren't cached yet; a refresh is requested once each loads.
local loading = {}

local function GetItemName(itemID)
	local name = C_Item.GetItemNameByID(itemID)
	if not name and not loading[itemID] then
		loading[itemID] = true
		Item:CreateFromItemID(itemID):ContinueOnItemLoad(function()
			loading[itemID] = nil
			ns:RequestRefresh()
		end)
	end
	return name
end

function RecipeData:IsAvailable()
	return C_TradeSkillUI and C_TradeSkillUI.GetRecipesTracked and ProfessionsUtil ~= nil
end

-- Required slots, with modifying reagent slots first (as the default tracker).
local function GetRequiredSlots(schematic)
	local slots = {}
	for slotIndex, slot in ipairs(schematic.reagentSlotSchematics) do
		if ProfessionsUtil.IsReagentSlotRequired(slot) then
			if ProfessionsUtil.IsReagentSlotModifyingRequired(slot) then
				table.insert(slots, 1, slot)
			else
				table.insert(slots, slot)
			end
		end
	end
	return slots
end

-- { text, finished } for a required reagent slot, or nil while its name loads.
local function GetReagentLine(slot)
	local reagent = slot.reagents[1]
	local name
	if ProfessionsUtil.IsReagentSlotBasicRequired(slot) then
		if reagent.itemID then
			name = GetItemName(reagent.itemID)
		elseif reagent.currencyID then
			local info = C_CurrencyInfo.GetCurrencyInfo(reagent.currencyID)
			name = info and info.name
		end
	elseif ProfessionsUtil.IsReagentSlotModifyingRequired(slot) and slot.slotInfo then
		name = slot.slotInfo.slotText
	end
	if not name then return nil end

	local format = PROFESSIONS_TRACKER_REAGENT_FORMAT or "%s %s"
	if slot:IsVariableQuantityReagent(reagent) then
		local min, max = slot:GetVariableQuantityRange(reagent)
		local range = (PROFESSIONS_TRACKER_REAGENT_RANGE_FORMAT or "%d-%d"):format(min, max)
		return { text = format:format(range, name), finished = false }
	end
	local required = slot:GetQuantityRequired(reagent)
	local have = ProfessionsUtil.AccumulateReagentsInPossession(slot.reagents)
	local count = (PROFESSIONS_TRACKER_REAGENT_COUNT_FORMAT or "%d/%d"):format(have, required)
	return { text = format:format(count, name), finished = have >= required }
end

local function ReadRecipe(recipeID, isRecraft)
	local schematic = ProfessionsUtil.GetRecipeSchematic(recipeID, isRecraft)
	if not schematic then return nil end
	local name = schematic.name
	if isRecraft then
		name = (PROFESSIONS_CRAFTING_FORM_RECRAFTING_HEADER or "Recraft: %s"):format(name)
	end
	local recipe = { recipeID = recipeID, isRecraft = isRecraft, name = name, reagents = {} }
	for _, slot in ipairs(GetRequiredSlots(schematic)) do
		local line = GetReagentLine(slot)
		if line then
			recipe.reagents[#recipe.reagents + 1] = line
		end
	end
	return recipe
end

-- Recrafts first, then regular recipes, each in tracking order (as the default
-- tracker).
function RecipeData:GetRecipes()
	local recipes = {}
	if not self:IsAvailable() then return recipes end
	for _, isRecraft in ipairs({ IS_RECRAFT, not IS_RECRAFT }) do
		for _, recipeID in ipairs(C_TradeSkillUI.GetRecipesTracked(isRecraft) or {}) do
			local recipe = ReadRecipe(recipeID, isRecraft)
			if recipe then
				recipes[#recipes + 1] = recipe
			end
		end
	end
	return recipes
end
