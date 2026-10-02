--[[
    Copyright © 2026 @APHONlC. All rights reserved.

    No copying, modification, distribution, or sale without prior written permission.
    AI/ML ingestion and training are strictly prohibited (TDM opt-out).

    See LICENSE.md for full terms and maintenance exceptions.
]]

local SS = APHSearchCore
local GG = {}
SS.GuideGroup = GG

local floor = math.floor
local GetFrameTimeMilliseconds = GetFrameTimeMilliseconds

local PROTOCOL_MARK_ID = 470
local PROTOCOL_TRAVEL_ID = 471
GG.PROTOCOL_MARK_ID, GG.PROTOCOL_TRAVEL_ID = PROTOCOL_MARK_ID, PROTOCOL_TRAVEL_ID

local NS = SS.name .. "GuideGroup"
local KINDS = { "waypoint", "quest", "place", "clear" }
local TRAVEL_WINDOW_MS = 120000
local DEDUPE_MS = 60000
local AUTO_FOLLOW_MS = 3000
local MARK_REFRESH_MS = 500
local SHARE_DELAY_MS = 1000
local LABEL_BYTES = 30
local FOLLOW_OFF, FOLLOW_ASK, FOLLOW_AUTO = "off", "ask", "auto"
GG.FOLLOW_OFF, GG.FOLLOW_ASK, GG.FOLLOW_AUTO = FOLLOW_OFF, FOLLOW_ASK, FOLLOW_AUTO

local marks = {}
GG.marks = marks
local mark_protocol, travel_protocol, built
local pending_travel, following_until = nil, 0
local recent_travel = {}
local marks_loop = false
local share_pending

function GG.Available()
	local lgb = LibGroupBroadcast
	return type(lgb) == "table" and type(lgb.RegisterHandler) == "function"
end

function GG.IsOn()
	return SS.saved.guide_group == true and SS.Guide.IsEnabled() and GG.Available()
end

local function TrimLabel(text)
	text = tostring(text or "")
	if #text <= LABEL_BYTES then return text end
	local stop = LABEL_BYTES
	local nextByte = string.byte(text, stop + 1)
	while stop > 0 and nextByte and nextByte >= 128 and nextByte < 192 do
		nextByte = string.byte(text, stop)
		stop = stop - 1
	end
	return string.sub(text, 1, stop)
end
GG.TrimLabel = TrimLabel

local function MyZone()
	local zoneId = GetUnitRawWorldPosition("player")
	return zoneId
end

local function RefreshMarks()
	local zoneId, _, py = GetUnitRawWorldPosition("player")
	local any = false
	for key, mark in pairs(marks) do
		any = true
		if SS.saved.guide_show_marks and mark.zoneId == zoneId then
			SS.GuideDraw.ShowMark(key, mark, py)
		else
			SS.GuideDraw.HideMark(key)
		end
	end
	if not any and marks_loop then
		marks_loop = false
		EVENT_MANAGER:UnregisterForUpdate(NS .. "Marks")
	end
end
GG.RefreshMarks = RefreshMarks

local function StartMarksLoop()
	if marks_loop then return end
	marks_loop = true
	EVENT_MANAGER:RegisterForUpdate(NS .. "Marks", MARK_REFRESH_MS, RefreshMarks)
end

local function LeaderName()
	local tag = GetGroupLeaderUnitTag()
	return tag and tag ~= "" and GetUnitDisplayName(tag) or nil
end

function GG.LeaderMarkTarget()
	if not GG.IsOn() or not SS.saved.guide_follow_leader_marks then return nil end
	local leader = LeaderName()
	local mark = leader and marks[leader]
	if not mark or mark.zoneId ~= MyZone() then return nil end
	return {
		own = false, zoneId = mark.zoneId, x = mark.x, z = mark.z, y = mark.y,
		label = mark.label, kind = mark.kind, from = mark.name,
	}
end

function GG.OnMark(unitTag, data)
	if AreUnitsEqual and AreUnitsEqual(unitTag, "player") then return false end
	local name = GetUnitDisplayName(unitTag)
	if not name or name == "" then return false end
	if data.kind == "clear" then
		marks[name] = nil
		SS.GuideDraw.HideMark(name)
		local st = SS.Guide.state
		if st.target and st.target.from == name then SS.Guide.ClearTarget() end
		return true
	end
	marks[name] = {
		name = name, kind = data.kind, label = data.label,
		zoneId = data.zoneId, x = data.x * 100, z = data.z * 100, y = data.y and data.y * 100 or nil,
	}
	StartMarksLoop()
	RefreshMarks()
	local st = SS.Guide.state
	if not st.target and SS.saved.guide_follow_leader_marks and name == LeaderName() then
		SS.Guide.GuideToMark(marks[name])
	end
	return true
end

local function NodeName(node)
	local _, name = GetFastTravelNodeInfo(node)
	return zo_strformat("<<1>>", name or "")
end

local function DoFollow(node, unitTag, name)
	if IsUnitInCombat("player") then
		SS.Print(SS.L("GUIDE_CANT_FOLLOW_IN_COMBAT"))
		return false
	end
	local known, _, _, _, _, _, _, _, locked = GetFastTravelNodeInfo(node)
	if known and not locked then
		following_until = GetFrameTimeMilliseconds() + TRAVEL_WINDOW_MS
		FastTravelToNode(node)
		return true
	end
	if CanJumpToGroupMember(unitTag) then
		following_until = GetFrameTimeMilliseconds() + TRAVEL_WINDOW_MS
		JumpToGroupMember(name)
		return true
	end
	SS.Print(SS.L("GUIDE_CANT_FOLLOW", name, NodeName(node)))
	return false
end
GG.DoFollow = DoFollow

local function Seen(name, node, now)
	local key = name .. ":" .. node
	if recent_travel[key] and now - recent_travel[key] < DEDUPE_MS then return true end
	recent_travel[key] = now
	return false
end

function GG.OnTravel(unitTag, data)
	if AreUnitsEqual and AreUnitsEqual(unitTag, "player") then return false end
	local mode = SS.saved.guide_follow_travel or FOLLOW_ASK
	if mode == FOLLOW_OFF then return false end
	local name = GetUnitDisplayName(unitTag)
	if not name or name == "" then return false end
	if SS.saved.guide_follow_leader_only and not IsUnitGroupLeader(unitTag) then return false end
	local now = GetFrameTimeMilliseconds()
	if Seen(name, data.node, now) then return false end
	local place = NodeName(data.node)
	if mode == FOLLOW_AUTO then
		SS.Print(SS.L("GUIDE_FOLLOWING", name, place))
		zo_callLater(function() DoFollow(data.node, unitTag, name) end, AUTO_FOLLOW_MS)
		return true
	end
	local cost = GetRecallCost(data.node) or 0
	local body = SS.L("GUIDE_FOLLOW_ASK_BODY", name, place)
	if cost > 0 then body = body .. "\n" .. SS.L("GUIDE_RECALL_COST", cost) end
	LibAPH.ShowDialogHidingWindows({}, "APHSEARCH_GUIDE_FOLLOW", SS.L("GUIDE_FOLLOW_ASK_TITLE"), body, {
		{ text = SI_DIALOG_ACCEPT, callback = function() DoFollow(data.node, unitTag, name) end },
		{ text = SI_DIALOG_DECLINE },
	})
	return true
end

local hooked = false

local function HookTravel()
	if hooked then return end
	hooked = true
	ZO_PreHook("FastTravelToNode", function(node)
		if not GG.IsOn() or not SS.saved.guide_share_travel then return end
		if GetFrameTimeMilliseconds() < following_until then return end
		pending_travel = { node = node, at = GetFrameTimeMilliseconds() }
	end)
end

function GG.OnActivated()
	local travel = pending_travel
	pending_travel = nil
	if GetFrameTimeMilliseconds() < following_until then
		following_until = 0
		return
	end
	if travel and GG.IsOn() and IsUnitGrouped("player") and GetFrameTimeMilliseconds() - travel.at <= TRAVEL_WINDOW_MS then
		if travel_protocol and travel_protocol:IsEnabled() then
			travel_protocol:Send({ node = travel.node, zoneId = MyZone() or 0 })
		end
	end
	RefreshMarks()
end

local function SendTarget(target)
	if not mark_protocol or not mark_protocol:IsEnabled() or not IsUnitGrouped("player") then return false end
	if not target or target.far then
		return mark_protocol:Send({ kind = "clear", zoneId = 0, x = 0, z = 0, y = 0, label = "" })
	end
	return mark_protocol:Send({
		kind = target.kind == "quest" and "quest" or (target.kind == "place" and "place" or "waypoint"),
		zoneId = target.zoneId, x = floor(target.x / 100 + 0.5), z = floor(target.z / 100 + 0.5),
		y = floor(((target.groundY or 0) / 100) + 0.5), label = TrimLabel(target.label),
	})
end
GG.SendTarget = SendTarget

function GG.ShareTarget(target)
	if not GG.IsOn() or not SS.saved.guide_share_marks then return false end
	local queued = share_pending ~= nil
	share_pending = target or false
	if queued then return true end
	zo_callLater(function()
		local latest = share_pending
		share_pending = nil
		SendTarget(latest or nil)
	end, SHARE_DELAY_MS)
	return true
end

local function OnMemberLeft(_, _, _, isLocalPlayer, _, displayName)
	if isLocalPlayer then
		for key in pairs(marks) do
			marks[key] = nil
			SS.GuideDraw.HideMark(key)
		end
		if SS.GuideTrack then
			if SS.GuideTrack.Mode() == SS.GuideTrack.MODE_MEMBER then SS.Guide.ClearTarget() end
			SS.GuideTrack.Stop()
			SS.GuideTrack.ResetOffer()
		end
		return
	end
	if displayName and marks[displayName] then
		marks[displayName] = nil
		SS.GuideDraw.HideMark(displayName)
	end
	local st = SS.Guide.state
	if st.target and st.target.member and not DoesUnitExist(st.target.member) then SS.Guide.ClearTarget() end
end

local function OnMemberJoined()
	local st = SS.Guide.state
	if st.target and st.target.own then GG.ShareTarget(st.target) end
	if SS.GuideTrack then zo_callLater(SS.GuideTrack.Offer, 2000) end
end

local function Build()
	if built then return true end
	local lgb = LibGroupBroadcast
	local handler = lgb:RegisterHandler(SS.name, "APHSearchGuide")
	if not handler then return false end
	handler:SetDisplayName("APH-Search")
	handler:SetDescription(SS.L("GUIDE_LGB_DESCRIPTION"))

	mark_protocol = handler:DeclareProtocol(PROTOCOL_MARK_ID, "APHSearchGuideMark")
	mark_protocol:AddField(lgb.CreateEnumField("kind", KINDS))
	mark_protocol:AddField(lgb.CreateNumericField("zoneId", { minValue = 0, maxValue = 8191 }))
	mark_protocol:AddField(lgb.CreateNumericField("x", { minValue = -131072, maxValue = 131071 }))
	mark_protocol:AddField(lgb.CreateNumericField("z", { minValue = -131072, maxValue = 131071 }))
	mark_protocol:AddField(lgb.CreateNumericField("y", { minValue = -8192, maxValue = 8191, trimValues = true }))
	mark_protocol:AddField(lgb.CreateStringField("label", { maxLength = LABEL_BYTES }))
	mark_protocol:OnData(GG.OnMark)
	mark_protocol:Finalize({ replaceQueuedMessages = true })

	travel_protocol = handler:DeclareProtocol(PROTOCOL_TRAVEL_ID, "APHSearchGuideTravel")
	travel_protocol:AddField(lgb.CreateNumericField("node", { minValue = 0, maxValue = 2047 }))
	travel_protocol:AddField(lgb.CreateNumericField("zoneId", { minValue = 0, maxValue = 8191 }))
	travel_protocol:OnData(GG.OnTravel)
	travel_protocol:Finalize()

	EVENT_MANAGER:RegisterForEvent(NS, EVENT_GROUP_MEMBER_LEFT, OnMemberLeft)
	EVENT_MANAGER:RegisterForEvent(NS, EVENT_GROUP_MEMBER_JOINED, OnMemberJoined)
	HookTravel()
	built = true
	return true
end
GG.Build = Build

function GG.Apply()
	if not GG.IsOn() then
		for key in pairs(marks) do marks[key] = nil end
		if SS.GuideDraw then SS.GuideDraw.HideAllMarks() end
		return false
	end
	return Build()
end
