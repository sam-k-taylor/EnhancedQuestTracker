local _, ns = ...

-- Reads the tracked (watched) quests from the quest log into a list of zones,
-- each holding its quests sorted by level ascending. Zones are sorted by name,
-- optionally with the player's current zone first.
-- With zone grouping off, all quests go in one group that has no name.
local Data = {}
ns.Data = Data

local function CompareQuests(a, b)
	if a.level ~= b.level then
		return a.level < b.level
	end
	return a.title < b.title
end

-- Names of party members (not raid) who also have this quest.
local function GetPartyMembersOnQuest(questID)
	local names = {}
	if IsInGroup() and not IsInRaid() then
		for i = 1, GetNumSubgroupMembers() do
			local unit = "party" .. i
			if UnitExists(unit) and C_QuestLog.IsUnitOnQuest(unit, questID) then
				names[#names + 1] = UnitName(unit)
			end
		end
	end
	return names
end

-- Classic tags elite quests as "Group" (shown as "Elite" in the quest log).
local ELITE_TAG = Enum and Enum.QuestTag and Enum.QuestTag.Group or 1

local function IsEliteQuest(questID)
	local tag = C_QuestLog.GetQuestTagInfo(questID)
	return tag ~= nil and (tag.isElite or tag.tagID == ELITE_TAG)
end

-- The usable quest item for this log entry, if any. Hidden once the quest is
-- complete.
local function GetQuestItem(logIndex, isComplete)
	if isComplete then return nil end
	local link, texture, charges = GetQuestLogSpecialItemInfo(logIndex)
	if not link then return nil end
	return { link = link, texture = texture, charges = charges }
end

-- Seconds left on each timed quest, keyed by questID. Read the same way as
-- forever's Blizzard quest timer frame (its tracker's timer bar is turned off).
local function GetQuestTimers()
	local timers = {}
	if C_QuestLog.GetQuestTimers then
		for _, info in ipairs(C_QuestLog.GetQuestTimers() or {}) do
			timers[info.questID] = info.questTimer
		end
	end
	return timers
end

-- The quest's timer as { duration, endTime } (endTime in GetTime() seconds),
-- or nil if it isn't timed or has run out. duration is nil when the quest's
-- total time isn't known.
local function GetQuestTimer(questID, timeLeft)
	local total, elapsed
	if C_QuestLog.GetTimeAllowed then
		total, elapsed = C_QuestLog.GetTimeAllowed(questID)
	end
	if not timeLeft and total and elapsed then
		timeLeft = total - elapsed
	end
	if not timeLeft or timeLeft <= 0 then return nil end
	return { duration = total and total > 0 and total or nil, endTime = GetTime() + timeLeft }
end

local function BuildQuest(info, timers)
	local questID = info.questID
	local isComplete = C_QuestLog.IsComplete(questID) or C_QuestLog.ReadyForTurnIn(questID)
	return {
		questID = questID,
		logIndex = info.questLogIndex,
		title = info.title,
		level = info.level or 0,
		isElite = IsEliteQuest(questID),
		isComplete = isComplete,
		item = GetQuestItem(info.questLogIndex, isComplete),
		isFailed = C_QuestLog.IsFailed(questID),
		timer = GetQuestTimer(questID, timers[questID]),
		objectives = C_QuestLog.GetQuestObjectives(questID) or {},
		partyMembers = GetPartyMembersOnQuest(questID),
		-- Looked up here rather than in the layout so resizing doesn't repeat it.
		hasWaypoint = ns.TomTom:IsEnabled() and ns.TomTom:HasLocation(questID),
	}
end

local MICRO_MAP = Enum and Enum.UIMapType and Enum.UIMapType.Micro or 5

-- The name of the zone the player is in. GetRealZoneText gives the building
-- when indoors (e.g. "Lakeshire Inn"), so use the player's map instead, going
-- up from building maps to their zone.
local function GetCurrentZoneName()
	local mapID = C_Map.GetBestMapForUnit("player")
	local info = mapID and C_Map.GetMapInfo(mapID)
	while info and info.mapType == MICRO_MAP and info.parentMapID and info.parentMapID ~= 0 do
		info = C_Map.GetMapInfo(info.parentMapID)
	end
	return info and info.name or GetRealZoneText()
end

function Data:GetZones()
	local zones, byName = {}, {}
	local current
	local timers = GetQuestTimers()

	local numEntries = C_QuestLog.GetNumQuestLogEntries()
	for i = 1, numEntries do
		local info = C_QuestLog.GetInfo(i)
		if info then
			if info.isHeader then
				current = byName[info.title]
				if not current then
					current = { name = info.title, key = info.title, quests = {} }
					byName[info.title] = current
					zones[#zones + 1] = current
				end
			elseif current and not info.isHidden and C_QuestLog.GetQuestWatchType(info.questID) then
				table.insert(current.quests, BuildQuest(info, timers))
			end
		end
	end

	if not ns.db.groupByZone then
		-- key is what collapse state is saved under (zone names for zone groups).
		local all = { key = "*all*", quests = {} }
		for _, zone in ipairs(zones) do
			for _, quest in ipairs(zone.quests) do
				all.quests[#all.quests + 1] = quest
			end
		end
		table.sort(all.quests, CompareQuests)
		return #all.quests > 0 and { all } or {}
	end

	local result = {}
	for _, zone in ipairs(zones) do
		if #zone.quests > 0 then
			table.sort(zone.quests, CompareQuests)
			result[#result + 1] = zone
		end
	end
	-- The quest log's header order shifts (e.g. opening the map moves the current
	-- zone to the top), so sort zones ourselves to keep the tracker stable.
	-- Quest log headers are zone names, so the player's zone matches by name.
	local currentZone = ns.db.currentZoneFirst and GetCurrentZoneName()
	table.sort(result, function(a, b)
		if currentZone and (a.name == currentZone) ~= (b.name == currentZone) then
			return a.name == currentZone
		end
		return a.name < b.name
	end)
	return result
end

-- Rewards ---------------------------------------------------------------------

-- Reads an item reward via GetQuestLogRewardInfo / GetQuestLogChoiceInfo.
-- name is nil until the item's data has loaded; pending then lists its itemID.
local function ReadItem(queryFunction, index, pending)
	local name, texture, count, quality, _, itemID = queryFunction(index)
	if not name and itemID then
		pending[#pending + 1] = itemID
	end
	return { name = name, texture = texture, count = count or 1, quality = quality }
end

local function ReadCurrency(info)
	return { name = info.name, texture = info.texture, count = info.totalRewardAmount or 0, quality = info.quality }
end

-- The quest's rewards, or nil if it has none (or they aren't shown):
-- { xp, money, items = {}, choices = {}, pending = { itemID, ... } }
-- items and choices hold { name, texture, count, quality }.
function Data:GetRewards(questID)
	if C_QuestLog.ShouldShowQuestRewards and not C_QuestLog.ShouldShowQuestRewards(questID) then
		return nil
	end

	-- The quest log reward functions read the selected quest.
	local selected = C_QuestLog.GetSelectedQuest()
	C_QuestLog.SetSelectedQuest(questID)

	local rewards = { items = {}, choices = {}, pending = {} }
	rewards.xp = GetQuestLogRewardXP and GetQuestLogRewardXP() or 0
	rewards.money = GetQuestLogRewardMoney() or 0

	for i = 1, GetNumQuestLogRewards() do
		rewards.items[#rewards.items + 1] = ReadItem(GetQuestLogRewardInfo, i, rewards.pending)
	end
	if C_QuestInfoSystem and C_QuestInfoSystem.GetQuestRewardCurrencies then
		for _, info in ipairs(C_QuestInfoSystem.GetQuestRewardCurrencies(questID) or {}) do
			if not info.isChoice then
				rewards.items[#rewards.items + 1] = ReadCurrency(info)
			end
		end
	end

	for i = 1, GetNumQuestLogChoices(questID, true) do
		-- Loot type 1 is a currency choice; anything else is an item.
		local isCurrency = GetQuestLogChoiceInfoLootType and GetQuestLogChoiceInfoLootType(i) == 1
		if isCurrency then
			local info = C_QuestLog.GetQuestRewardCurrencyInfo(questID, i, true)
			if info then
				rewards.choices[#rewards.choices + 1] = ReadCurrency(info)
			end
		else
			rewards.choices[#rewards.choices + 1] = ReadItem(GetQuestLogChoiceInfo, i, rewards.pending)
		end
	end

	C_QuestLog.SetSelectedQuest(selected or 0)

	if rewards.xp == 0 and rewards.money == 0 and #rewards.items == 0 and #rewards.choices == 0 then
		return nil
	end
	return rewards
end
