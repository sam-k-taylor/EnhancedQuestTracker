# Enhanced Quest Tracker

Goal is to create a questie style quest tracker UI element.

Core Features
- Collapsable Sections by quest zone
- Quests ordered by quest level ascending

## Layout

```
EnhancedQuestTracker.toc         Addon manifest (Interface 16001 = WoW Forever 1.60.1)
src/Core.lua                     Namespace, saved variables, events, slash commands
src/QuestData.lua                Reads C_QuestLog into zones -> quests (sorted by level)
src/Announce.lua                 Party chat messages for accepted/completed quests, auto-sharing
src/TomTom.lua                   Optional TomTom waypoints to quest locations
src/ItemButtons.lua              Secure buttons for usable quest items
src/Tracker.lua                  Tracker frame, collapsible zone headers, quest/objective rows
src/Options.lua                  Options > AddOns settings panel
```

## Install

Symlink (or copy) this folder into `World of Warcraft/_forever_/Interface/AddOns/EnhancedQuestTracker`.

## Slash commands

`/eqt` toggle · `/eqt options` · `/eqt lock` · `/eqt blizz` (toggle hiding Blizzard's tracker) · `/eqt announce` (toggle party completion messages) · `/eqt announceaccept` (toggle party accepted messages) · `/eqt share` (toggle auto-sharing accepted quests) · `/eqt expand` · `/eqt reset` (position and size)

Party: a blue `(+N)` after a quest shows how many party members also have it; hover the quest to see their progress.

Quest items: quests with a usable item show a button at the right of the quest name; click it to use the item. It disappears once the quest is complete. The buttons only update outside combat.

Quest clicks: left-click opens the quest, Shift-click untracks (or links it if you are typing in chat), right-click opens a menu with Focus, Untrack, Share Quest, Share In Chat and Abandon.

Style: Options > AddOns > Enhanced Quest Tracker has a Style dropdown to change how the tracker looks. "Default" looks like Blizzard's quest tracker (header bars, quest map icons you can click to focus a quest, check marks on finished objectives, item buttons on the right) but keeps the zone groups; click a zone's bar to collapse it, or the button on the top bar to collapse or expand every zone. "QuestieLike - High Contrast" outlines all tracker text so it's easier to read over the game world.

Options: Options > AddOns > Enhanced Quest Tracker has two sections.
- Display Options: Lock Tracker, Hide Blizzard Quest Tracker, Style, Font Size (70–150%; row spacing and quest item buttons scale with it), Background Opacity (0–100%, default 0%), Tracker Width, Show Quest Rewards on Mouse Over (off by default; rewards come from `Data:GetRewards` and are added below party progress in the quest tooltip), and Show TomTom Waypoint Buttons (only registered when TomTom is loaded).
- Party Options (party only, not raids): Announce Completed Quests (on by default), Announce Accepted Quests and Auto Share Accepted Quests (both off by default).

Party announcements and sharing: completed quests are detected by `Announce:Scan` on quest log updates; accepted quests come from `QUEST_ACCEPTED`. Auto share skips quests that were shared with you, detected in `QUEST_DETAIL` by the quest giver being a player.

TomTom: `TomTom` is an `OptionalDeps` in the .toc so it loads first. With TomTom loaded, quests with a known location get a map button at the right of the quest name that sets a TomTom waypoint (and points the arrow) to the quest; while it's set the button shows a red X that removes it. `RemoveWaypoint`/`ClearAllWaypoints` are hooked so the button resets when TomTom removes the waypoint itself (e.g. on arrival). The location comes from `C_QuestLog.GetNextWaypoint`, falling back to the quest's POI in `C_QuestLog.GetQuestsOnMap` for the player's map and its parents. Quests without a location have no button; `QUEST_POI_UPDATE` refreshes the tracker when location data loads. `Waypoint:Update` runs on each debounced refresh: it moves the waypoint when the quest's location changes (an objective updates or it becomes ready to hand in) and removes it once the quest leaves the log (handed in or abandoned). Setting a waypoint also focuses the quest (`C_SuperTrack.SetSuperTrackedQuestID`); on `SUPER_TRACKING_CHANGED`, the waypoint is cancelled if its quest is no longer focused. Cancelling the waypoint leaves the focus alone.

Drag the grip in the bottom-right corner to resize; scroll with the mouse wheel when the list is taller than the window.
