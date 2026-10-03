local _, ns = ...

-- Announces to party chat when a quest is accepted or becomes ready to turn in.
local Announce = {}
ns.Announce = Announce

-- [questID] = true/false (complete or not) as of the last scan.
local lastState = {}

local function SendPartyMessage(msg)
	if C_ChatInfo and C_ChatInfo.SendChatMessage then
		C_ChatInfo.SendChatMessage(msg, "PARTY")
	else
		SendChatMessage(msg, "PARTY")
	end
end

local function InParty()
	return IsInGroup() and not IsInRaid()
end

local function ShouldAnnounce()
	return ns.db.announceParty and InParty()
end

-- Quest IDs offered to us by another player. A shared quest opens the quest
-- details window with the sharing player as the quest giver.
local sharedWithUs = {}

function Announce:OnQuestDetail()
	local questID = GetQuestID()
	if questID and questID ~= 0 then
		-- Overwrite any earlier offer, e.g. a declined share now taken from the NPC.
		sharedWithUs[questID] = (UnitIsPlayer("questnpc") or UnitIsPlayer("npc")) or nil
	end
end

local function ShareQuest(questID, retried)
	if not C_QuestLog.GetLogIndexForQuestID(questID) then
		-- The quest may not be in the log yet when QUEST_ACCEPTED fires.
		if not retried then
			C_Timer.After(0.5, function() ShareQuest(questID, true) end)
		end
		return
	end
	if C_QuestLog.IsPushableQuest(questID) then
		QuestUtil.ShareQuest(questID)
	end
end

function Announce:OnQuestAccepted(questID)
	if not questID then return end
	local wasShared = sharedWithUs[questID]
	sharedWithUs[questID] = nil
	if not InParty() then return end
	-- Only share quests we picked up ourselves, not ones shared with us.
	if ns.db.autoShare and not wasShared then
		ShareQuest(questID)
	end
	if not ns.db.announceAccepted then return end
	local link = GetQuestLink and GetQuestLink(questID)
	local title = link or C_QuestLog.GetTitleForQuestID(questID)
	if title then
		SendPartyMessage(("Quest accepted: %s"):format(title))
	end
end

function Announce:Scan()
	local state = {}
	for i = 1, C_QuestLog.GetNumQuestLogEntries() do
		local info = C_QuestLog.GetInfo(i)
		if info and not info.isHeader then
			local questID = info.questID
			local complete = C_QuestLog.IsComplete(questID) or C_QuestLog.ReadyForTurnIn(questID) or false
			state[questID] = complete
			-- Only announce a transition we saw happen; quests that are new to the
			-- log (or seen for the first time after login) have no previous state.
			if complete and lastState[questID] == false and ShouldAnnounce() then
				local link = GetQuestLink and GetQuestLink(questID)
				SendPartyMessage(("Quest complete: %s"):format(link or info.title))
			end
		end
	end
	lastState = state
end
