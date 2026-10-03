local addonName, ns = ...

-- Options panel under Options > AddOns, built on the Settings API.
local Options = {}
ns.Options = Options

local TITLE = "Enhanced Quest Tracker"

local function AddCheckbox(category, key, name, tooltip, onChanged)
	local setting = Settings.RegisterAddOnSetting(category, addonName .. "_" .. key, key, ns.db,
		Settings.VarType.Boolean, name, ns.defaults[key])
	if onChanged then
		setting:SetValueChangedCallback(onChanged)
	end
	Settings.CreateCheckbox(category, setting, tooltip)
end

function Options:Init()
	local category, layout = Settings.RegisterVerticalLayoutCategory(TITLE)
	self.category = category

	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Display Options"))

	AddCheckbox(category, "locked", "Lock Tracker",
		"Prevent the tracker from being moved or resized. Hold Shift to move or resize it anyway.")

	AddCheckbox(category, "hideBlizzardTracker", "Hide Blizzard Quest Tracker",
		"Hide the default objective tracker while this addon is enabled.",
		function() ns:UpdateBlizzardTracker() end)

	local styleSetting = Settings.RegisterAddOnSetting(category, addonName .. "_style", "style", ns.db,
		Settings.VarType.String, "Style", ns.defaults.style)
	styleSetting:SetValueChangedCallback(function()
		ns:UpdateTextStyle()
		ns.Tracker:Layout()
	end)
	local function GetStyleOptions()
		local container = Settings.CreateControlTextContainer()
		for _, style in ipairs(ns.styles) do
			container:Add(style.key, style.name)
		end
		return container:GetData()
	end
	Settings.CreateDropdown(category, styleSetting, GetStyleOptions,
		"Visual style of the tracker. Default looks like Blizzard's quest tracker; High Contrast outlines all tracker text so it's easier to read over the game world.")

	local fontSetting = Settings.RegisterAddOnSetting(category, addonName .. "_fontScale", "fontScale", ns.db,
		Settings.VarType.Number, "Font Size", ns.defaults.fontScale)
	fontSetting:SetValueChangedCallback(function()
		ns:UpdateTextStyle()
		ns.Tracker:Layout()
	end)
	local fontOptions = Settings.CreateSliderOptions(70, 150, 5)
	if MinimalSliderWithSteppersMixin then
		fontOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
			return value .. "%"
		end)
	end
	Settings.CreateSlider(category, fontSetting, fontOptions, "Size of the tracker text, as a percentage of the default.")

	local bgSetting = Settings.RegisterAddOnSetting(category, addonName .. "_bgOpacity", "bgOpacity", ns.db,
		Settings.VarType.Number, "Background Opacity", ns.defaults.bgOpacity)
	bgSetting:SetValueChangedCallback(function() ns.Tracker:ApplyBackground() end)
	local bgOptions = Settings.CreateSliderOptions(0, 100, 5)
	if MinimalSliderWithSteppersMixin then
		bgOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
			return value .. "%"
		end)
	end
	Settings.CreateSlider(category, bgSetting, bgOptions, "Opacity of the tracker's background. 0% is fully transparent.")

	local widthSetting = Settings.RegisterAddOnSetting(category, addonName .. "_width", "width", ns.db,
		Settings.VarType.Number, "Tracker Width", ns.defaults.width)
	widthSetting:SetValueChangedCallback(function() ns.Tracker:ApplyWidth() end)
	local widthOptions = Settings.CreateSliderOptions(180, 600, 10)
	if MinimalSliderWithSteppersMixin then
		widthOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
	end
	Settings.CreateSlider(category, widthSetting, widthOptions, "Width of the tracker in pixels.")

	if ns.TomTom:IsAvailable() then
		AddCheckbox(category, "tomtomButton", "Show TomTom Waypoint Buttons",
			"Show a button next to each quest that sets a TomTom waypoint to it. Quests without a known location have no button.",
			function() ns:RequestRefresh() end)
	end

	-- Party Options: these only apply while in a party (not a raid).
	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Party Options"))

	AddCheckbox(category, "announceParty", "Announce Completed Quests",
		"When in a party, post a message in party chat when a quest's objectives are complete.")

	AddCheckbox(category, "announceAccepted", "Announce Accepted Quests",
		"When in a party, post a message in party chat when you accept a quest.")

	AddCheckbox(category, "autoShare", "Auto Share Accepted Quests",
		"When in a party, automatically share quests with party members as you accept them (if the quest can be shared). Quests shared with you aren't shared back.")

	Settings.RegisterAddOnCategory(category)
end

function Options:Open()
	if self.category then
		Settings.OpenToCategory(self.category:GetID())
	end
end
