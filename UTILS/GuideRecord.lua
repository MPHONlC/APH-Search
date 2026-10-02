--[[
    Copyright © 2026 @APHONlC. All rights reserved.

    No copying, modification, distribution, or sale without prior written permission.
    AI/ML ingestion and training are strictly prohibited (TDM opt-out).

    See LICENSE.md for full terms and maintenance exceptions.
]]

local SS = APHSearchCore
local Rec = {}
SS.GuideRecord = Rec

local sqrt, abs, floor = math.sqrt, math.abs, math.floor

local NS = SS.name .. "GuideRecord"
local SAMPLE_MS = 250
local STEP_M = 4
local RISE_M = 1.5
local JUMP_M = 60
local MIN_LENGTH_M = 10
local MAX_POINTS = 3000
local MAX_RECORDINGS = 300

Rec.STEP_M, Rec.JUMP_M, Rec.MIN_LENGTH_M, Rec.MAX_POINTS = STEP_M, JUMP_M, MIN_LENGTH_M, MAX_POINTS

local active
local last_x, last_y, last_z
local version = 0

local function Store()
	local list = SS.saved.guide_recordings
	if not list then
		list = {}
		SS.saved.guide_recordings = list
	end
	return list
end

local function Changed()
	version = version + 1
	if SS.GuideRoads then SS.GuideRoads.Invalidate() end
	if SS.GuideMap then SS.GuideMap.RecordingsChanged() end
end

function Rec.Version() return version end
function Rec.IsRecording() return active ~= nil end
function Rec.Active() return active end

function Rec.Recordings(zoneId)
	local out = {}
	local list = Store()
	for i = 1, #list do
		local entry = list[i]
		if entry.zone == zoneId and entry.x and #entry.x >= 2 then out[#out + 1] = entry end
	end
	return out
end

function Rec.Length(entry)
	local xs, zs, total = entry.x, entry.z, 0
	for k = 2, #xs do
		local dx, dz = xs[k] - xs[k - 1], zs[k] - zs[k - 1]
		total = total + sqrt(dx * dx + dz * dz) / 100
	end
	return total
end

function Rec.PlaceName()
	local name = GetPlayerActiveSubzoneName()
	if not name or name == "" then name = GetPlayerLocationName() end
	return zo_strformat("<<1>>", name or "")
end

local function Begin(zoneId)
	local list = Store()
	while #list >= MAX_RECORDINGS do table.remove(list, 1) end
	local map, inside = SS.Guide.PlayerMap()
	active = { zone = zoneId, map = map, inside = inside or nil, place = Rec.PlaceName(), when = GetTimeStamp(), x = {}, y = {}, z = {} }
	list[#list + 1] = active
	last_x, last_y, last_z = nil, nil, nil
end

local function Close()
	local entry = active
	active = nil
	last_x = nil
	if not entry then return nil, 0 end
	local length = Rec.Length(entry)
	if #entry.x < 2 or length < MIN_LENGTH_M then
		local list = Store()
		for i = #list, 1, -1 do
			if list[i] == entry then table.remove(list, i) end
		end
		return nil, length
	end
	return entry, length
end

local function Add(x, y, z)
	local n = #active.x + 1
	active.x[n], active.y[n], active.z[n] = floor(x * 100 + 0.5), floor(y * 100 + 0.5), floor(z * 100 + 0.5)
	last_x, last_y, last_z = x, y, z
end

local function Sample()
	if not active then return false end
	local zoneId, wx, wy, wz = GetUnitRawWorldPosition("player")
	if not zoneId or zoneId == 0 then return false end
	local x, y, z = wx / 100, wy / 100, wz / 100
	SS.Guide.ToPlayerMap()
	SS.Guide.LearnFrame()
	local map, inside = SS.Guide.PlayerMap()
	if zoneId ~= active.zone or ((active.inside or inside) and map ~= active.map) then
		Close()
		Begin(zoneId)
		Add(x, y, z)
		Changed()
		return true
	end
	if last_x then
		local moved = sqrt((x - last_x) ^ 2 + (z - last_z) ^ 2)
		if moved > JUMP_M then
			Close()
			Begin(zoneId)
		elseif moved < STEP_M and abs(y - last_y) < RISE_M then
			return false
		end
	end
	if #active.x >= MAX_POINTS then
		local px, py, pz = last_x, last_y, last_z
		Close()
		Begin(zoneId)
		if px then Add(px, py, pz) end
	end
	Add(x, y, z)
	Changed()
	return true
end
Rec.Sample = Sample

function Rec.Start()
	if active then return false end
	local zoneId, wx, wy, wz = GetUnitRawWorldPosition("player")
	if not zoneId or zoneId == 0 then return false end
	SS.Guide.ToPlayerMap(true)
	Begin(zoneId)
	Add(wx / 100, wy / 100, wz / 100)
	EVENT_MANAGER:RegisterForUpdate(NS, SAMPLE_MS, Sample)
	Changed()
	SS.Print(SS.L("GUIDE_RECORD_STARTED"), true)
	return true
end

function Rec.Stop()
	if not active then return false end
	EVENT_MANAGER:UnregisterForUpdate(NS)
	Sample()
	local zoneId = active.zone
	local kept, length = Close()
	Changed()
	if kept then
		SS.Print(SS.L("GUIDE_RECORD_SAVED", SS.Guide.FormatDistance(length), zo_strformat("<<1>>", GetZoneNameById(zoneId))), true)
	else
		SS.Print(SS.L("GUIDE_RECORD_TOO_SHORT", MIN_LENGTH_M), true)
	end
	return kept ~= nil
end

function Rec.Toggle()
	if active then return Rec.Stop() end
	return Rec.Start()
end

function Rec.SetRecording(on)
	if on and not active then return Rec.Start() end
	if not on and active then return Rec.Stop() end
	return false
end

function Rec.Forget()
	if active then
		EVENT_MANAGER:UnregisterForUpdate(NS)
		active, last_x = nil, nil
	end
	SS.saved.guide_recordings = {}
	Changed()
end

function Rec.Count()
	return #Store()
end
