--[[
    Copyright © 2026 @APHONlC. All rights reserved.

    No copying, modification, distribution, or sale without prior written permission.
    AI/ML ingestion and training are strictly prohibited (TDM opt-out).

    See LICENSE.md for full terms and maintenance exceptions.
]]

local SS = APHSearchCore
local D = {}
SS.GuideDraw = D

local sqrt, atan2, floor, min, max, abs, pi = math.sqrt, math.atan2, math.floor, math.min, math.max, math.abs, math.pi

local TEX_GROUND = "APH-Search/textures/guide_ground.dds"
local TEX_HUD = "APH-Search/textures/guide_compass.dds"
local TEX_RING = "APH-Search/textures/guide_ring.dds"
D.TEX_GROUND, D.TEX_HUD, D.TEX_RING = TEX_GROUND, TEX_HUD, TEX_RING
D.DESIGNS = {
	hud = { TEX_HUD, "APH-Search/textures/guide_compass2.dds", "APH-Search/textures/guide_compass3.dds" },
	ground = { TEX_GROUND, "APH-Search/textures/guide_ground2.dds", "APH-Search/textures/guide_ground3.dds" },
	ring = { TEX_RING, "APH-Search/textures/guide_ring2.dds", "APH-Search/textures/guide_ring3.dds" },
}

function D.Texture(kind)
	local list = D.DESIGNS[kind]
	return list[tonumber(SS.saved["guide_design_" .. kind]) or 1] or list[1]
end

local MAX_ARROWS = 28
local SPACING_M = 3.2
local START_M = 2.5
local FAR_M = 80
local ARROW_M = 1.1
local FLOW_MPS = 1.6
local LIFT_M = 0.12
local LABEL_LIFT_M = 3
local RING_M = 3
local FACE_EVERY_MS = 500
local FACE_TURN = 0.2
local HUD_ARROW = 64
local ON_TARGET = 0.35
local FEET_GAP = 28
local TEXT_WIDTH = 100000
local HUD_EASE = 0.25
local HUD_SNAP_PX = 200
local INFO_GAP = 6

D.MAX_ARROWS, D.SPACING_M, D.START_M, D.FAR_M = MAX_ARROWS, SPACING_M, START_M, FAR_M

D.COLORS = {
	light_blue = { 0.56, 0.83, 1 },
	light_purple = { 0.78, 0.62, 1 },
	green = { 0.35, 0.9, 0.35 },
	gold = { 1, 0.8, 0.3 },
	orange = { 1, 0.58, 0.22 },
	red = { 1, 0.42, 0.42 },
	bright_red = { 1, 0.05, 0.05 },
	pink = { 1, 0.58, 0.86 },
	cyan = { 0.32, 0.95, 0.95 },
	white = { 1, 1, 1 },
}
D.COLOR_ORDER = { "light_blue", "light_purple", "green", "gold", "orange", "red", "bright_red", "pink", "cyan", "white" }

function D.Color(element)
	local key = SS.saved["guide_color_" .. element] or SS.DEFAULTS["guide_color_" .. element]
	local c = D.COLORS[key] or D.COLORS.white
	return c[1], c[2], c[3]
end

local function Opacity()
	return SS.saved.guide_opacity or SS.DEFAULTS.guide_opacity
end

local function WantsHud()
	return SS.Guide.Style() ~= SS.Guide.STYLE_GROUND
end

local function WantsGround()
	return SS.Guide.Style() ~= SS.Guide.STYLE_HUD
end

function D.Cardinal(heading)
	local h = SS.Guide.Wrap(heading)
	if abs(h) <= pi / 4 then return "N" end
	if abs(h) > 3 * pi / 4 then return "S" end
	return h > 0 and "W" or "E"
end

local hud, hud_box, hud_arrow, hud_letter, hud_title, hud_info, hud_dist, hud_eta, hud_gamepad
local hud_x, hud_y, placed_x, placed_y

local function FeetMode()
	return SS.saved.guide_hud_anchor == "feet"
end

local function PlaceTop()
	hud_x, hud_y, placed_x, placed_y = nil, nil, nil, nil
	hud:ClearAnchors()
	hud:SetAnchor(TOP, GuiRoot, TOP, 0, floor(GuiRoot:GetHeight() * (SS.saved.guide_hud_y or SS.DEFAULTS.guide_hud_y)))
end

local function PlaceHud(st)
	if not hud then return end
	if FeetMode() and st then
		local sx, sy = SS.GuideWorld.Project(st.x, st.y, st.z)
		if sx then
			local tx, ty = sx, sy + FEET_GAP
			if not hud_x or abs(tx - hud_x) > HUD_SNAP_PX or abs(ty - hud_y) > HUD_SNAP_PX then
				hud_x, hud_y = tx, ty
			else
				hud_x = hud_x + (tx - hud_x) * HUD_EASE
				hud_y = hud_y + (ty - hud_y) * HUD_EASE
			end
			local rx, ry = floor(hud_x + 0.5), floor(hud_y + 0.5)
			if rx ~= placed_x or ry ~= placed_y then
				placed_x, placed_y = rx, ry
				hud:ClearAnchors()
				hud:SetAnchor(TOP, GuiRoot, CENTER, rx, ry)
			end
			return
		end
	end
	PlaceTop()
end

local function HudFont(big)
	if IsInGamepadPreferredMode() then return big and "ZoFontGamepad27" or "ZoFontGamepad22" end
	return big and "ZoFontWinH4" or "ZoFontGameMedium"
end

local function BuildHud()
	if hud then return end
	local wm = WINDOW_MANAGER
	hud = wm:CreateTopLevelWindow("APHSearchGuideHud")
	hud:SetDimensions(420, 150)
	hud:SetMouseEnabled(false)
	hud_box = wm:CreateControl("$(parent)Box", hud, CT_CONTROL)
	hud_box:SetAnchorFill(hud)
	hud_arrow = wm:CreateControl("$(parent)Arrow", hud_box, CT_TEXTURE)
	hud_arrow:SetTexture(D.Texture("hud"))
	hud_arrow:SetDimensions(HUD_ARROW, HUD_ARROW)
	hud_arrow:SetAnchor(TOP, hud_box, TOP, 0, 0)
	hud_letter = wm:CreateControl("$(parent)Letter", hud_box, CT_LABEL)
	hud_letter:SetAnchor(LEFT, hud_arrow, RIGHT, 4, 6)
	hud_title = wm:CreateControl("$(parent)Title", hud_box, CT_LABEL)
	hud_title:SetAnchor(TOP, hud_arrow, BOTTOM, 0, 2)
	hud_title:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
	hud_info = wm:CreateControl("$(parent)Info", hud_box, CT_LABEL)
	hud_info:SetAnchor(TOP, hud_title, BOTTOM, 0, 0)
	hud_info:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
	hud_dist = wm:CreateControl("$(parent)Distance", hud_box, CT_LABEL)
	hud_dist:SetAnchor(TOPRIGHT, hud_title, BOTTOM, -INFO_GAP, 0)
	hud_dist:SetHorizontalAlignment(TEXT_ALIGN_RIGHT)
	hud_eta = wm:CreateControl("$(parent)Eta", hud_box, CT_LABEL)
	hud_eta:SetAnchor(TOPLEFT, hud_title, BOTTOM, INFO_GAP, 0)
	hud_eta:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
	local fragment = ZO_HUDFadeSceneFragment:New(hud)
	HUD_SCENE:AddFragment(fragment)
	HUD_UI_SCENE:AddFragment(fragment)
	EVENT_MANAGER:RegisterForEvent("APHSearchGuideHud", EVENT_ALL_GUI_SCREENS_RESIZED, function() PlaceHud() end)
	PlaceTop()
end

local function HudText(st)
	local target = st.target
	local title = target.label or ""
	if target.mapX and not st.away then
		title = string.format("%s %d,%d", title, target.mapX, target.mapY)
	end
	if target.from then title = target.from .. ": " .. title end
	if st.away then return SS.L("GUIDE_GO_TO", title), SS.L("GUIDE_IN_ANOTHER_ZONE") end
	if st.arrived_at then
		return title, "|c55DD55" .. (target.arriveText or SS.L("GUIDE_ARRIVED")) .. "|r"
	end
	local dist = SS.Guide.FormatDistance(st.dist)
	local info = dist
	local eta = SS.Guide.FormatEta(st.eta)
	if eta then
		eta = "|cE8B84A" .. eta .. "|r"
		info = info .. "  " .. eta
	end
	return SS.L("GUIDE_GO_TO", title), info, dist, eta or ""
end
D.HudText = HudText

local function UpdateHud(st)
	if not hud then BuildHud() end
	hud_box:SetHidden(false)
	local gamepad = IsInGamepadPreferredMode()
	if gamepad ~= hud_gamepad then
		hud_gamepad = gamepad
		hud_title:SetFont(HudFont(true))
		hud_info:SetFont(HudFont(false))
		hud_dist:SetFont(HudFont(false))
		hud_eta:SetFont(HudFont(false))
		hud_letter:SetFont(HudFont(true))
	end
	PlaceHud(st)
	local r, g, b = D.Color("hud")
	local show_arrow = not st.away and not st.arrived_at
	hud_arrow:SetHidden(not show_arrow)
	hud_letter:SetHidden(not show_arrow or not SS.saved.guide_hud_letter)
	if show_arrow then
		hud_arrow:SetTextureRotation(st.rel, 0.5, 0.5)
		local aim = abs(st.rel) < ON_TARGET and 1 or 0.8
		hud_arrow:SetColor(r * aim, g * aim, b * aim, Opacity())
		hud_letter:SetText(D.Cardinal(st.heading))
		hud_letter:SetColor(r, g, b, Opacity())
	end
	local title, info, dist, eta = HudText(st)
	hud_title:SetText(title)
	hud_info:SetHidden(dist ~= nil)
	hud_dist:SetHidden(dist == nil)
	hud_eta:SetHidden(dist == nil)
	if dist then
		hud_dist:SetText(dist)
		hud_eta:SetText(eta)
	else
		hud_info:SetText(info)
	end
end

local function HideHud()
	if hud_box then hud_box:SetHidden(true) end
end

local arrows = {}
local ring, label, label_text, label_yaw, label_y
local ring_y, ring_target
local label_at = 0
local RING_EASE = 0.08
local RING_SNAP_CM = 3000
local LABEL_MOVE_CM = 200

local function Arrow(i)
	local flat = arrows[i]
	if flat then return flat end
	flat = SS.GuideWorld.NewFlat(D.Texture("ground"), ARROW_M)
	arrows[i] = flat
	return flat
end

local function HideArrowsFrom(first)
	for i = first, #arrows do arrows[i]:SetHidden(true) end
end

function D.TrimBehind(points, px, pz)
	if #points < 3 then return points end
	local best_k, best_t, best_d2 = 2, 0, math.huge
	for k = 2, #points do
		local a, b = points[k - 1], points[k]
		local vx, vz = b[1] - a[1], b[3] - a[3]
		local len2 = vx * vx + vz * vz
		local t = len2 > 0 and max(0, min(1, ((px - a[1]) * vx + (pz - a[3]) * vz) / len2)) or 0
		local qx, qz = a[1] + vx * t, a[3] + vz * t
		local d2 = (qx - px) ^ 2 + (qz - pz) ^ 2
		if d2 < best_d2 then best_k, best_t, best_d2 = k, t, d2 end
	end
	local a, b = points[best_k - 1], points[best_k]
	local out = { { px, points[1][2], pz } }
	local cut = { a[1] + (b[1] - a[1]) * best_t, a[2] + (b[2] - a[2]) * best_t, a[3] + (b[3] - a[3]) * best_t, a[4] or b[4] }
	if (cut[1] - px) ^ 2 + (cut[3] - pz) ^ 2 > 1 then out[#out + 1] = cut end
	for k = best_k, #points do out[#out + 1] = points[k] end
	return out
end

local function Walk(points, now, place)
	local total = 0
	for k = 2, #points do
		local a, b = points[k - 1], points[k]
		total = total + sqrt((b[1] - a[1]) ^ 2 + (b[3] - a[3]) ^ 2)
	end
	local phase = (now / 1000 * FLOW_MPS) % SPACING_M
	local stop = min(total - 1.5, FAR_M)
	local s = total - (floor((total - START_M + phase) / SPACING_M) * SPACING_M - phase)
	local walked, k, count = 0, 2, 0
	while s <= stop and k <= #points and count < MAX_ARROWS do
		local a, b = points[k - 1], points[k]
		local seg = sqrt((b[1] - a[1]) ^ 2 + (b[3] - a[3]) ^ 2)
		if seg > 0 and s <= walked + seg then
			local t = (s - walked) / seg
			local ux, uz = (b[1] - a[1]) / seg, (b[3] - a[3]) / seg
			count = count + 1
			place(count, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t,
				atan2(-ux, -uz), s, total)
			s = s + SPACING_M
		else
			walked = walked + seg
			k = k + 1
		end
	end
	return count, total
end
D.Walk = Walk

local function ArrowAlpha(s, total)
	local a = 1
	if s < 6 then a = 0.3 + 0.7 * (s / 6) end
	if s > FAR_M * 0.6 then a = a * max(0, 1 - (s - FAR_M * 0.6) / (FAR_M * 0.4)) end
	local left = total - s
	if left < 5 then a = a * max(0, left / 5) end
	return a
end
D.ArrowAlpha = ArrowAlpha

local path_pool, path, along = {}, {}, {}

local function PutPath(i, x, y, z, guessed)
	local p = path_pool[i]
	if not p then
		p = {}
		path_pool[i] = p
	end
	p[1], p[2], p[3], p[4] = x, y, z, guessed
	path[i] = p
end

function D.PathPoints(st)
	local px, py, pz = st.x / 100, st.y / 100, st.z / 100
	local ty = (st.target.level or st.y) / 100
	local route, n = st.route, 0
	if route and #route >= 3 then
		local best_k, best_t, best_d2 = 2, 0, math.huge
		for k = 2, #route do
			local a, b = route[k - 1], route[k]
			local vx, vz = b[1] - a[1], b[3] - a[3]
			local len2 = vx * vx + vz * vz
			local t = len2 > 0 and max(0, min(1, ((px - a[1]) * vx + (pz - a[3]) * vz) / len2)) or 0
			local qx, qz = a[1] + vx * t, a[3] + vz * t
			local d2 = (qx - px) ^ 2 + (qz - pz) ^ 2
			if d2 < best_d2 then best_k, best_t, best_d2 = k, t, d2 end
		end
		local a, b = route[best_k - 1], route[best_k]
		n = 1
		PutPath(1, px, py, pz)
		local cx, cz = a[1] + (b[1] - a[1]) * best_t, a[3] + (b[3] - a[3]) * best_t
		if (cx - px) ^ 2 + (cz - pz) ^ 2 > 1 then
			n = 2
			PutPath(2, cx, a[2] + (b[2] - a[2]) * best_t, cz, a[4] or b[4])
		end
		for k = best_k, #route do
			local r = route[k]
			n = n + 1
			PutPath(n, r[1], r[2], r[3], r[4])
		end
	elseif route then
		for k = 1, #route do
			local r = route[k]
			n = n + 1
			PutPath(n, r[1], r[2], r[3], r[4])
		end
	else
		PutPath(1, px, py, pz)
		PutPath(2, st.target.x / 100, ty, st.target.z / 100)
		n = 2
	end
	for k = n + 1, #path do path[k] = nil end
	local total = 0
	along[1] = 0
	for k = 2, n do
		local a, b = path[k - 1], path[k]
		local dx, dz = b[1] - a[1], b[3] - a[3]
		total = total + sqrt(dx * dx + dz * dz)
		along[k] = total
	end
	for k = 1, n do
		local p = path[k]
		if k == 1 then
			p[2] = py
		elseif k == n or p[4] then
			p[2] = py + (ty - py) * (total > 0 and along[k] / total or 1)
		end
	end
	return path
end

local arrow_r, arrow_g, arrow_b, arrow_opacity = 1, 1, 1, 1

local function PlaceArrow(i, x, y, z, yaw, s, total)
	Arrow(i):SetPosition(x * 100, (y + LIFT_M) * 100, z * 100):SetYaw(yaw)
		:SetColor(arrow_r, arrow_g, arrow_b, arrow_opacity * ArrowAlpha(s, total)):SetHidden(false)
end

local function UpdateGround(points, now)
	arrow_r, arrow_g, arrow_b = D.Color("ground")
	arrow_opacity = Opacity()
	HideArrowsFrom(Walk(points, now, PlaceArrow) + 1)
end

function D.FaceYaw(tx, tz, px, pz)
	return atan2(px - tx, pz - tz)
end

local screen_labels = {}

local function ScreenLabel(key)
	local l = screen_labels[key]
	if l then return l end
	local wm = WINDOW_MANAGER
	local top = wm:CreateTopLevelWindow("APHSearchGuideName" .. key)
	top:SetDimensions(10, 10)
	local lbl = wm:CreateControl("$(parent)Text", top, CT_LABEL)
	lbl:SetAnchor(BOTTOM, top, CENTER, 0, 0)
	lbl:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
	lbl:SetFont("ZoFontWinH4")
	local fragment = ZO_HUDFadeSceneFragment:New(top)
	HUD_SCENE:AddFragment(fragment)
	HUD_UI_SCENE:AddFragment(fragment)
	l = { top = top, label = lbl }
	screen_labels[key] = l
	return l
end

local function ShowScreenLabel(key, text, x, y, z, r, g, b)
	local l = ScreenLabel(key)
	local sx, sy = SS.GuideWorld.Project(x, y, z)
	if not sx then
		l.label:SetHidden(true)
		l.x = nil
		return
	end
	if not l.x or abs(sx - l.x) > HUD_SNAP_PX or abs(sy - l.y) > HUD_SNAP_PX then
		l.x, l.y = sx, sy
	else
		l.x, l.y = l.x + (sx - l.x) * HUD_EASE, l.y + (sy - l.y) * HUD_EASE
	end
	local rx, ry = floor(l.x + 0.5), floor(l.y + 0.5)
	if rx ~= l.px or ry ~= l.py then
		l.px, l.py = rx, ry
		l.top:ClearAnchors()
		l.top:SetAnchor(CENTER, GuiRoot, CENTER, rx, ry)
	end
	l.label:SetText(text)
	l.label:SetColor(r, g, b, Opacity())
	l.label:SetHidden(false)
end

local function HideScreenLabel(key)
	local l = screen_labels[key]
	if l then
		l.label:SetHidden(true)
		l.x = nil
	end
end

local function WorldText(old, text, x, y, z, yaw, color, size)
	if old then old:Wipe() end
	local t = LibImplex.Text(text, CENTER, LibImplex.Vector({ x, y, z }), { 0, yaw, 0, false }, size, color, TEXT_WIDTH)
	t:Render()
	return t
end

local function UpdateDestination(st, now, points)
	local target = st.target
	local ground = points[#points][2] * 100
	if ring_target ~= target or not ring_y or abs(ground - ring_y) > RING_SNAP_CM then
		ring_target, ring_y = target, ground
	else
		ring_y = ring_y + (ground - ring_y) * RING_EASE
	end
	local tx, ty, tz = target.x, ring_y, target.z
	if not ring then ring = SS.GuideWorld.NewFlat(D.Texture("ring"), RING_M) end
	local r, g, b = D.Color("ring")
	ring:SetSize(RING_M * (1 + 0.08 * math.sin(now / 300)))
	ring:SetPosition(tx, ty + LIFT_M * 100, tz):SetColor(r, g, b, Opacity()):SetHidden(false)

	local text = target.from and (target.from .. "\n" .. (target.label or "")) or (target.label or "")
	if not SS.saved.guide_label_3d then
		if label then label:Wipe() label, label_text = nil, nil end
		HideScreenLabel("Target")
		return
	end
	if not SS.Guide.HasLibImplex() then
		ShowScreenLabel("Target", text, tx, ty + LABEL_LIFT_M * 100, tz, r, g, b)
		return
	end
	local yaw = D.FaceYaw(tx, tz, st.x, st.z)
	local turned = not label_yaw or abs(SS.Guide.Wrap(yaw - label_yaw)) > FACE_TURN
	local moved = not label_y or abs(ty - label_y) > LABEL_MOVE_CM
	if text ~= label_text or moved or (turned and now - label_at >= FACE_EVERY_MS) then
		label_at = now
		label = WorldText(label, text, tx, ty + LABEL_LIFT_M * 100, tz, yaw, { r, g, b }, 1.2)
		label_text, label_yaw, label_y = text, yaw, ty
	end
end

local function HideWorld()
	HideArrowsFrom(1)
	if ring then ring:SetHidden(true) end
	if label then label:Wipe() label, label_text, label_yaw, label_y = nil, nil, nil, nil end
	ring_target, ring_y = nil, nil
	HideScreenLabel("Target")
end

local mark_objects = {}

function D.ShowMark(key, mark, playerY)
	local entry = mark_objects[key]
	if not entry then
		entry = { ring = SS.GuideWorld.NewFlat(D.Texture("ring"), RING_M * 0.8) }
		mark_objects[key] = entry
	end
	if entry.mx ~= mark.x or entry.mz ~= mark.z then entry.mx, entry.mz, entry.level = mark.x, mark.z, nil end
	local y = mark.y or entry.level or playerY or 0
	entry.level = y
	local r, g, b = D.Color("marks")
	entry.ring:SetPosition(mark.x, y + LIFT_M * 100, mark.z):SetColor(r, g, b, Opacity()):SetHidden(false)
	local text = mark.name .. "\n" .. (mark.label or "")
	if not SS.Guide.HasLibImplex() then
		ShowScreenLabel("Mark" .. key, text, mark.x, y + LABEL_LIFT_M * 100, mark.z, r, g, b)
		return true
	end
	local _, px, _, pz = GetUnitRawWorldPosition("player")
	local yaw = D.FaceYaw(mark.x, mark.z, px, pz)
	if text ~= entry.text or not entry.yaw or abs(SS.Guide.Wrap(yaw - entry.yaw)) > FACE_TURN then
		entry.label = WorldText(entry.label, text, mark.x, y + LABEL_LIFT_M * 100, mark.z, yaw, { r, g, b }, 1)
		entry.text, entry.yaw = text, yaw
	end
	return true
end

function D.HideMark(key)
	HideScreenLabel("Mark" .. tostring(key))
	local entry = mark_objects[key]
	if not entry then return end
	entry.ring:SetHidden(true)
	if entry.label then entry.label:Wipe() end
	entry.label, entry.text, entry.yaw = nil, nil, nil
end

function D.HideAllMarks()
	for key in pairs(mark_objects) do D.HideMark(key) end
end

function D.Show()
	if WantsHud() then BuildHud() end
end

function D.Update(st, now)
	if WantsHud() then UpdateHud(st) else HideHud() end
	if WantsGround() and not st.away then
		local points = D.PathPoints(st)
		if st.arrived_at then HideArrowsFrom(1) else UpdateGround(points, now) end
		UpdateDestination(st, now, points)
	else
		HideWorld()
	end
	if SS.GuideMap then SS.GuideMap.Update(st, now) end
end

function D.Hide()
	HideHud()
	HideWorld()
	if SS.GuideMap then SS.GuideMap.Clear() end
end

local function RefreshTextures()
	if hud_arrow then hud_arrow:SetTexture(D.Texture("hud")) end
	local ground = D.Texture("ground")
	for i = 1, #arrows do arrows[i]:SetTexture(ground) end
	local ring_tex = D.Texture("ring")
	if ring then ring:SetTexture(ring_tex) end
	for _, entry in pairs(mark_objects) do entry.ring:SetTexture(ring_tex) end
end
D.RefreshTextures = RefreshTextures

function D.Apply()
	RefreshTextures()
	if hud then PlaceTop() end
	if not WantsHud() then HideHud() end
	if not WantsGround() then HideWorld() end
end
