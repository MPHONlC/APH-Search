--[[
    Copyright © 2026 @APHONlC. All rights reserved.

    No copying, modification, distribution, or sale without prior written permission.
    AI/ML ingestion and training are strictly prohibited (TDM opt-out).

    See LICENSE.md for full terms and maintenance exceptions.
]]

local SS = APHSearchCore
local M = {}
SS.GuideMap = M

local floor, max = math.floor, math.max

local PINS = {
	"APH-Search/textures/guide_pin1.dds",
	"APH-Search/textures/guide_pin2.dds",
	"APH-Search/textures/guide_pin3.dds",
}
M.PINS = PINS
local MAX_LINES = 64
local LINE_PX = 4
local REFRESH_MS = 100
local CIRCLE_M = 30
local CIRCLE_MIN_PX = 28
local CIRCLE_MAX_PX = 140
local PULSE_MS = 700
local MAX_REC_LINES = 300
local REC_LINE_PX = 3

function M.Available()
	return not IsConsoleUI()
end

local original_pin

function M.CurrentPin()
	local n = tonumber(tostring(SS.saved.guide_map_marker or ""):match("^pin(%d)$"))
	return n and PINS[n] or nil
end

local function PinTint()
	local r, g, b = SS.GuideDraw.Color("marker")
	return ZO_ColorDef:New(r, g, b, 1)
end

function M.ApplyMarker()
	local data = ZO_MapPin and ZO_MapPin.PIN_DATA and ZO_MapPin.PIN_DATA[MAP_PIN_TYPE_PLAYER_WAYPOINT]
	if not data then return false end
	if not original_pin then original_pin = { texture = data.texture, tint = data.tint } end
	if M.Available() and SS.Guide.IsEnabled() and M.CurrentPin() then
		data.texture = function() return M.CurrentPin() or PINS[1] end
		data.tint = PinTint
	else
		data.texture, data.tint = original_pin.texture, original_pin.tint
	end
	return true
end

local lines, rec_lines = {}, {}
local drawing, last_draw = false, 0
local shown_points
local circle_at
local rec_polylines, rec_dirty = {}, true
local placed_w, placed_h

local function MapSize()
	if ZO_WorldMap_GetMapDimensions then return ZO_WorldMap_GetMapDimensions() end
	return ZO_WorldMapContainer:GetDimensions()
end

local function NewLine(pool, prefix, i, level)
	local line = WINDOW_MANAGER:CreateControl(prefix .. i, ZO_WorldMapContainer, CT_LINE)
	line:SetDrawLayer(DL_OVERLAY)
	line:SetDrawLevel(level)
	line:SetPixelRoundingEnabled(false)
	line:SetHidden(true)
	pool[i] = line
	return line
end

local function HidePool(pool, first)
	for i = first, #pool do pool[i]:SetHidden(true) end
end

local function PlaceLines(pool, prefix, polylines, w, h, color, thickness, level)
	local used = 0
	for _, points in ipairs(polylines) do
		for k = 2, #points do
			local a, c = points[k - 1], points[k]
			used = used + 1
			local line = pool[used] or NewLine(pool, prefix, used, level)
			line:ClearAnchors()
			line:SetAnchor(TOPLEFT, ZO_WorldMapContainer, TOPLEFT, a[1] * w, a[2] * h)
			line:SetAnchor(BOTTOMRIGHT, ZO_WorldMapContainer, TOPLEFT, c[1] * w, c[2] * h)
			line:SetThickness(thickness)
			line:SetColor(color[1], color[2], color[3], color[4])
			line:SetHidden(false)
		end
	end
	HidePool(pool, used + 1)
	return used
end

function M.Thin(points)
	if #points <= MAX_LINES + 1 then return points end
	local out, step = {}, (#points - 1) / MAX_LINES
	for k = 0, MAX_LINES do out[#out + 1] = points[floor(k * step + 0.5) + 1] end
	return out
end

local function MapPoints(st, frame)
	local points = M.Thin(SS.GuideDraw.PathPoints(st))
	local out = {}
	for k = 1, #points do
		local p = points[k]
		local mx, my = SS.Guide.FrameToMap(frame, p[1] * 100, p[3] * 100)
		out[k] = { mx, my }
	end
	return out
end

local circle, pulse

local function Circle()
	if circle then return circle end
	circle = WINDOW_MANAGER:CreateControl("APHSearchGuideMapCircle", ZO_WorldMapContainer, CT_TEXTURE)
	circle:SetDrawLayer(DL_OVERLAY)
	circle:SetDrawLevel(4)
	circle:SetPixelRoundingEnabled(false)
	circle:SetHidden(true)
	return circle
end

local function Pulse(on)
	if on then
		if not pulse then
			pulse = ANIMATION_MANAGER:CreateTimeline()
			local grow = pulse:InsertAnimation(ANIMATION_SCALE, Circle(), 0)
			grow:SetScaleValues(0.8, 1.15)
			grow:SetDuration(PULSE_MS)
			local fade = pulse:InsertAnimation(ANIMATION_ALPHA, Circle(), 0)
			fade:SetAlphaValues(1, 0.45)
			fade:SetDuration(PULSE_MS)
			pulse:SetPlaybackType(ANIMATION_PLAYBACK_PING_PONG, LOOP_INDEFINITELY)
		end
		if not pulse:IsPlaying() then pulse:PlayFromStart() end
	elseif pulse and pulse:IsPlaying() then
		pulse:Stop()
		Circle():SetScale(1)
		Circle():SetAlpha(1)
	end
end
M.Pulse = Pulse

local function HideCircle()
	circle_at = nil
	if not circle then return end
	Pulse(false)
	circle:SetHidden(true)
end

function M.CircleSize(nx, cx, w)
	return math.min(CIRCLE_MAX_PX, max(CIRCLE_MIN_PX, math.abs(cx - nx) * w * 2))
end

local function Place()
	local w, h = MapSize()
	placed_w, placed_h = w, h
	local r, g, b = SS.GuideDraw.Color("path")
	PlaceLines(lines, "APHSearchGuideMapLine", shown_points and { shown_points } or {}, w, h, { r, g, b, 0.9 }, max(2, LINE_PX), 5)
	local rr, rg, rb = SS.GuideDraw.Color("record")
	PlaceLines(rec_lines, "APHSearchGuideMapRecord", rec_polylines, w, h, { rr, rg, rb, 0.85 }, REC_LINE_PX, 3)
	if circle_at then
		local c = Circle()
		local size = M.CircleSize(circle_at[1], circle_at[3], w)
		c:SetDimensions(size, size)
		c:ClearAnchors()
		c:SetAnchor(CENTER, ZO_WorldMapContainer, TOPLEFT, circle_at[1] * w, circle_at[2] * h)
		c:SetHidden(false)
	end
end
M.Place = Place

local function ShownFrame()
	local mapId = GetCurrentMapId and GetCurrentMapId() or 0
	return SS.Guide.FrameFor(mapId), mapId
end

local function PlayerHere(mapId)
	local own, inside = SS.Guide.PlayerMap()
	return not inside or own == mapId
end
M.PlayerHere = PlayerHere

local function Fits(entry, frame, mapId)
	if entry.inside then return entry.map == mapId end
	return not frame.learned
end
M.Fits = Fits

local function ShowRecordings()
	local record = SS.GuideRecord
	if not record then return false end
	return record.IsRecording() or (SS.saved.guide_show_recordings and record.Count() > 0)
end

local rec_key

local function BuildRecordings(frame, mapId)
	rec_polylines, rec_dirty, rec_key = {}, false, mapId .. ":" .. frame.zoneId
	if not ShowRecordings() then return end
	local list = SS.GuideRecord.Recordings(frame.zoneId)
	local total = 0
	for r = 1, #list do
		if Fits(list[r], frame, mapId) then total = total + #list[r].x end
	end
	local step = math.max(1, math.ceil(total / MAX_REC_LINES))
	local to_map = SS.Guide.FrameToMap
	for r = 1, #list do
		local entry = list[r]
		if Fits(entry, frame, mapId) then
			local xs, zs, out = entry.x, entry.z, {}
			local count = #xs
			for k = 1, count do
				if k == 1 or k == count or (k - 1) % step == 0 then
					local mx, my = to_map(frame, xs[k], zs[k])
					out[#out + 1] = { mx, my }
				end
			end
			if #out >= 2 then rec_polylines[#rec_polylines + 1] = out end
		end
	end
end

function M.RecordingsChanged()
	rec_dirty = true
	if drawing then
		last_draw = 0
	else
		M.Update()
	end
end

function M.RecordedLines() return rec_polylines end

local function Draw()
	local frame, mapId = ShownFrame()
	if not frame then
		shown_points = nil
		rec_polylines = {}
		rec_dirty = true
		HideCircle()
		Place()
		return
	end
	if rec_dirty or rec_key ~= mapId .. ":" .. frame.zoneId then BuildRecordings(frame, mapId) end

	local st = SS.Guide.state
	local target = st.target
	shown_points = nil
	if target and not st.away and st.zoneId == frame.zoneId and PlayerHere(mapId) then
		if SS.saved.guide_map_path then shown_points = MapPoints(st, frame) end
		if SS.saved.guide_map_circle then
			local nx, ny = SS.Guide.FrameToMap(frame, target.x, target.z)
			local cx = SS.Guide.FrameToMap(frame, target.x + CIRCLE_M * 100, target.z)
			circle_at = { nx, ny, cx }
			local c = Circle()
			c:SetTexture(SS.GuideDraw.Texture("ring"))
			local r, g, b = SS.GuideDraw.Color("ring")
			c:SetColor(r, g, b, 0.95)
			Pulse(SS.saved.guide_map_circle_animate)
		else
			HideCircle()
		end
	else
		HideCircle()
	end
	Place()
end
M.Draw = Draw

function M.ShownPoints() return shown_points end

local function OnMapUpdate()
	local now = GetFrameTimeMilliseconds()
	if now - last_draw >= REFRESH_MS then
		last_draw = now
		Draw()
		return
	end
	local w, h = MapSize()
	if w ~= placed_w or h ~= placed_h then Place() end
end
M.OnMapUpdate = OnMapUpdate

local function StartDrawing()
	if drawing then return end
	drawing = true
	last_draw = GetFrameTimeMilliseconds()
	EVENT_MANAGER:RegisterForUpdate("APHSearchGuideMap", 0, OnMapUpdate)
	Draw()
end

local function StopDrawing()
	if not drawing then return end
	drawing = false
	EVENT_MANAGER:UnregisterForUpdate("APHSearchGuideMap")
	shown_points = nil
	rec_polylines, rec_dirty = {}, true
	HidePool(lines, 1)
	HidePool(rec_lines, 1)
	HideCircle()
end

local function WantsMap()
	return SS.saved.guide_map_path or SS.saved.guide_map_circle or ShowRecordings()
end

local function MapShowing()
	return ZO_WorldMap_IsWorldMapShowing and ZO_WorldMap_IsWorldMapShowing()
end

local watching = false

local function OnMapScene(_, state)
	if state == SCENE_SHOWN and WantsMap() then
		StartDrawing()
	elseif state == SCENE_HIDDEN then
		StopDrawing()
	end
end

local function WatchMap()
	if watching then return end
	watching = true
	for _, scene in ipairs({ WORLD_MAP_SCENE, GAMEPAD_WORLD_MAP_SCENE }) do
		if scene then scene:RegisterCallback("StateChange", OnMapScene) end
	end
	if ZO_WorldMapPins_Manager then
		SecurePostHook(ZO_WorldMapPins_Manager, "UpdatePinsForMapSizeChange", function()
			if drawing then Place() end
		end)
	end
	CALLBACK_MANAGER:RegisterCallback("OnWorldMapChanged", function()
		if drawing then
			last_draw = GetFrameTimeMilliseconds()
			rec_dirty = true
			Draw()
		end
	end)
end

function M.Update()
	if not M.Available() then return end
	if drawing then return end
	if WantsMap() and MapShowing() then
		WatchMap()
		StartDrawing()
	end
end

function M.Clear()
	if not drawing then return end
	shown_points = nil
	HideCircle()
	Place()
end

function M.Apply()
	if not M.Available() then return false end
	M.ApplyMarker()
	if WantsMap() then WatchMap() else StopDrawing() end
	return true
end
