local _, ns = ...

-- Sets a TomTom waypoint to a quest, when the TomTom addon is loaded. TomTom is
-- an optional dependency in the .toc, so it's loaded before us if installed.
local Waypoint = {}
ns.TomTom = Waypoint

-- The waypoint we last set, replaced by the next one, its quest and where it
-- points.
local currentUid, currentQuestID, currentMapID, currentX, currentY

function Waypoint:IsAvailable()
	return TomTom ~= nil and TomTom.AddWaypoint ~= nil
end

-- Whether the tracker should show waypoint buttons.
function Waypoint:IsEnabled()
	return self:IsAvailable() and ns.db.tomtomButton
end

-- Finds where to send the player for a quest: the next waypoint (which routes
-- to another zone if needed), else the quest's POI on the player's map or one
-- of its parent maps.
local function FindQuestLocation(questID)
	local mapID, x, y = C_QuestLog.GetNextWaypoint(questID)
	if mapID and x and y then return mapID, x, y end

	local map = C_Map.GetBestMapForUnit("player")
	while map and map ~= 0 do
		for _, info in ipairs(C_QuestLog.GetQuestsOnMap(map) or {}) do
			if info.questID == questID and info.x and info.y then
				return map, info.x, info.y
			end
		end
		local mapInfo = C_Map.GetMapInfo(map)
		map = mapInfo and mapInfo.parentMapID
	end
end

-- Whether a waypoint can be set for the quest; the tracker hides the button
-- otherwise.
function Waypoint:HasLocation(questID)
	return FindQuestLocation(questID) ~= nil
end

-- Whether our current waypoint is for this quest (and still exists in TomTom).
function Waypoint:IsActiveFor(questID)
	if not (currentUid and currentQuestID == questID) then return false end
	return not TomTom.IsValidWaypoint or TomTom:IsValidWaypoint(currentUid)
end

local function ForgetWaypoint()
	currentUid, currentQuestID = nil, nil
	ns.Tracker:Layout()
end

-- Removes our waypoint from TomTom without relaying out the tracker. Our state
-- is cleared first so the RemoveWaypoint hook below ignores it.
local function RemoveCurrent()
	local uid = currentUid
	currentUid, currentQuestID = nil, nil
	if uid then TomTom:RemoveWaypoint(uid) end
end

local function AddWaypoint(questID, mapID, x, y)
	currentUid = TomTom:AddWaypoint(mapID, x, y, {
		title = C_QuestLog.GetTitleForQuestID(questID),
		from = "Enhanced Quest Tracker",
		persistent = false,
		crazy = true, -- point TomTom's arrow at it
	})
	currentQuestID = currentUid and questID
	currentMapID, currentX, currentY = mapID, x, y
end

function Waypoint:Clear()
	RemoveCurrent()
	ns.Tracker:Layout()
end

function Waypoint:SetForQuest(questID)
	local mapID, x, y = FindQuestLocation(questID)
	if not mapID then return end
	RemoveCurrent()
	AddWaypoint(questID, mapID, x, y)
	ns.Tracker:Layout()
end

-- Keeps our waypoint in step with its quest, called on quest log changes
-- before the tracker refreshes: removes it once the quest has left the log
-- (handed in or abandoned), and moves it when the quest's location changes
-- (an objective was completed, or the quest is ready to hand in).
function Waypoint:Update()
	if not (self:IsAvailable() and self:IsActiveFor(currentQuestID)) then return end
	local questID = currentQuestID
	if not C_QuestLog.GetLogIndexForQuestID(questID) then
		RemoveCurrent()
		return
	end
	-- Keep the old waypoint if the new location isn't known (yet); a later
	-- QUEST_POI_UPDATE will move it.
	local mapID, x, y = FindQuestLocation(questID)
	if not mapID or (mapID == currentMapID and x == currentX and y == currentY) then return end
	RemoveCurrent()
	AddWaypoint(questID, mapID, x, y)
end

-- The quest's waypoint button: sets a waypoint, or cancels it if already set.
-- Setting one also focuses (super tracks) the quest, so the game's own quest
-- tracking points the same way.
function Waypoint:Toggle(questID)
	if not self:IsAvailable() then return end
	if self:IsActiveFor(questID) then
		self:Clear()
	elseif self:HasLocation(questID) then
		-- Focus first, so SUPER_TRACKING_CHANGED doesn't cancel the new waypoint.
		C_SuperTrack.SetSuperTrackedQuestID(questID)
		self:SetForQuest(questID)
	end
end

-- Cancels our waypoint when its quest stops being focused (another quest was
-- focused, or the quest was unfocused).
function Waypoint:OnSuperTrackingChanged()
	if not (self:IsAvailable() and self:IsActiveFor(currentQuestID)) then return end
	if C_SuperTrack.GetSuperTrackedQuestID() ~= currentQuestID then
		self:Clear()
	end
end

-- Switch the button back when the waypoint goes away in TomTom itself (reached,
-- or removed from TomTom's arrow or map).
if Waypoint:IsAvailable() then
	hooksecurefunc(TomTom, "RemoveWaypoint", function(_, uid)
		if uid and uid == currentUid then ForgetWaypoint() end
	end)
	if TomTom.ClearAllWaypoints then
		hooksecurefunc(TomTom, "ClearAllWaypoints", function()
			if currentUid then ForgetWaypoint() end
		end)
	end
end
