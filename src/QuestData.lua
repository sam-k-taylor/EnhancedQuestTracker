local _, ns = ...

-- Reads the tracked (watched) quests from the quest log into a list of zones,
-- each holding its quests sorted by level ascending. Zones are sorted by name.
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

local function BuildQuest(info)
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
		objectives = C_QuestLog.GetQuestObjectives(questID) or {},
		partyMembers = GetPartyMembersOnQuest(questID),
	}
end

function Data:GetZones()
	local zones, byName = {}, {}
	local current

	local numEntries = C_QuestLog.GetNumQuestLogEntries()
	for i = 1, numEntries do
		local info = C_QuestLog.GetInfo(i)
		if info then
			if info.isHeader then
				current = byName[info.title]
				if not current then
					current = { name = info.title, quests = {} }
					byName[info.title] = current
					zones[#zones + 1] = current
				end
			elseif current and not info.isHidden and C_QuestLog.GetQuestWatchType(info.questID) then
				table.insert(current.quests, BuildQuest(info))
			end
		end
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
	table.sort(result, function(a, b) return a.name < b.name end)
	return result
end
