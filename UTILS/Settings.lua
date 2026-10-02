--[[
    Copyright © 2026 @APHONlC. All rights reserved.

    No copying, modification, distribution, or sale without prior written permission.
    AI/ML ingestion and training are strictly prohibited (TDM opt-out).

    See LICENSE.md for full terms and maintenance exceptions.
]]

local SS = APHSearchCore

local PANEL_ID = "APHSearchOptions"
local REQUIRED_LAM = 30
local REQUIRED_LHAS = 1
local panel

local WARN_TEMPLATES = {
	missing = SS.L("IS_NOT_INSTALLED_INSTALL_OR"),
	disabled = SS.L("IS_INSTALLED_BUT_SWITCHED_OFF_TURN"),
	old = SS.L("IS_THIS_NEEDS_UPDATE_IT_OR"),
}

function SS.CheckSettingsLibraries()
	local lam_version, lam_enabled = LibAPH.CheckLibraryVersion("LibAddonMenu-2.0")
	local alerts = {}

	local lam_alert = LibAPH.BuildLibraryWarning(WARN_TEMPLATES, "LibAddonMenu", "LAM",
		lam_version, lam_enabled, REQUIRED_LAM, SS.L("THE_SETTINGS_PANEL_WILL_NOT_OPEN"))
	if lam_alert then alerts[#alerts + 1] = lam_alert end

	if IsConsoleUI() then
		local lhas_version, lhas_enabled = LibAPH.CheckLibraryVersion("LibHarvensAddonSettings")
		local lhas_alert = LibAPH.BuildLibraryWarning(WARN_TEMPLATES, "LibHarvensAddonSettings", "LHAS",
			lhas_version, lhas_enabled, REQUIRED_LHAS, SS.L("THE_SETTINGS_PANEL_WILL_NOT_OPEN_2"))
		if lhas_alert then alerts[#alerts + 1] = lhas_alert end
	end

	return alerts
end

function SS.WarnAboutSettingsLibraries()
	local alerts = SS.CheckSettingsLibraries()
	if #alerts == 0 then return false end
	if SS.saved.warned_about_libraries then return false end

	SS.saved.warned_about_libraries = true
	for _, alert in ipairs(alerts) do SS.Print(alert, true) end
	return true
end

local function ScopeControls(data)
	for _, scope in ipairs(SS.GetAllScopes()) do
		data[#data + 1] = {
			type = "checkbox",
			name = SS.ScopeName(scope),
			getFunc = function() return SS.IsScopeEnabled(scope) end,
			setFunc = function(value)
				SS.SetScopeEnabled(scope, value)
				SS.RefreshScope()
			end,
			default = SS.DefaultScopeOn(scope),
			width = "half",
		}
	end
end

local function GuideOff() return not SS.Guide.IsEnabled() end
local function NoImplex() return GuideOff() or not SS.Guide.HasLibImplex() end
local function GroupOff() return GuideOff() or not SS.GuideGroup.Available() or not SS.saved.guide_group end

local function ColorChoice(element, labelKey)
	local names, values = {}, {}
	for _, key in ipairs(SS.GuideDraw.COLOR_ORDER) do
		names[#names + 1] = SS.L("GUIDE_COLOR_" .. string.upper(key))
		values[#values + 1] = key
	end
	return {
		type = "dropdown",
		name = SS.L(labelKey),
		choices = names,
		choicesValues = values,
		getFunc = function() return SS.saved["guide_color_" .. element] end,
		setFunc = function(value)
			SS.saved["guide_color_" .. element] = value
			SS.Guide.Apply()
		end,
		default = SS.DEFAULTS["guide_color_" .. element],
		disabled = function() return not SS.Guide.IsEnabled() end,
		width = "half",
	}
end

local function DesignChoice(kind, labelKey, nameKeys)
	local names, values = {}, {}
	for i, key in ipairs(nameKeys) do
		names[i] = SS.L(key)
		values[i] = i
	end
	return {
		type = "dropdown",
		name = SS.L(labelKey),
		choices = names,
		choicesValues = values,
		getFunc = function() return SS.saved["guide_design_" .. kind] end,
		setFunc = function(value)
			SS.saved["guide_design_" .. kind] = value
			SS.Guide.Apply()
		end,
		default = SS.DEFAULTS["guide_design_" .. kind],
		disabled = function() return not SS.Guide.IsEnabled() end,
		width = "half",
	}
end

local function GuideSet(key, refresh)
	return function(value)
		SS.saved[key] = value
		if refresh then SS.Guide.Apply() end
	end
end

local function GuideControls()
	local D = SS.DEFAULTS
	return {
		{
			type = "description",
			text = function()
				local notes = { SS.L("GUIDE_HOW_IT_WORKS") }
				if not SS.Guide.HasLibImplex() then notes[#notes + 1] = SS.L("GUIDE_NEEDS_LIBIMPLEX") end
				if not SS.GuideGroup.Available() then notes[#notes + 1] = SS.L("GUIDE_NEEDS_LGB") end
				return table.concat(notes, "\n\n")
			end,
		},
		{
			type = "description",
			text = function() return (SS.GuideRoads.MapDataStatus()) end,
		},
		{
			type = "checkbox",
			name = SS.L("GUIDE_ME_TO_MY_WAYPOINT"),
			getFunc = function() return SS.saved.guide_enabled end,
			setFunc = GuideSet("guide_enabled", true),
			default = D.guide_enabled,
		},
		{
			type = "dropdown",
			name = SS.L("GUIDE_STYLE"),
			choices = { SS.L("GUIDE_STYLE_BOTH"), SS.L("GUIDE_STYLE_GROUND"), SS.L("GUIDE_STYLE_HUD") },
			choicesValues = { "both", "ground", "hud" },
			getFunc = function() return SS.saved.guide_style end,
			setFunc = GuideSet("guide_style", true),
			default = D.guide_style,
			disabled = GuideOff,
		},
		ColorChoice("hud", "GUIDE_COLOR_SCREEN_ARROW"),
		ColorChoice("ground", "GUIDE_COLOR_GROUND_ARROWS"),
		ColorChoice("ring", "GUIDE_COLOR_DESTINATION"),
		ColorChoice("path", "GUIDE_COLOR_MAP_PATH"),
		ColorChoice("marker", "GUIDE_COLOR_MAP_MARKER"),
		ColorChoice("marks", "GUIDE_COLOR_GROUP_MARKS"),
		ColorChoice("record", "GUIDE_COLOR_RECORDED"),
		DesignChoice("hud", "GUIDE_DESIGN_SCREEN_ARROW", { "GUIDE_DESIGN_COMPASS", "GUIDE_DESIGN_DOUBLE_CHEVRON", "GUIDE_DESIGN_ARROW" }),
		DesignChoice("ground", "GUIDE_DESIGN_GROUND_ARROWS", { "GUIDE_DESIGN_ARROWHEAD", "GUIDE_DESIGN_CHEVRON", "GUIDE_DESIGN_DART" }),
		DesignChoice("ring", "GUIDE_DESIGN_DESTINATION", { "GUIDE_DESIGN_RING", "GUIDE_DESIGN_DASHED_RING", "GUIDE_DESIGN_TARGET" }),
		{
			type = "dropdown",
			name = SS.L("GUIDE_HUD_PLACE"),
			choices = { SS.L("GUIDE_HUD_PLACE_FEET"), SS.L("GUIDE_HUD_PLACE_TOP") },
			choicesValues = { "feet", "top" },
			getFunc = function() return SS.saved.guide_hud_anchor end,
			setFunc = GuideSet("guide_hud_anchor", true),
			default = D.guide_hud_anchor,
			disabled = GuideOff,
		},
		{
			type = "checkbox",
			name = SS.L("GUIDE_HUD_LETTER"),
			getFunc = function() return SS.saved.guide_hud_letter end,
			setFunc = GuideSet("guide_hud_letter"),
			default = D.guide_hud_letter,
			disabled = GuideOff,
		},
		{
			type = "dropdown",
			name = SS.L("GUIDE_MAP_MARKER"),
			choices = { SS.L("GUIDE_MAP_MARKER_PIN1"), SS.L("GUIDE_MAP_MARKER_PIN2"), SS.L("GUIDE_MAP_MARKER_PIN3"), SS.L("GUIDE_MAP_MARKER_GAME") },
			choicesValues = { "pin1", "pin2", "pin3", "game" },
			getFunc = function() return SS.saved.guide_map_marker end,
			setFunc = GuideSet("guide_map_marker", true),
			default = D.guide_map_marker,
			disabled = GuideOff,
		},
		{
			type = "checkbox",
			name = SS.L("GUIDE_MAP_PATH"),
			getFunc = function() return SS.saved.guide_map_path end,
			setFunc = GuideSet("guide_map_path", true),
			default = D.guide_map_path,
			disabled = GuideOff,
		},
		{
			type = "checkbox",
			name = SS.L("GUIDE_MAP_CIRCLE"),
			getFunc = function() return SS.saved.guide_map_circle end,
			setFunc = GuideSet("guide_map_circle", true),
			default = D.guide_map_circle,
			disabled = GuideOff,
		},
		{
			type = "checkbox",
			name = SS.L("GUIDE_MAP_CIRCLE_ANIMATE"),
			getFunc = function() return SS.saved.guide_map_circle_animate end,
			setFunc = GuideSet("guide_map_circle_animate", true),
			default = D.guide_map_circle_animate,
			disabled = function() return GuideOff() or not SS.saved.guide_map_circle end,
		},
		{
			type = "slider",
			name = SS.L("GUIDE_OPACITY"),
			min = 20,
			max = 100,
			step = 5,
			getFunc = function() return math.floor(SS.saved.guide_opacity * 100 + 0.5) end,
			setFunc = function(value) SS.saved.guide_opacity = value / 100 end,
			default = math.floor(D.guide_opacity * 100 + 0.5),
			disabled = GuideOff,
		},
		{
			type = "slider",
			name = SS.L("GUIDE_HUD_HEIGHT"),
			min = 2,
			max = 70,
			step = 1,
			getFunc = function() return math.floor(SS.saved.guide_hud_y * 100 + 0.5) end,
			setFunc = function(value)
				SS.saved.guide_hud_y = value / 100
				SS.Guide.Apply()
			end,
			default = math.floor(D.guide_hud_y * 100 + 0.5),
			disabled = GuideOff,
		},
		{
			type = "checkbox",
			name = SS.L("GUIDE_LABEL_3D"),
			getFunc = function() return SS.saved.guide_label_3d end,
			setFunc = GuideSet("guide_label_3d"),
			default = D.guide_label_3d,
			disabled = NoImplex,
		},
		{
			type = "checkbox",
			name = SS.L("GUIDE_CLEAR_ON_ARRIVAL"),
			getFunc = function() return SS.saved.guide_clear_on_arrival end,
			setFunc = GuideSet("guide_clear_on_arrival"),
			default = D.guide_clear_on_arrival,
			disabled = GuideOff,
		},
		{
			type = "checkbox",
			name = SS.L("GUIDE_LEARN_ROADS"),
			getFunc = function() return SS.saved.guide_learn_roads end,
			setFunc = GuideSet("guide_learn_roads"),
			default = D.guide_learn_roads,
			disabled = GuideOff,
		},
		{
			type = "checkbox",
			name = SS.L("GUIDE_RECORD"),
			getFunc = function() return SS.GuideRecord.IsRecording() end,
			setFunc = function(value) SS.GuideRecord.SetRecording(value) end,
			default = false,
		},
		{
			type = "checkbox",
			name = SS.L("GUIDE_SHOW_RECORDINGS"),
			getFunc = function() return SS.saved.guide_show_recordings end,
			setFunc = GuideSet("guide_show_recordings", true),
			default = D.guide_show_recordings,
		},
		{
			type = "button",
			name = "|cFF0000" .. SS.L("GUIDE_FORGET_RECORDINGS") .. "|r",
			isDangerous = true,
			warning = SS.L("GUIDE_FORGET_RECORDINGS_WARNING"),
			func = function()
				SS.GuideRecord.Forget()
				SS.Print(SS.L("GUIDE_RECORDINGS_FORGOTTEN"), true)
			end,
			width = "half",
		},
		{
			type = "checkbox",
			name = SS.L("GUIDE_MAP_ROADS"),
			getFunc = function() return SS.saved.guide_map_roads end,
			setFunc = GuideSet("guide_map_roads"),
			default = D.guide_map_roads,
			disabled = function() return GuideOff() or SS.GuideRoads.MapData() == nil end,
		},
		{
			type = "button",
			name = "|cFF0000" .. SS.L("GUIDE_FORGET_ROADS") .. "|r",
			isDangerous = true,
			warning = SS.L("GUIDE_FORGET_ROADS_WARNING"),
			func = function()
				SS.GuideRoads.Forget()
				SS.Print(SS.L("GUIDE_ROADS_FORGOTTEN"), true)
			end,
			width = "half",
		},
		{
			type = "header",
			name = SS.L("GUIDE_GROUP"),
		},
		{
			type = "checkbox",
			name = SS.L("GUIDE_USE_WITH_GROUP"),
			getFunc = function() return SS.saved.guide_group end,
			setFunc = GuideSet("guide_group", true),
			default = D.guide_group,
			disabled = function() return GuideOff() or not SS.GuideGroup.Available() end,
		},
		{
			type = "checkbox",
			name = SS.L("GUIDE_SHARE_MARKS"),
			getFunc = function() return SS.saved.guide_share_marks end,
			setFunc = GuideSet("guide_share_marks"),
			default = D.guide_share_marks,
			disabled = GroupOff,
		},
		{
			type = "checkbox",
			name = SS.L("GUIDE_SHOW_MARKS"),
			getFunc = function() return SS.saved.guide_show_marks end,
			setFunc = function(value)
				SS.saved.guide_show_marks = value
				SS.GuideGroup.RefreshMarks()
			end,
			default = D.guide_show_marks,
			disabled = function() return GroupOff() or not SS.Guide.HasLibImplex() end,
		},
		{
			type = "checkbox",
			name = SS.L("GUIDE_FOLLOW_LEADER_MARKS"),
			getFunc = function() return SS.saved.guide_follow_leader_marks end,
			setFunc = GuideSet("guide_follow_leader_marks"),
			default = D.guide_follow_leader_marks,
			disabled = GroupOff,
		},
		{
			type = "checkbox",
			name = SS.L("GUIDE_GROUP_OFFER"),
			getFunc = function() return SS.saved.guide_group_offer end,
			setFunc = GuideSet("guide_group_offer"),
			default = D.guide_group_offer,
			disabled = GroupOff,
		},
		{
			type = "checkbox",
			name = SS.L("GUIDE_SHARE_TRAVEL"),
			getFunc = function() return SS.saved.guide_share_travel end,
			setFunc = GuideSet("guide_share_travel"),
			default = D.guide_share_travel,
			disabled = GroupOff,
		},
		{
			type = "dropdown",
			name = SS.L("GUIDE_FOLLOW_TRAVEL"),
			choices = { SS.L("GUIDE_FOLLOW_ASK"), SS.L("GUIDE_FOLLOW_AUTO"), SS.L("GUIDE_FOLLOW_OFF") },
			choicesValues = { "ask", "auto", "off" },
			getFunc = function() return SS.saved.guide_follow_travel end,
			setFunc = GuideSet("guide_follow_travel"),
			default = D.guide_follow_travel,
			disabled = GroupOff,
		},
		{
			type = "checkbox",
			name = SS.L("GUIDE_FOLLOW_LEADER_ONLY"),
			getFunc = function() return SS.saved.guide_follow_leader_only end,
			setFunc = GuideSet("guide_follow_leader_only"),
			default = D.guide_follow_leader_only,
			disabled = function() return GroupOff() or SS.saved.guide_follow_travel == "off" end,
		},
	}
end

function SS.HowItWorks()
	if IsInGamepadPreferredMode() then
		return SS.L("HOW_IT_WORKS_CONTROLLER")
	end
	local key = ZO_Keybindings_GetHighestPriorityBindingStringFromAction("APHSEARCH_TOGGLE",
		KEYBIND_TEXT_OPTIONS_ABBREVIATED_NAME, KEYBIND_TEXTURE_OPTIONS_EMBED_MARKUP)
	local opener = key and string.format(SS.L("HOW_IT_WORKS_OPEN_KEY"), key) or SS.L("HOW_IT_WORKS_OPEN_NO_KEY")
	return opener .. SS.L("HOW_IT_WORKS_KEYBOARD_REST")
end

local KEYBOARD_ONLY = {
	[SS.L("BAR_OPACITY")] = true, [SS.L("RESET_BAR_POSITION")] = true,
	[SS.L("GUIDE_MAP_MARKER")] = true, [SS.L("GUIDE_MAP_PATH")] = true,
	[SS.L("GUIDE_COLOR_MAP_PATH")] = true, [SS.L("GUIDE_COLOR_MAP_MARKER")] = true,
	[SS.L("GUIDE_MAP_CIRCLE")] = true, [SS.L("GUIDE_MAP_CIRCLE_ANIMATE")] = true,
	[SS.L("GUIDE_SHOW_RECORDINGS")] = true, [SS.L("GUIDE_COLOR_RECORDED")] = true,
	[SS.L("GUIDE_GROUP_OFFER")] = true,
}
local CONSOLE_ONLY = { [SS.L("HOLD_LEFT_TRIGGER")] = true }
local HOW_IT_WORKS = "APHSearchHowItWorks"

function SS.DropOtherPlatformSettings(data)
	local other = IsConsoleUI() and KEYBOARD_ONLY or CONSOLE_ONLY
	for index = #data, 1, -1 do
		local name = data[index].name
		if type(name) == "string" and other[LibAPH.StripColors(name)] then table.remove(data, index) end
	end
	return data
end

function SS.ShowKeyFrames(created)
	if IsConsoleUI() or created ~= panel then return false end
	local control = _G[HOW_IT_WORKS]
	local desc = control and control.desc
	if not desc or desc.aphsearch_key_frames then return false end
	desc.aphsearch_key_frames = true
	desc:SetHandler("OnTextChanged", ZO_SmallKeyMarkupLabel_OnTextChanged)
	desc:SetHandler("OnUserAreaCreated", ZO_SmallKeyMarkupLabel_OnNewUserAreaCreated)
	desc:SetText(SS.HowItWorks())
	return true
end

function SS.BuildSettingsPanel()
	local lam = LibAddonMenu2
	if not lam or type(lam.RegisterAddonPanel) ~= "function" then return false end
	if panel then return true end

	local header = {
		type = "panel",
		name = "|c9CD04CAPH-Search|r",
		displayName = "|c00FFFFAPH-Search|r",
		author = "|ca500f3A|r|cb400e6P|r|cc300daH|r|cd200cdO|r|ce100c1NlC|r",
		version = SS.VERSION,
		registerForRefresh = true,
		translation = "https://www.esoui.com/portal.php?id=360&a=featurereq",
		donation = "https://buymeacoffee.com/aph0nlc",
	}

	local data = {
		{
			type = "description",
			title = SS.L("HOW_IT_WORKS"),
			text = function() return SS.HowItWorks() end,
			reference = HOW_IT_WORKS,
		},
		{
			type = "checkbox",
			name = SS.L("MATCH_TOOLTIPS_AND_DESCRIPTIONS"),
			getFunc = function() return SS.saved.match_tooltips end,
			setFunc = function(value) SS.saved.match_tooltips = value end,
			default = SS.DEFAULTS.match_tooltips,
		},
		{
			type = "checkbox",
			name = SS.L("OFFER_TO_TRAVEL_FROM_THE_MAP"),
			getFunc = function() return SS.saved.wayshrine_travel_prompt end,
			setFunc = function(value) SS.saved.wayshrine_travel_prompt = value end,
			default = SS.DEFAULTS.wayshrine_travel_prompt,
		},
		{
			type = "checkbox",
			name = SS.L("CHAT_MESSAGES"),
			getFunc = function() return SS.saved.chat_messages end,
			setFunc = function(value) SS.saved.chat_messages = value end,
			default = SS.DEFAULTS.chat_messages,
		},
		{
			type = "checkbox",
			name = SS.L("HOLD_LEFT_TRIGGER"),
			getFunc = function() return SS.saved.hold_trigger_search end,
			setFunc = function(value) SS.saved.hold_trigger_search = value end,
			default = SS.DEFAULTS.hold_trigger_search,
		},
		{
			type = "checkbox",
			name = SS.L("PREFER_INSTANT_RESULTS"),
			getFunc = function() return SS.saved.instant_results end,
			setFunc = function(value) SS.saved.instant_results = value end,
			default = SS.DEFAULTS.instant_results,
		},
		{
			type = "slider",
			name = SS.L("BAR_OPACITY"),
			min = 0,
			max = 100,
			step = 5,
			getFunc = function() return math.floor((SS.saved.bar_opacity or 1) * 100 + 0.5) end,
			setFunc = function(value) SS.SetBarOpacity(value / 100) end,
			default = math.floor(SS.DEFAULTS.bar_opacity * 100 + 0.5),
		},
		{
			type = "button",
			name = "|cFF0000" .. SS.L("RESET_BAR_POSITION") .. "|r",
			warning = SS.L("WARN_RESET_BAR_POSITION"),
			isDangerous = true,
			func = function()
				SS.ResetBarPosition()
				SS.Print(SS.L("THE_SEARCH_BAR_IS_BACK_WHERE"), true)
			end,
			width = "half",
		},
		{
			type = "button",
			name = "|cFF0000" .. SS.L("RESET_TO_DEFAULTS") .. "|r",
			warning = SS.L("WARN_RESET_TO_DEFAULTS"),
			isDangerous = true,
			func = function()
				SS.ResetToDefaults()
				SS.RefreshScope()
				SS.Guide.Apply()
				SS.Print(SS.L("SETTINGS_ARE_BACK_TO_THEIR_DEFAULTS"), true)
			end,
			width = "half",
		},
		{
			type = "submenu",
			name = SS.L("GUIDE"),
			controls = SS.DropOtherPlatformSettings(GuideControls()),
		},
		{
			type = "submenu",
			name = SS.L("WHAT_GETS_SEARCHED"),
			controls = (function()
				local controls = {}
				ScopeControls(controls)
				return controls
			end)(),
		},
	}

	SS.DropOtherPlatformSettings(data)

	panel = lam:RegisterAddonPanel(PANEL_ID, header)
	lam:RegisterOptionControls(PANEL_ID, data)
	if not IsConsoleUI() then CALLBACK_MANAGER:RegisterCallback("LAM-PanelControlsCreated", SS.ShowKeyFrames) end
	SS.WarnAboutSettingsLibraries()
	return true
end
