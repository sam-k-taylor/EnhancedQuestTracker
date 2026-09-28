local _, ns = ...

-- Announces to party chat when a quest in the log becomes ready to turn in.
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

local function ShouldAnnounce()
	return ns.db.announceParty and IsInGroup() and not IsInRaid()
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
