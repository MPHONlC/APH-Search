--[[
    Copyright © 2026 @APHONlC. All rights reserved.

    No copying, modification, distribution, or sale without prior written permission.
    AI/ML ingestion and training are strictly prohibited (TDM opt-out).

    See LICENSE.md for full terms and maintenance exceptions.
]]

local SS = APHSearchCore
local G = {}
SS.Guide = G

local sqrt, abs, atan2, floor, pi = math.sqrt, math.abs, math.atan2, math.floor, math.pi
local GetUnitRawWorldPosition, GetPlayerCameraHeading = GetUnitRawWorldPosition, GetPlayerCameraHeading
local GetFrameTimeMilliseconds = GetFrameTimeMilliseconds

local NS = SS.name .. "Guide"
local CAL_CM = 10000
local MAP_SLACK = 0.004
local FRAME_SLACK = 0.01
local FRAME_MIN_CM = 1500
local FRAME_RATIO = 1.25
local TO_MAP_MS = 1000
local LABEL_WINDOW_MS = 4000
local ROUTE_EVERY_MS = 400
local ROUTE_KEEP_MS = 5000
local ROUTE_KEEP_M = 20
local RECORD_EVERY_MS = 250
local ARRIVED_HOLD_MS = 4000
local CRUMB_EVERY_MS = 500

G.STYLE_GROUND, G.STYLE_HUD, G.STYLE_BOTH = "ground", "hud", "both"
G.ARRIVE_M = 8
local LEVEL_LOCK_M = 6

local st = {
	target = nil,
	zoneId = 0, x = 0, y = 0, z = 0,
	heading = 0, dist = 0, rel = 0, speed = 0, eta = nil,
	route = nil, away = false, arrived_at = nil,
}
G.state = st

local pending_label, pending_label_at, pending_kind
local waypoint_zone, waypoint_node
local running = false
local last_route_ms, last_record_ms, last_tick_ms, last_full_route_ms = 0, 0, 0, 0
local last_px, last_pz
local last_crumb_ms = 0

local function Wrap(angle)
	while angle > pi do angle = angle - 2 * pi end
	while angle < -pi do angle = angle + 2 * pi end
	return angle
end
G.Wrap = Wrap

function G.IsEnabled()
	return SS.saved and SS.saved.guide_enabled == true
end

function G.Style()
	return SS.saved.guide_style or G.STYLE_BOTH
end

function G.HasLibImplex()
	return type(LibImplex) == "table" and type(LibImplex.Objects) == "table" and type(LibImplex.Text) == "table"
end

local function WorldMapBrowsing()
	return ZO_WorldMap_IsWorldMapShowing and ZO_WorldMap_IsWorldMapShowing() or false
end

local rects = {}
local RECT_SLACK = 0.001

local function Rect(zoneId)
	local rect = rects[zoneId]
	if rect ~= nil then return rect end
	rect = false
	local mapId = GetMapIdByZoneId(zoneId)
	if mapId and mapId ~= 0 then
		local x, z, w, h = GetUniversallyNormalizedMapInfo(mapId)
		if w and h and w > 0 and h > 0 then rect = { x, z, w, h } end
	end
	rects[zoneId] = rect
	return rect
end

function G.Contains(outer, inner)
	if not outer or not inner or outer == inner then return false end
	local o, i = Rect(outer), Rect(inner)
	if not o or not i or i[3] >= o[3] then return false end
	return i[1] >= o[1] - RECT_SLACK and i[2] >= o[2] - RECT_SLACK
		and i[1] + i[3] <= o[1] + o[3] + RECT_SLACK and i[2] + i[4] <= o[2] + o[4] + RECT_SLACK
end

function G.SameZone(a, b)
	if not a or not b or a == 0 or b == 0 or a == b then return true end
	local pa, pb = GetParentZoneId(a), GetParentZoneId(b)
	return pa == b or pb == a or (pa == pb and pa ~= 0)
end

local function MapZone()
	local index = GetCurrentMapZoneIndex()
	return index and GetZoneId(index) or nil
end
G.MapZone = MapZone

function G.ShownMapZone()
	local mapId = GetCurrentMapId and GetCurrentMapId() or 0
	if mapId and mapId ~= 0 then
		local _, _, _, zoneIndex = GetMapInfoById(mapId)
		if zoneIndex and zoneIndex > 0 then
			local zoneId = GetZoneId(zoneIndex)
			if zoneId and zoneId ~= 0 then return zoneId end
		end
	end
	local zoneId = MapZone()
	if zoneId and zoneId ~= 0 then return zoneId end
	return nil
end

local function Probe(fn, zoneId, qx, qy, qz, wx, wy, wz, px, py)
	if not fn or not zoneId or zoneId == 0 or not qx then return nil end
	local x0, y0 = fn(zoneId, qx, qy, qz)
	if not x0 or not y0 or abs(px - x0) > MAP_SLACK or abs(py - y0) > MAP_SLACK then return nil end
	local x1, y1 = fn(zoneId, qx + CAL_CM, qy, qz)
	local x2, y2 = fn(zoneId, qx, qy, qz + CAL_CM)
	if not (x1 and y1 and x2 and y2) then return nil end
	local ax, az = x1 - x0, y2 - y0
	if abs(ax) < 1e-9 or abs(az) < 1e-9 then return nil end
	if abs(y1 - y0) > abs(ax) * 0.02 or abs(x2 - x0) > abs(az) * 0.02 then return nil end
	return { wx = wx, wy = wy, wz = wz, x0 = x0, y0 = y0, ax = ax, az = az, cm = CAL_CM }
end

local function Direct(zoneId, wx, wy, wz, px, py)
	local cal = Probe(GetRawNormalizedWorldPosition, zoneId, wx, wy, wz, wx, wy, wz, px, py)
	if cal or not GetUnitWorldPosition or not GetNormalizedWorldPosition then return cal end
	local zone, qx, qy, qz = GetUnitWorldPosition("player")
	return Probe(GetNormalizedWorldPosition, zone, qx, qy, qz, wx, wy, wz, px, py)
end

local function Frames()
	local saved = SS.saved.guide_map_frames
	if not saved then
		saved = {}
		SS.saved.guide_map_frames = saved
	end
	return saved
end

local function CurrentMap()
	return GetCurrentMapId and GetCurrentMapId() or 0
end

local function FromFrame(f, wx, wy, wz)
	return { wx = wx, wy = wy, wz = wz, x0 = f[4] + (wx - f[2]) * f[6], y0 = f[5] + (wz - f[3]) * f[7],
		ax = f[6] * CAL_CM, az = f[7] * CAL_CM, cm = CAL_CM, learned = true }
end

function G.MapCalibration()
	local zoneId, wx, wy, wz = GetUnitRawWorldPosition("player")
	if not zoneId or zoneId == 0 or not G.SameZone(MapZone(), zoneId) then return nil end
	local px, py = GetMapPlayerPosition("player")
	if not px then return nil end
	local mapId = CurrentMap()
	local cal = Direct(zoneId, wx, wy, wz, px, py)
	if not cal then
		local f = Frames()[mapId]
		if not f or f[1] ~= zoneId then return nil end
		cal = FromFrame(f, wx, wy, wz)
		if abs(px - cal.x0) > FRAME_SLACK or abs(py - cal.y0) > FRAME_SLACK then return nil end
	end
	cal.zoneId, cal.mapId = zoneId, mapId
	return cal
end

local player_map, player_inside, last_to_map_ms = nil, false, -math.huge

function G.ToPlayerMap(force)
	local now = GetFrameTimeMilliseconds()
	if WorldMapBrowsing() then return player_map end
	if not force and player_map and CurrentMap() == player_map and now - last_to_map_ms < TO_MAP_MS
		and G.SameZone(MapZone(), (GetUnitRawWorldPosition("player"))) then return player_map end
	last_to_map_ms = now
	if SetMapToPlayerLocation() == SET_MAP_RESULT_MAP_CHANGED and CALLBACK_MANAGER then
		CALLBACK_MANAGER:FireCallbacks("OnWorldMapChanged")
	end
	player_map = CurrentMap()
	local zoneId, wx, wy, wz = GetUnitRawWorldPosition("player")
	local px, py = GetMapPlayerPosition("player")
	player_inside = px ~= nil and zoneId ~= nil and Direct(zoneId, wx, wy, wz, px, py) == nil
	return player_map
end

function G.PlayerMap() return player_map, player_inside end

local anchor

function G.LearnFrame()
	if WorldMapBrowsing() then return false end
	local mapId = CurrentMap()
	if mapId == 0 or mapId ~= player_map then
		G.ToPlayerMap()
		return false
	end
	local zoneId, wx, wy, wz = GetUnitRawWorldPosition("player")
	local px, py = GetMapPlayerPosition("player")
	if not zoneId or zoneId == 0 or not px or px <= 0 or px >= 1 or py <= 0 or py >= 1 then return false end
	if Direct(zoneId, wx, wy, wz, px, py) then return false end
	local frames = Frames()
	local f = frames[mapId]
	if f and f[1] == zoneId then
		local cal = FromFrame(f, wx, wy, wz)
		if abs(px - cal.x0) <= FRAME_SLACK and abs(py - cal.y0) <= FRAME_SLACK then return true end
		frames[mapId] = nil
	end
	if not anchor or anchor.map ~= mapId or anchor.zone ~= zoneId then
		anchor = { map = mapId, zone = zoneId, wx = wx, wz = wz, px = px, py = py }
		return false
	end
	local dx, dz = wx - anchor.wx, wz - anchor.wz
	local sx = abs(dx) >= FRAME_MIN_CM and (px - anchor.px) / dx or nil
	local sz = abs(dz) >= FRAME_MIN_CM and (py - anchor.py) / dz or nil
	if not sx and not sz then return false end
	if not (sx and sz) then
		if math.max(abs(dx), abs(dz)) < FRAME_MIN_CM * 2 then return false end
		sx, sz = sx or sz, sz or sx
	end
	if sx <= 0 or sz <= 0 or sx / sz > FRAME_RATIO or sz / sx > FRAME_RATIO then
		anchor = nil
		return false
	end
	frames[mapId] = { zoneId, anchor.wx, anchor.wz, anchor.px, anchor.py, sx, sz }
	anchor = nil
	if SS.GuideMap then SS.GuideMap.RecordingsChanged() end
	return true
end

local function MapRect(mapId)
	local x, z, w, h = GetUniversallyNormalizedMapInfo(mapId)
	if not w or not h or w <= 0 or h <= 0 then return nil end
	return x, z, w, h
end

local function Nested(zoneId, mapId)
	local zoneMap = GetMapIdByZoneId(zoneId)
	if not zoneMap or zoneMap == 0 then return nil end
	local zx, zz, zw, zh = MapRect(zoneMap)
	local sx, sz, sw, sh = MapRect(mapId)
	if not zx or not sx then return nil end
	local inner = sx >= zx - RECT_SLACK and sz >= zz - RECT_SLACK and sx + sw <= zx + zw + RECT_SLACK and sz + sh <= zz + zh + RECT_SLACK
	local outer = zx >= sx - RECT_SLACK and zz >= sz - RECT_SLACK and zx + zw <= sx + sw + RECT_SLACK and zz + zh <= sz + sh + RECT_SLACK
	if not inner and not outer then return nil end
	local _, wx, wy, wz = GetUnitRawWorldPosition("player")
	local x0, y0 = GetRawNormalizedWorldPosition(zoneId, wx, wy, wz)
	local x1 = GetRawNormalizedWorldPosition(zoneId, wx + CAL_CM, wy, wz)
	local _, y2 = GetRawNormalizedWorldPosition(zoneId, wx, wy, wz + CAL_CM)
	if not (x0 and y0 and x1 and y2) or abs(x1 - x0) < 1e-9 or abs(y2 - y0) < 1e-9 then return nil end
	return { wx = wx, wy = wy, wz = wz, cm = CAL_CM, nested = true,
		x0 = (x0 * zw + zx - sx) / sw, y0 = (y0 * zh + zz - sz) / sh,
		ax = (x1 - x0) * zw / sw, az = (y2 - y0) * zh / sh }
end

function G.FrameFor(mapId)
	if not mapId or mapId == 0 then return nil end
	local zoneId, wx, wy, wz = GetUnitRawWorldPosition("player")
	if not zoneId or zoneId == 0 then return nil end
	local _, _, _, zoneIndex = GetMapInfoById(mapId)
	local mapZone = zoneIndex and zoneIndex > 0 and GetZoneId(zoneIndex) or nil
	if mapZone and mapZone ~= 0 and not G.SameZone(mapZone, zoneId) then return nil end
	local cal = CurrentMap() == mapId and G.MapCalibration() or nil
	if not cal then
		local f = Frames()[mapId]
		if f and f[1] == zoneId then cal = FromFrame(f, wx, wy, wz) end
	end
	cal = cal or Nested(zoneId, mapId)
	if not cal then return nil end
	cal.zoneId, cal.mapId = zoneId, mapId
	return cal
end

function G.FrameToMap(cal, x, z)
	return cal.x0 + (x - cal.wx) / cal.cm * cal.ax, cal.y0 + (z - cal.wz) / cal.cm * cal.az
end

function G.MapToWorld(mx, my)
	local cal = G.MapCalibration()
	if not cal then return nil end
	return cal.zoneId, cal.wx + (mx - cal.x0) / cal.ax * CAL_CM, cal.wz + (my - cal.y0) / cal.az * CAL_CM, cal.wy
end

function G.SetNextLabel(label, kind)
	pending_label, pending_label_at, pending_kind = label, GetFrameTimeMilliseconds(), kind
end

local function TakeLabel()
	if pending_label and GetFrameTimeMilliseconds() - (pending_label_at or 0) <= LABEL_WINDOW_MS then
		local label, kind = pending_label, pending_kind
		pending_label, pending_kind = nil, nil
		return label, kind
	end
	return nil, nil
end

function G.ResolveWaypoint(browsing)
	local playerZone = GetUnitRawWorldPosition("player")
	local home = waypoint_zone ~= nil and G.SameZone(waypoint_zone, playerZone)
	if not browsing and G.SameZone(waypoint_zone, playerZone) then G.ToPlayerMap() end
	local mx, my = GetMapPlayerWaypoint()
	if not mx or (mx == 0 and my == 0) then return true, nil end
	local label, kind = TakeLabel()
	local outside = mx < -0.02 or mx > 1.02 or my < -0.02 or my > 1.02
	if not home and (outside or not G.SameZone(waypoint_zone, playerZone)) then
		local far = { own = true, far = true, destZoneId = waypoint_zone, node = waypoint_node,
			label = label or SS.L("GUIDE_YOUR_WAYPOINT"), kind = kind or "waypoint" }
		local hop = G.PlanHop(far)
		if not hop then G.NoTravelKnown(far) end
		return true, hop
	end
	if outside and player_inside and not browsing then return true, nil end
	if not G.SameZone(MapZone(), playerZone) then
		if browsing then
			if label then G.SetNextLabel(label, kind) end
			return false, nil
		end
		G.ToPlayerMap(true)
		mx, my = GetMapPlayerWaypoint()
	end
	if not browsing then G.LearnFrame() end
	local zoneId, x, z, y = G.MapToWorld(mx, my)
	if not zoneId then
		if label then G.SetNextLabel(label, kind) end
		return false, nil
	end
	local target = {
		own = true, zoneId = zoneId, x = x, z = z, y = nil, groundY = y,
		label = label or SS.L("GUIDE_YOUR_WAYPOINT"), kind = kind or "waypoint",
		mapX = floor(mx * 100 + 0.5), mapY = floor(my * 100 + 0.5),
	}
	SS.GuideRoads.Settle(target, zoneId, CurrentMap(), mx, my)
	return true, target
end

function G.PlanHop(far)
	local zoneId, px, _, pz = GetUnitRawWorldPosition("player")
	local dest = far.destZoneId
	if not dest or dest == 0 or G.SameZone(dest, zoneId) then return nil end
	return G.PlanWayshrineHop(far, zoneId, px, pz)
end

function G.PlanWayshrineHop(far, zoneId, px, pz)
	local travel = SS.GuideTravel
	if not travel then return nil end
	local node = far.node or travel.DestinationNode(far.destZoneId)
	if not node then return nil end
	if not G.SameZone(MapZone(), zoneId) then G.ToPlayerMap(true) end
	local shrine, sx, sz = travel.NearestWayshrine(zoneId, px, pz)
	if not shrine then return nil end
	local _, shrine_name = GetFastTravelNodeInfo(shrine)
	local _, node_name = GetFastTravelNodeInfo(node)
	shrine_name, node_name = zo_strformat("<<1>>", shrine_name), zo_strformat("<<1>>", node_name)
	return { own = true, hop = true, via = "wayshrine", node = node, zoneId = zoneId, x = sx, z = sz,
		destZoneId = far.destZoneId, kind = far.kind, final = far.label,
		label = shrine_name, arriveText = SS.L("GUIDE_USE_WAYSHRINE", node_name) }
end

function G.SetLevel(target, wy, dist)
	if target.member then
		target.level = target.groundY or wy
		return target.level
	end
	if not target.level then target.level = target.groundY or wy end
	if not target.level_locked and dist <= LEVEL_LOCK_M then target.level, target.level_locked = wy, true end
	return target.level
end

local told_about
function G.NoTravelKnown(far)
	local dest = far.destZoneId
	if not dest or dest == 0 or G.SameZone(dest, (GetUnitRawWorldPosition("player"))) then return false end
	local key = tostring(dest) .. ":" .. tostring(far.label)
	if told_about == key then return false end
	told_about = key
	if SS.SuggestTravel then SS.SuggestTravel(dest) end
	return true
end

function G.PathLength(points)
	local total = 0
	for k = 2, #points do
		total = total + sqrt((points[k][1] - points[k - 1][1]) ^ 2 + (points[k][3] - points[k - 1][3]) ^ 2)
	end
	return total
end

function G.RouteFits(route, px, pz, tx, tz)
	if not route or #route < 2 then return false end
	local last = route[#route]
	if abs(last[1] - tx) > 1 or abs(last[3] - tz) > 1 then return false end
	local best = math.huge
	for k = 2, #route do
		local a, b = route[k - 1], route[k]
		local vx, vz = b[1] - a[1], b[3] - a[3]
		local len2 = vx * vx + vz * vz
		local t = len2 > 0 and math.max(0, math.min(1, ((px - a[1]) * vx + (pz - a[3]) * vz) / len2)) or 0
		local d2 = (a[1] + vx * t - px) ^ 2 + (a[3] + vz * t - pz) ^ 2
		if d2 < best then best = d2 end
	end
	return best <= ROUTE_KEEP_M * ROUTE_KEEP_M
end

function G.FollowMember(target, zoneId, now)
	local mz, mx, my, mzz = GetUnitRawWorldPosition(target.member)
	if not mz or mz == 0 then return false end
	if G.SameZone(mz, zoneId) or not IsUnitWorldMapPositionBreadcrumbed(target.member) then
		target.zoneId, target.x, target.groundY, target.z, target.crumb = mz, mx, my, mzz, nil
		return true
	end
	if now - last_crumb_ms < CRUMB_EVERY_MS then return false end
	last_crumb_ms = now
	local bx, by = GetMapPlayerPosition(target.member)
	local cz, cx, cwz = G.MapToWorld(bx, by)
	if not cz then return false end
	target.zoneId, target.x, target.z, target.groundY, target.crumb = cz, cx, cwz, nil, true
	return true
end

local function Draw() return SS.GuideDraw end
local function Group() return SS.GuideGroup end

local function StopLoop()
	if not running then return end
	running = false
	EVENT_MANAGER:UnregisterForUpdate(NS)
end

local function Tick()
	local target = st.target
	if not target then
		StopLoop()
		return
	end
	local now = GetFrameTimeMilliseconds()
	local dt = (now - last_tick_ms) / 1000
	last_tick_ms = now
	local zoneId, wx, wy, wz = GetUnitRawWorldPosition("player")
	st.zoneId, st.x, st.y, st.z = zoneId, wx, wy, wz
	st.heading = GetPlayerCameraHeading()
	if target.member then G.FollowMember(target, zoneId, now) end

	if now - last_record_ms >= RECORD_EVERY_MS then
		last_record_ms = now
		G.LearnFrame()
		if SS.saved.guide_learn_roads then SS.GuideRoads.Record(zoneId, wx / 100, wy / 100, wz / 100) end
	end

	if target.far or target.zoneId ~= zoneId then
		st.away, st.route, st.eta = true, nil, nil
		Draw().Update(st, now)
		return
	end
	st.away = false

	if last_px and dt > 0 and dt < 1 then
		local moved = sqrt((wx - last_px) ^ 2 + (wz - last_pz) ^ 2) / 100
		st.speed = st.speed + (moved / dt - st.speed) * math.min(1, dt * 2)
	end
	last_px, last_pz = wx, wz

	local dx, dz = target.x - wx, target.z - wz
	st.dist = sqrt(dx * dx + dz * dz) / 100
	G.SetLevel(target, wy, st.dist)
	st.rel = Wrap(atan2(-dx, -dz) - st.heading)
	st.eta = st.speed > 0.8 and st.dist / st.speed or nil

	if now - last_route_ms >= ROUTE_EVERY_MS then
		last_route_ms = now
		local tx, tz = target.x / 100, target.z / 100
		local fits = G.RouteFits(st.route, wx / 100, wz / 100, tx, tz)
		if not fits or now - last_full_route_ms >= ROUTE_KEEP_MS then
			last_full_route_ms = now
			local ty = target.settled == "walked" and target.groundY and target.groundY / 100 or nil
			local route = SS.GuideRoads.Route(zoneId, wx / 100, wy / 100, wz / 100, tx, tz, ty)
			if not fits then
				st.route = route
			elseif route then
				local left = G.PathLength(Draw().TrimBehind(st.route, wx / 100, wz / 100))
				if G.PathLength(route) < left * 0.9 then st.route = route end
			end
		end
	end

	if st.dist <= G.ARRIVE_M and not target.member then
		if not st.arrived_at then
			st.arrived_at = now
			if target.own and not target.hop and not target.quest and SS.saved.guide_clear_on_arrival then RemovePlayerWaypoint() end
		elseif not target.hop and not target.member and not target.quest and now - st.arrived_at > ARRIVED_HOLD_MS then
			G.ClearTarget()
			return
		end
	else
		st.arrived_at = nil
	end
	Draw().Update(st, now)
end
G.Tick = Tick

local function StartLoop()
	if running then return end
	running = true
	last_tick_ms = GetFrameTimeMilliseconds()
	last_px, last_pz, last_route_ms, last_full_route_ms = nil, nil, 0, 0
	EVENT_MANAGER:RegisterForUpdate(NS, 0, Tick)
end

function G.SetTarget(target)
	st.target = target
	st.route, st.arrived_at, st.speed, st.eta = nil, nil, 0, nil
	if target then
		Draw().Show(target)
		StartLoop()
	else
		StopLoop()
		Draw().Hide()
	end
	if target == nil or target.own then
		local group = Group()
		if group then group.ShareTarget(target) end
	end
end

function G.ClearTarget()
	G.SetTarget(nil)
	local fallback = Group() and Group().LeaderMarkTarget() or nil
	if fallback then G.SetTarget(fallback) end
end

function G.GuideToMark(mark)
	if not mark then return false end
	G.SetTarget({
		own = false, zoneId = mark.zoneId, x = mark.x, z = mark.z, y = mark.y,
		label = mark.label, kind = mark.kind, from = mark.name,
	})
	return true
end

local function TryWaypoint()
	local browsing = WorldMapBrowsing()
	if browsing and not G.SameZone(MapZone(), (GetUnitRawWorldPosition("player"))) then return false end
	local done, target = G.ResolveWaypoint(browsing)
	if not done then return false end
	if target then
		G.SetTarget(target)
	elseif st.target and st.target.own then
		G.ClearTarget()
	end
	return true
end

function G.RefreshWaypoint()
	if not G.IsEnabled() then return false end
	if TryWaypoint() then return true end
	LibAPH.ScheduleWait(NS .. "Resolve", function() return not G.IsEnabled() or TryWaypoint() end)
	return false
end

local function OnMapPing(_, eventType, pinType, _, _, _, isOwner)
	if pinType ~= MAP_PIN_TYPE_PLAYER_WAYPOINT or not isOwner then return end
	if eventType == PING_EVENT_REMOVED then
		if st.target and st.target.own and not st.target.quest then G.ClearTarget() end
		return
	end
	local zoneIndex = GetCurrentMapZoneIndex and GetCurrentMapZoneIndex()
	waypoint_zone = zoneIndex and GetZoneId(zoneIndex) or nil
	waypoint_node = nil
	if not G.SameZone(waypoint_zone, (GetUnitRawWorldPosition("player"))) and SS.GuideTravel then
		local mx, my = GetMapPlayerWaypoint()
		local way = SS.GuideTravel.WayInto(waypoint_zone, mx, my)
		if way and way.kind == "wayshrine" then waypoint_node = way.node end
	end
	if SS.GuideTrack then SS.GuideTrack.Stop() end
	G.RefreshWaypoint()
end

local function OnActivated()
	G.ToPlayerMap(true)
	if st.target and st.target.own then
		st.target = nil
		StopLoop()
		Draw().Hide()
	end
	G.RefreshWaypoint()
	local group = Group()
	if group then group.OnActivated() end
end

local function OnZoneChanged()
	G.ToPlayerMap(true)
	local target = st.target
	if target and target.own and not target.hop and not target.quest then G.RefreshWaypoint() end
end

local watching = false

function G.Apply()
	local on = G.IsEnabled()
	if on and not watching then
		watching = true
		EVENT_MANAGER:RegisterForEvent(NS, EVENT_MAP_PING, OnMapPing)
		EVENT_MANAGER:RegisterForEvent(NS, EVENT_PLAYER_ACTIVATED, OnActivated)
		EVENT_MANAGER:RegisterForEvent(NS, EVENT_ZONE_CHANGED, OnZoneChanged)
		G.RefreshWaypoint()
	elseif not on and watching then
		watching = false
		EVENT_MANAGER:UnregisterForEvent(NS, EVENT_MAP_PING)
		EVENT_MANAGER:UnregisterForEvent(NS, EVENT_PLAYER_ACTIVATED)
		EVENT_MANAGER:UnregisterForEvent(NS, EVENT_ZONE_CHANGED)
		G.SetTarget(nil)
	end
	if Draw() and Draw().Apply then Draw().Apply() end
	if SS.GuideMap then SS.GuideMap.Apply() end
	if not on and SS.GuideTrack then SS.GuideTrack.Stop() end
	if Group() then Group().Apply() end
	return on
end

function G.Toggle()
	SS.saved.guide_enabled = not G.IsEnabled()
	G.Apply()
	SS.Print(G.IsEnabled() and SS.L("GUIDE_IS_ON") or SS.L("GUIDE_IS_OFF"), true)
end

function G.Command(args)
	local word = zo_strlower(zo_strtrim(args or ""))
	if word == "clear" then
		if SS.GuideTrack then SS.GuideTrack.Stop() end
		if st.target and st.target.own then RemovePlayerWaypoint() end
		G.ClearTarget()
		return
	end
	if word == "record" and SS.GuideRecord then return SS.GuideRecord.Toggle() end
	if G.IsEnabled() and SS.GuideTrack then
		if word == "quest" then return SS.GuideTrack.StartQuest() end
		if word == "member" or word == "next" then return SS.GuideTrack.NextMember() end
	end
	G.Toggle()
end

function G.FormatEta(seconds)
	if not seconds or seconds ~= seconds or seconds > 5999 then return nil end
	seconds = floor(seconds + 0.5)
	return string.format("%d:%02d", floor(seconds / 60), seconds % 60)
end

function G.FormatDistance(meters)
	if meters >= 1000 then return string.format("%.1f km", meters / 1000) end
	return string.format("%d m", floor(meters + 0.5))
end
