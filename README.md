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
src/Announce.lua                 Party chat message when a quest becomes complete
src/ItemButtons.lua              Secure buttons for usable quest items
src/Tracker.lua                  Tracker frame, collapsible zone headers, quest/objective rows
src/Options.lua                  Options > AddOns settings panel
```

## Install

Symlink (or copy) this folder into `World of Warcraft/_forever_/Interface/AddOns/EnhancedQuestTracker`.

## Slash commands

`/eqt` toggle · `/eqt options` · `/eqt lock` · `/eqt blizz` (toggle hiding Blizzard's tracker) · `/eqt announce` (toggle party completion messages) · `/eqt expand` · `/eqt reset` (position and size)

Party: a blue `(+N)` after a quest shows how many party members also have it; hover the quest to see their progress.

Quest items: quests with a usable item show a button at the right of the quest name; click it to use the item. It disappears once the quest is complete. The buttons only update outside combat.

Quest clicks: left-click opens the quest, Shift-click untracks (or links it if you are typing in chat), right-click opens a menu with Focus, Untrack, Share Quest, Share In Chat and Abandon.

Style: Options > AddOns > Enhanced Quest Tracker has a Style dropdown to change how the tracker looks. "Default" looks like Blizzard's quest tracker (header bars, quest map icons you can click to focus a quest, check marks on finished objectives, item buttons on the right) but keeps the zone groups; click a zone's bar to collapse it, or the button on the top bar to collapse or expand every zone. "QuestieLike - High Contrast" outlines all tracker text so it's easier to read over the game world.

Font size: Options > AddOns > Enhanced Quest Tracker has a Font Size slider (70–150%); row spacing and quest item buttons scale with it.

Drag the grip in the bottom-right corner to resize; scroll with the mouse wheel when the list is taller than the window.
