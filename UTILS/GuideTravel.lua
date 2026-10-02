--[[
    Copyright © 2026 @APHONlC. All rights reserved.

    No copying, modification, distribution, or sale without prior written permission.
    AI/ML ingestion and training are strictly prohibited (TDM opt-out).

    See LICENSE.md for full terms and maintenance exceptions.
]]

local SS = APHSearchCore
local T = {}
SS.GuideTravel = T

local function Parent(zoneId)
	return GetParentZoneId and GetParentZoneId(zoneId) or zoneId
end

local function LeadsTo(spotZone, destZone)
	if not spotZone or spotZone == 0 or not destZone or destZone == 0 then return false end
	if spotZone == destZone then return true end
	if Parent(spotZone) == destZone or Parent(destZone) == spotZone then return true end
	return SS.Guide.Contains(destZone, spotZone) or SS.Guide.Contains(spotZone, destZone)
end
T.LeadsTo = LeadsTo

function T.NodeZone(node)
	local zoneIndex = GetFastTravelNodePOIIndicies(node)
	return zoneIndex and GetZoneId(zoneIndex) or nil
end

function T.DestinationNode(destZone)
	for node = 1, GetNumFastTravelNodes() do
		local known, _, _, _, _, _, poiType = GetFastTravelNodeInfo(node)
		if known and poiType == POI_TYPE_WAYSHRINE and LeadsTo(T.NodeZone(node) or 0, destZone) then return node end
	end
	return nil
end

function T.NearestWayshrine(zoneId, px, pz)
	local best, best_d, best_x, best_z
	for node = 1, GetNumFastTravelNodes() do
		local known, _, nx, ny, _, _, poiType, shown = GetFastTravelNodeInfo(node)
		if known and shown and poiType == POI_TYPE_WAYSHRINE and LeadsTo(T.NodeZone(node) or zoneId, zoneId) then
			local mapZone, wx, wz = SS.Guide.MapToWorld(nx, ny)
			if mapZone then
				local d = (wx - px) ^ 2 + (wz - pz) ^ 2
				if not best_d or d < best_d then best, best_d, best_x, best_z = node, d, wx, wz end
			end
		end
	end
	return best, best_x, best_z
end

local function Usable(node)
	local known, _, _, _, _, _, _, _, locked = GetFastTravelNodeInfo(node)
	return known and not locked and not GetFastTravelNodeOutboundOnlyInfo(node)
end

local function HouseOwned(houseId)
	local collectible = GetCollectibleIdForHouse(houseId)
	return collectible ~= nil and collectible ~= 0 and IsCollectibleUnlocked(collectible)
end

local function NodeChoices(destZone, x, z)
	local best = {}
	for node = 1, GetNumFastTravelNodes() do
		if Usable(node) and LeadsTo(T.NodeZone(node), destZone) then
			local _, _, nx, nz, _, _, poiType, shown = GetFastTravelNodeInfo(node)
			local houseId = GetFastTravelNodeHouseId(node)
			local kind, outside
			if houseId ~= 0 then
				kind = "house"
				outside = not HouseOwned(houseId)
				if outside and not HasCompletedFastTravelNodePOI(node) then kind = nil end
			elseif poiType == POI_TYPE_WAYSHRINE then
				kind = "wayshrine"
			else
				kind = "instance"
			end
			if kind then
				local d = (x and shown) and ((nx - x) ^ 2 + (nz - z) ^ 2) or math.huge
				local held = best[kind]
				if not held or d < held.d or (kind == "house" and held.outside and not outside) then
					best[kind] = { kind = kind, node = node, outside = outside, d = d }
				end
			end
		end
	end
	return best
end

local function Online(status)
	return status ~= nil and status ~= PLAYER_STATUS_OFFLINE
end

local function FriendIn(destZone)
	for i = 1, GetNumFriends() do
		local name, _, status = GetFriendInfo(i)
		local hasCharacter, _, _, _, _, _, _, zoneId = GetFriendCharacterInfo(i)
		if Online(status) and hasCharacter and LeadsTo(zoneId, destZone) then
			return { kind = "player", who = "friend", name = name }
		end
	end
	return nil
end

local function GroupMemberIn(destZone)
	for i = 1, GetGroupSize() do
		local tag = GetGroupUnitTagByIndex(i)
		if tag and not AreUnitsEqual(tag, "player") and IsUnitOnline(tag) then
			local zoneIndex = GetUnitZoneIndex(tag)
			if zoneIndex and LeadsTo(GetZoneId(zoneIndex), destZone) and CanJumpToGroupMember(tag) then
				return { kind = "player", who = "group", name = GetUnitDisplayName(tag) }
			end
		end
	end
	return nil
end

local function GuildMemberIn(destZone)
	local guilds = GetNumGuilds()
	if guilds == 0 then return nil end
	local me = GetDisplayName()
	for g = 1, guilds do
		local guildId = GetGuildId(g)
		for i = 1, GetNumGuildMembers(guildId) do
			local name, _, _, status = GetGuildMemberInfo(guildId, i)
			if name ~= me and Online(status) then
				local hasCharacter, _, _, _, _, _, _, zoneId = GetGuildMemberCharacterInfo(guildId, i)
				if hasCharacter and LeadsTo(zoneId, destZone) then
					return { kind = "player", who = "guild", name = name, guild = GetGuildName(guildId) }
				end
			end
		end
	end
	return nil
end

function T.WayInto(destZone, x, z)
	if not destZone or destZone == 0 then return nil end
	local nodes = NodeChoices(destZone, x, z)
	return nodes.wayshrine or FriendIn(destZone) or GroupMemberIn(destZone) or GuildMemberIn(destZone)
		or nodes.house or nodes.instance
end
