--[[
    Copyright © 2026 @APHONlC. All rights reserved.

    No copying, modification, distribution, or sale without prior written permission.
    AI/ML ingestion and training are strictly prohibited (TDM opt-out).

    See LICENSE.md for full terms and maintenance exceptions.
]]

local SS = APHSearchCore
local Roads = {}
SS.GuideRoads = Roads

local sqrt, floor, ceil, abs = math.sqrt, math.floor, math.ceil, math.abs

local STEP_M = 3.5
local SNAP_M = 2
local LINK_MAX_M = 14
local LEVEL_M = 1.8
local MAX_RISE = 1.1
local CELL_M = 10
local MAX_POINTS = 6000
local START_M = 25
local END_M = 40
local OFFROAD = 1.6
local MAX_EXPAND = 2500
local SHIPPED_CELL_M = 25
local SHIPPED_START_M = 60
local SHIPPED_END_M = 120
local MAP_SCALE = 8280
local BLOCK_GRID = 64
local SETTLE_M = 30
local SETTLE_FAR_M = 400

Roads.STEP_M, Roads.SNAP_M, Roads.LINK_MAX_M, Roads.MAX_POINTS = STEP_M, SNAP_M, LINK_MAX_M, MAX_POINTS
Roads.MAX_EXPAND = MAX_EXPAND

local zone_id, entry, pts, links, grid
local learned
local last_index, last_x, last_y, last_z

local function CellKey(cx, cz)
	return (cx + 60000) * 200000 + (cz + 60000)
end

local function AddToGrid(g, i)
	local x, z = g.pts[i * 3 - 2], g.pts[i * 3]
	local key = CellKey(floor(x / g.cell), floor(z / g.cell))
	local cell = g.grid[key]
	if not cell then
		cell = {}
		g.grid[key] = cell
	end
	cell[#cell + 1] = i
end

local function Connect(i, j)
	local a, b = links[i], links[j]
	if not a then
		a = {}
		links[i] = a
	end
	if not b then
		b = {}
		links[j] = b
	end
	a[#a + 1] = j
	b[#b + 1] = i
end

local function Count()
	return pts and floor(#pts / 3) or 0
end
Roads.Count = Count

function Roads.Load(zoneId)
	if zone_id == zoneId and grid then return false end
	zone_id = zoneId
	last_index = nil
	grid = {}
	local all = SS.saved.guide_roads
	entry = all and all[zoneId] or nil
	if entry and not entry.x then entry = nil end
	pts, links = {}, {}
	learned = { pts = pts, links = links, grid = grid, cell = CELL_M }
	if entry then
		local xs, ys, zs = entry.x, entry.y, entry.z
		for i = 1, #xs do
			local k = i * 3
			pts[k - 2], pts[k - 1], pts[k] = xs[i] / 100, ys[i] / 100, zs[i] / 100
			AddToGrid(learned, i)
		end
		local e = entry.e
		for k = 1, #e - 1, 2 do Connect(e[k], e[k + 1]) end
	end
	return true
end

function Roads.Forget()
	SS.saved.guide_roads = {}
	zone_id, entry, pts, links, grid, learned = nil, nil, nil, nil, nil, nil
	last_index = nil
end

local function NearestIn(g, x, z, range, y, dy, need_y)
	local gp, gg, size = g.pts, g.grid, g.cell
	local best, best_d2 = nil, range * range
	local reach = ceil(range / size)
	local cx, cz = floor(x / size), floor(z / size)
	for gx = cx - reach, cx + reach do
		for gz = cz - reach, cz + reach do
			local cell = gg[CellKey(gx, gz)]
			if cell then
				for k = 1, #cell do
					local i = cell[k]
					local ix, iz = gp[i * 3 - 2], gp[i * 3]
					local iy = g.ys and g.ys[i]
					if not g.flat then iy = gp[i * 3 - 1] end
					if (iy or not need_y) and (not iy or not y or abs(iy - y) <= dy) then
						local ddx, ddz = ix - x, iz - z
						local d2 = ddx * ddx + ddz * ddz
						if d2 <= best_d2 then best, best_d2 = i, d2 end
					end
				end
			end
		end
	end
	return best, best and sqrt(best_d2) or nil
end

local function Nearest(x, z, range, y, dy)
	return NearestIn(learned, x, z, range, y, dy)
end
Roads.Nearest = Nearest

local function EnsureEntry()
	if entry then return end
	entry = { x = {}, y = {}, z = {}, e = {} }
	SS.saved.guide_roads[zone_id] = entry
end

local function AddPoint(x, y, z)
	if Count() >= MAX_POINTS then return nil end
	EnsureEntry()
	local i = #entry.x + 1
	local ix, iy, iz = floor(x * 100 + 0.5), floor(y * 100 + 0.5), floor(z * 100 + 0.5)
	entry.x[i], entry.y[i], entry.z[i] = ix, iy, iz
	pts[i * 3 - 2], pts[i * 3 - 1], pts[i * 3] = ix / 100, iy / 100, iz / 100
	AddToGrid(learned, i)
	return i
end

local function Linked(list, j)
	if not list then return false end
	for k = 1, #list do
		if list[k] == j then return true end
	end
	return false
end

local function Link(i, j)
	if i == j or Linked(links[i], j) then return false end
	local xi, yi, zi = pts[i * 3 - 2], pts[i * 3 - 1], pts[i * 3]
	local xj, yj, zj = pts[j * 3 - 2], pts[j * 3 - 1], pts[j * 3]
	local run = sqrt((xi - xj) ^ 2 + (zi - zj) ^ 2)
	if run > LINK_MAX_M then return false end
	if abs(yi - yj) > run * MAX_RISE + 1 then return false end
	Connect(i, j)
	local e = entry.e
	e[#e + 1] = i
	e[#e + 1] = j
	return true
end

function Roads.Record(zoneId, x, y, z)
	if not zoneId or zoneId == 0 then return false end
	if zoneId ~= zone_id or not grid then Roads.Load(zoneId) end
	if last_x then
		local moved = sqrt((x - last_x) ^ 2 + (z - last_z) ^ 2)
		if moved > LINK_MAX_M then
			last_index = nil
		elseif moved < STEP_M and abs(y - last_y) < LEVEL_M * 0.66 then
			return false
		end
	end
	local index = Nearest(x, z, SNAP_M, y, LEVEL_M)
	if not index then index = AddPoint(x, y, z) end
	if not index then return false end
	if last_index and last_index ~= index then Link(last_index, index) end
	last_index, last_x, last_y, last_z = index, x, y, z
	return true
end

local function Push(heap, f, i)
	local n = #heap + 1
	heap[n] = { f, i }
	while n > 1 do
		local parent = floor(n / 2)
		if heap[parent][1] <= heap[n][1] then break end
		heap[parent], heap[n] = heap[n], heap[parent]
		n = parent
	end
end

local function Pop(heap)
	local top = heap[1]
	local n = #heap
	heap[1] = heap[n]
	heap[n] = nil
	n = n - 1
	local i = 1
	while true do
		local l, r, smallest = i * 2, i * 2 + 1, i
		if l <= n and heap[l][1] < heap[smallest][1] then smallest = l end
		if r <= n and heap[r][1] < heap[smallest][1] then smallest = r end
		if smallest == i then break end
		heap[i], heap[smallest] = heap[smallest], heap[i]
		i = smallest
	end
	return top
end

local function RouteOn(g, px, py, pz, tx, tz, start_m, end_m, ty)
	local gp, gl = g.pts, g.links
	local start = NearestIn(g, px, pz, start_m, py, LEVEL_M * 2)
	local goal = ty and NearestIn(g, tx, tz, end_m, ty, LEVEL_M * 2) or NearestIn(g, tx, tz, end_m)
	if not start or not goal or start == goal then return nil end

	local gx, gz = gp[goal * 3 - 2], gp[goal * 3]
	local cost_to, came, closed, heap = { [start] = 0 }, {}, {}, {}
	Push(heap, 0, start)
	local expanded = 0
	while #heap > 0 do
		local current = Pop(heap)[2]
		if current == goal then break end
		if not closed[current] then
			closed[current] = true
			expanded = expanded + 1
			if expanded > MAX_EXPAND then return nil end
			local list = gl[current]
			if list then
				local cx, cz = gp[current * 3 - 2], gp[current * 3]
				for k = 1, #list do
					local nb = list[k]
					if not closed[nb] then
						local nx, nz = gp[nb * 3 - 2], gp[nb * 3]
						local cost = cost_to[current] + sqrt((nx - cx) ^ 2 + (nz - cz) ^ 2)
						if not cost_to[nb] or cost < cost_to[nb] then
							cost_to[nb] = cost
							came[nb] = current
							local hx, hz = nx - gx, nz - gz
							Push(heap, cost + sqrt(hx * hx + hz * hz), nb)
						end
					end
				end
			end
		end
	end
	if not cost_to[goal] then return nil end

	local chain = {}
	local node = goal
	while node do
		chain[#chain + 1] = node
		node = came[node]
	end
	local straight = sqrt((tx - px) ^ 2 + (tz - pz) ^ 2) * OFFROAD
	local ends = sqrt((gp[start * 3 - 2] - px) ^ 2 + (gp[start * 3] - pz) ^ 2)
		+ sqrt((gx - tx) ^ 2 + (gz - tz) ^ 2)
	if cost_to[goal] + ends * OFFROAD >= straight then return nil end

	local route = { { px, py, pz } }
	for k = #chain, 1, -1 do
		local i = chain[k]
		local guessed = g.flat and g.ys[i] == nil
		local y = g.flat and (g.ys[i] or py) or gp[i * 3 - 1]
		route[#route + 1] = { gp[i * 3 - 2], y, gp[i * 3], guessed or nil }
	end
	route[#route + 1] = { tx, ty or route[#route][2], tz, not ty or nil }
	return route, expanded
end

local shipped, shipped_key
local decode

local function Decoder()
	if decode then return decode end
	decode = {}
	local v = 0
	for c = 35, 126 do
		if c ~= 92 and v < 91 then
			decode[c] = v
			v = v + 1
		end
	end
	return decode
end

local REC_LINK_M = 8

local function NewGraph()
	return { pts = {}, links = {}, grid = {}, cell = SHIPPED_CELL_M, flat = true, ys = {}, chain = {} }
end

local function AddNode(g, x, z, y, chain)
	local gp = g.pts
	local n = #gp
	gp[n + 1] = x
	gp[n + 2] = 0
	gp[n + 3] = z
	local i = (n + 3) / 3
	if y then g.ys[i] = y end
	if chain then g.chain[i] = chain end
	AddToGrid(g, i)
	return i
end

local function Join(g, i, j)
	local gl = g.links
	if not i or not j or i == j or Linked(gl[i], j) then return end
	gl[i] = gl[i] or {}
	gl[j] = gl[j] or {}
	gl[i][#gl[i] + 1] = j
	gl[j][#gl[j] + 1] = i
end
function Roads.MapKey(mapId)
	if not mapId or mapId == 0 then return nil end
	local tile = GetMapTileTextureForMapId(mapId, 1)
	if not tile or tile == "" then return nil end
	local key = string.lower(tile):gsub("^/", ""):gsub("^art/maps/", ""):gsub("_%d+%.dds$", "")
	return key
end

function Roads.MapData()
	return SS.MapData or APHSearchMapData
end

local map_count, counted_data

function Roads.MapDataStatus()
	local data = Roads.MapData()
	if data then
		if counted_data ~= data then
			map_count, counted_data = 0, data
			for _ in pairs(data) do map_count = map_count + 1 end
		end
		return SS.L("GUIDE_MAP_DATA_STATUS", string.format(SS.L("GUIDE_MAP_DATA_LOADED"), map_count)), true
	end
	local ver, enabled = LibAPH.CheckLibraryVersion("APH-Search-MapData")
	if ver <= 0 then return SS.L("GUIDE_MAP_DATA_STATUS", SS.L("GUIDE_MAP_DATA_MISSING")), false end
	if not enabled then return SS.L("GUIDE_MAP_DATA_STATUS", SS.L("GUIDE_MAP_DATA_OFF")), false end
	return SS.L("GUIDE_MAP_DATA_STATUS", SS.L("GUIDE_MAP_DATA_RELOAD")), false
end

local function MapEntry(mapId)
	local data = Roads.MapData()
	local key = data and Roads.MapKey(mapId)
	return key and data[key] or nil, key
end

local function AddMap(g, zoneId, mapId)
	local map = MapEntry(mapId)
	if not map then return true end
	local cal = SS.Guide.FrameFor(mapId)
	if not cal or cal.zoneId ~= zoneId then return false end
	local text = map[1]
	local byte, dec = string.byte, Decoder()
	local ids = {}
	local function Node(px, py)
		local id = px * (MAP_SCALE + 1) + py
		local i = ids[id]
		if i then return i end
		local nx, ny = px / MAP_SCALE, py / MAP_SCALE
		i = AddNode(g, (cal.wx + (nx - cal.x0) / cal.ax * cal.cm) / 100, (cal.wz + (ny - cal.y0) / cal.az * cal.cm) / 100)
		ids[id] = i
		return i
	end
	local prev
	local k, n = 1, #text
	while k <= n do
		if byte(text, k) == 32 then
			prev = nil
			k = k + 1
		else
			local a, b, c, d = byte(text, k, k + 3)
			local i = Node(dec[a] * 91 + dec[b], dec[c] * 91 + dec[d])
			Join(g, prev, i)
			prev = i
			k = k + 4
		end
	end
	return true
end

local block_key, block_cells

local function BlockCells(mapId)
	local map, key = MapEntry(mapId)
	if not map then return nil end
	if block_key == key then return block_cells end
	local cells, dec, byte = {}, Decoder(), string.byte
	local text, open, n = map[2], true, 0
	for k = 1, #text do
		local run = dec[byte(text, k)]
		for _ = 1, run do
			n = n + 1
			cells[n] = not open
		end
		open = not open
	end
	block_key, block_cells = key, cells
	return cells
end

function Roads.Blocked(mapId, nx, ny)
	local cells = BlockCells(mapId)
	if not cells then return nil end
	if nx < 0 or nx >= 1 or ny < 0 or ny >= 1 then return true end
	return cells[floor(ny * BLOCK_GRID) * BLOCK_GRID + floor(nx * BLOCK_GRID) + 1] == true
end

function Roads.NearestOpen(mapId, nx, ny)
	local cells = BlockCells(mapId)
	if not cells then return nil end
	local cx = math.max(0, math.min(BLOCK_GRID - 1, floor(nx * BLOCK_GRID)))
	local cy = math.max(0, math.min(BLOCK_GRID - 1, floor(ny * BLOCK_GRID)))
	for r = 0, BLOCK_GRID do
		local best, best_d2
		for gy = cy - r, cy + r do
			for gx = cx - r, cx + r do
				if (abs(gx - cx) == r or abs(gy - cy) == r) and gx >= 0 and gy >= 0 and gx < BLOCK_GRID and gy < BLOCK_GRID
					and not cells[gy * BLOCK_GRID + gx + 1] then
					local d2 = (gx - cx) ^ 2 + (gy - cy) ^ 2
					if not best_d2 or d2 < best_d2 then best, best_d2 = gy * BLOCK_GRID + gx, d2 end
				end
			end
		end
		if best then
			return ((best % BLOCK_GRID) + 0.5) / BLOCK_GRID, (floor(best / BLOCK_GRID) + 0.5) / BLOCK_GRID
		end
	end
	return nil
end

local next_chain = 0

local function AddChain(g, xs, ys, zs, first, last)
	next_chain = next_chain + 1
	local prev
	for k = first or 1, last or #xs do
		local i = AddNode(g, xs[k] / 100, zs[k] / 100, ys[k] / 100, next_chain)
		Join(g, prev, i)
		prev = i
	end
end

local function LinkRecorded(g)
	local gp, chain, gg, size = g.pts, g.chain, g.grid, g.cell
	local reach = ceil(REC_LINK_M / size)
	for i, own in pairs(chain) do
		local x, z = gp[i * 3 - 2], gp[i * 3]
		local best, best_d2 = nil, REC_LINK_M * REC_LINK_M
		local cx, cz = floor(x / size), floor(z / size)
		for gx = cx - reach, cx + reach do
			for gz = cz - reach, cz + reach do
				local cell = gg[CellKey(gx, gz)]
				if cell then
					for k = 1, #cell do
						local j = cell[k]
						if chain[j] ~= own then
							local d2 = (gp[j * 3 - 2] - x) ^ 2 + (gp[j * 3] - z) ^ 2
							if d2 <= best_d2 then best, best_d2 = j, d2 end
						end
					end
				end
			end
		end
		if best then Join(g, i, best) end
	end
end

local function ZoneGraph(zoneId)
	local data = SS.RoadData
	local mapId = SS.Guide.PlayerMap() or GetCurrentMapId() or 0
	local want_art = SS.saved.guide_map_roads and Roads.MapData() ~= nil
	local record = SS.GuideRecord
	local key = table.concat({ zoneId, mapId, record and record.Version() or 0, tostring(want_art) }, ":")
	if shipped_key == key then return shipped end
	local g = NewGraph()
	local art_ok = true
	if want_art then
		if mapId ~= 0 then art_ok = AddMap(g, zoneId, mapId) else art_ok = false end
	end
	local zone = data and data.recorded and data.recorded[zoneId]
	if zone then
		local starts, xs = zone.start, zone.x
		for r = 1, #starts do AddChain(g, xs, zone.y, zone.z, starts[r], (starts[r + 1] or #xs + 1) - 1) end
	end
	if record then
		local list = record.Recordings(zoneId)
		for r = 1, #list do
			local recording = list[r]
			AddChain(g, recording.x, recording.y, recording.z)
		end
	end
	LinkRecorded(g)
	if art_ok then shipped, shipped_key = g, key end
	return g
end
Roads.ShippedGraph = ZoneGraph

function Roads.Invalidate()
	shipped, shipped_key = nil, nil
end

function Roads.ShippedCount()
	return shipped and floor(#shipped.pts / 3) or 0
end

function Roads.Route(zoneId, px, py, pz, tx, tz, ty)
	if zoneId ~= zone_id or not grid then Roads.Load(zoneId) end
	if Count() >= 2 then
		local route, expanded = RouteOn(learned, px, py, pz, tx, tz, START_M, END_M, ty)
		if route then return route, expanded end
	end
	local g = ZoneGraph(zoneId)
	if not g or #g.pts < 6 then return nil end
	return RouteOn(g, px, py, pz, tx, tz, SHIPPED_START_M, SHIPPED_END_M, ty)
end

local function SettleOn(target, x, y, z, how)
	target.x, target.z = x * 100, z * 100
	if y then target.groundY, target.level, target.level_locked = y * 100, nil, nil end
	target.settled = how
	return how
end

function Roads.Settle(target, zoneId, mapId, mx, my)
	if not target or target.settled or target.member or target.hop then return nil end
	target.settled = "kept"
	if zoneId ~= zone_id or not grid then Roads.Load(zoneId) end
	local tx, tz = target.x / 100, target.z / 100
	local i = Count() > 0 and Nearest(tx, tz, SETTLE_M) or nil
	if i then return SettleOn(target, pts[i * 3 - 2], pts[i * 3 - 1], pts[i * 3], "walked") end
	local g = ZoneGraph(zoneId)
	i = g and NearestIn(g, tx, tz, SETTLE_M, nil, nil, true)
	if i then return SettleOn(target, g.pts[i * 3 - 2], g.ys[i], g.pts[i * 3], "walked") end
	if not mx or not Roads.Blocked(mapId, mx, my) then return nil end
	i = g and NearestIn(g, tx, tz, SETTLE_FAR_M)
	if i then return SettleOn(target, g.pts[i * 3 - 2], nil, g.pts[i * 3], "road") end
	local ox, oy = Roads.NearestOpen(mapId, mx, my)
	if not ox then return nil end
	local zone, wx, wz = SS.Guide.MapToWorld(ox, oy)
	if zone ~= zoneId or not wx then return nil end
	return SettleOn(target, wx / 100, nil, wz / 100, "ground")
end
