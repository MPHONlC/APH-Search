--[[
    Copyright © 2026 @APHONlC. All rights reserved.

    No copying, modification, distribution, or sale without prior written permission.
    AI/ML ingestion and training are strictly prohibited (TDM opt-out).

    See LICENSE.md for full terms and maintenance exceptions.
]]

local SS = APHSearchCore
local K = {}
SS.GuideTrack = K

local NS = SS.name .. "GuideTrack"
local QUEST_CHECK_MS = 2000
local QUEST_REFRESH_MS = 10000
local STEP = 1

K.MODE_NONE, K.MODE_QUEST, K.MODE_MEMBER = "none", "quest", "member"
local mode = K.MODE_NONE
local tasks = {}
local quest_key, quest_asked_at = nil, 0
local member_tag
local offered = false

function K.Mode() return mode end
function K.MemberTag() return member_tag end

local function QuestKey(index)
	if not index then return nil end
	local _, _, stepText = GetJournalQuestInfo(index)
	return index .. ":" .. tostring(stepText)
end

local function AskQuestPositions(index)
	for k in pairs(tasks) do tasks[k] = nil end
	SS.Guide.ToPlayerMap()
	for condition = 1, GetJournalQuestNumConditions(index, STEP) do
		local _, current, maximum, _, complete = GetJournalQuestConditionInfo(index, STEP, condition)
		if not complete and (not maximum or current < maximum) and DoesJournalQuestConditionHavePosition(index, STEP, condition) then
			local task = RequestJournalQuestConditionAssistance(index, STEP, condition)
			if task then tasks[task] = index end
		end
	end
	quest_asked_at = GetFrameTimeMilliseconds()
end

local function CheckQuest()
	if mode ~= K.MODE_QUEST then return end
	local index = SS.FocusedQuestIndex()
	local key = QuestKey(index)
	if not key then return end
	if key ~= quest_key or GetFrameTimeMilliseconds() - quest_asked_at >= QUEST_REFRESH_MS then
		quest_key = key
		AskQuestPositions(index)
	end
end
K.CheckQuest = CheckQuest

function K.OnQuestPosition(_, task, _, x, y, _, inside, isBreadcrumb)
	local index = tasks[task]
	if not index or mode ~= K.MODE_QUEST then return false end
	tasks[task] = nil
	local label = zo_strformat("<<1>>", GetJournalQuestName(index))
	if isBreadcrumb then label = SS.L("GUIDE_WAY_TO", label) end
	if not inside then
		SS.Guide.SetTarget({ own = true, far = true, kind = "quest", label = label, quest = true })
		return true
	end
	local zoneId, wx, wz, wy = SS.Guide.MapToWorld(x, y)
	if not zoneId then return false end
	SS.Guide.SetTarget({
		own = true, kind = "quest", label = label, quest = true, zoneId = zoneId, x = wx, z = wz, groundY = wy,
		mapX = math.floor(x * 100 + 0.5), mapY = math.floor(y * 100 + 0.5),
	})
	return true
end

function K.Members()
	local list = {}
	for i = 1, GetGroupSize() do
		local tag = GetGroupUnitTagByIndex(i)
		if tag and not AreUnitsEqual(tag, "player") and DoesUnitExist(tag) then list[#list + 1] = tag end
	end
	return list
end

local function MemberTarget(tag)
	local zoneId, x, y, z = GetUnitRawWorldPosition(tag)
	return { own = false, member = tag, kind = "member", label = GetUnitDisplayName(tag) or tag,
		zoneId = zoneId, x = x, z = z, groundY = y }
end
K.MemberTarget = MemberTarget

function K.NextMember()
	local list = K.Members()
	if #list == 0 then
		SS.Print(SS.L("GUIDE_NO_ONE_TO_FOLLOW"))
		return nil
	end
	local pick = list[1]
	for i, tag in ipairs(list) do
		if tag == member_tag then pick = list[i % #list + 1] end
	end
	K.Stop()
	mode, member_tag = K.MODE_MEMBER, pick
	SS.Guide.SetTarget(MemberTarget(pick))
	SS.Print(SS.L("GUIDE_FOLLOWING_MEMBER", GetUnitDisplayName(pick) or pick))
	return pick
end

function K.StartQuest()
	K.Stop()
	mode, quest_key = K.MODE_QUEST, nil
	EVENT_MANAGER:RegisterForEvent(NS, EVENT_QUEST_POSITION_REQUEST_COMPLETE, K.OnQuestPosition)
	EVENT_MANAGER:RegisterForUpdate(NS, QUEST_CHECK_MS, CheckQuest)
	CheckQuest()
	SS.Print(SS.L("GUIDE_SHARING_QUEST"))
end

function K.Stop()
	if mode == K.MODE_QUEST then
		EVENT_MANAGER:UnregisterForEvent(NS, EVENT_QUEST_POSITION_REQUEST_COMPLETE)
		EVENT_MANAGER:UnregisterForUpdate(NS)
	end
	local was = mode
	mode, member_tag, quest_key = K.MODE_NONE, nil, nil
	for k in pairs(tasks) do tasks[k] = nil end
	return was
end

function K.Offer()
	if IsConsoleUI() or offered or not SS.Guide.IsEnabled() or not SS.saved.guide_group_offer then return false end
	if not IsUnitGrouped("player") or SS.Guide.state.target then return false end
	offered = true
	LibAPH.ShowDialogHidingWindows({}, "APHSEARCH_GUIDE_OFFER", SS.L("GUIDE_OFFER_TITLE"), SS.L("GUIDE_OFFER_QUEST"), {
		{ text = SI_DIALOG_ACCEPT, callback = K.StartQuest },
		{ text = SI_DIALOG_DECLINE, callback = function()
			LibAPH.ShowDialogHidingWindows({}, "APHSEARCH_GUIDE_OFFER_MEMBER", SS.L("GUIDE_OFFER_TITLE"), SS.L("GUIDE_OFFER_MEMBER"), {
				{ text = SI_DIALOG_ACCEPT, callback = K.NextMember },
				{ text = SI_DIALOG_DECLINE },
			})
		end },
	})
	return true
end

function K.ResetOffer() offered = false end
