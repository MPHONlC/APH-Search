--[[
    Copyright © 2026 @APHONlC. All rights reserved.

    No copying, modification, distribution, or sale without prior written permission.
    AI/ML ingestion and training are strictly prohibited (TDM opt-out).

    See LICENSE.md for full terms and maintenance exceptions.
]]

local SS = APHSearchCore
local W = {}
SS.GuideWorld = W

local pi = math.pi
local WorldPositionToGuiRender3DPosition = WorldPositionToGuiRender3DPosition

local canvas

local function Canvas()
	if canvas then return canvas end
	canvas = WINDOW_MANAGER:CreateTopLevelWindow("APHSearchGuideWorld")
	canvas:SetDimensions(GuiRoot:GetWidth(), GuiRoot:GetHeight())
	canvas:SetAnchor(CENTER, GuiRoot, CENTER, 0, 0)
	canvas:SetMouseEnabled(false)
	local fragment = ZO_HUDFadeSceneFragment:New(canvas)
	HUD_SCENE:AddFragment(fragment)
	HUD_UI_SCENE:AddFragment(fragment)
	return canvas
end

local Native = {}
Native.__index = Native

function Native:SetTexture(path) self.control:SetTexture(path) return self end
function Native:SetSize(meters) self.control:Set3DLocalDimensions(meters, meters) return self end
function Native:SetColor(r, g, b, a) self.control:SetColor(r, g, b, a) return self end
function Native:SetHidden(hidden) self.control:SetHidden(hidden) return self end
function Native:SetYaw(yaw) self.control:Set3DRenderSpaceOrientation(-pi / 2, yaw, 0) return self end
function Native:SetPosition(x, y, z)
	self.control:Set3DRenderSpaceOrigin(WorldPositionToGuiRender3DPosition(x, y, z))
	return self
end

local native_count = 0

local function NewNative()
	native_count = native_count + 1
	local control = WINDOW_MANAGER:CreateControl("APHSearchGuideWorldFlat" .. native_count, Canvas(), CT_TEXTURE)
	control:Create3DRenderSpace()
	control:Set3DRenderSpaceOrientation(-pi / 2, 0, 0)
	control:SetHidden(true)
	return setmetatable({ control = control }, Native)
end

local Implex = {}
Implex.__index = Implex

function Implex:SetTexture(path) self.obj:SetTexture(path) return self end
function Implex:SetSize(meters) self.obj:SetDimensions(meters, meters) return self end
function Implex:SetColor(r, g, b, a) self.obj:SetColor(r, g, b, a) return self end
function Implex:SetHidden(hidden)
	if self.obj.control then self.obj.control:SetHidden(hidden) end
	return self
end
function Implex:SetYaw(yaw) self.obj:SetOrientation(-pi / 2, yaw, 0) return self end
function Implex:SetPosition(x, y, z) self.obj:SetPosition(x, y, z) return self end

local implex_context

local function NewImplex()
	implex_context = implex_context or LibImplex.Objects("APHSearchGuide")
	return setmetatable({ obj = implex_context._3DStatic() }, Implex)
end

function W.UsesLibImplex()
	return SS.Guide.HasLibImplex()
end

function W.NewFlat(texture, meters)
	local flat = W.UsesLibImplex() and NewImplex() or NewNative()
	flat:SetTexture(texture)
	flat:SetSize(meters)
	flat:SetYaw(0)
	return flat
end

local probe

local function Probe()
	if probe then return probe end
	probe = WINDOW_MANAGER:CreateControl("APHSearchGuideCameraProbe", Canvas(), CT_CONTROL)
	probe:Create3DRenderSpace()
	return probe
end

function W.Project(x, y, z)
	local p = Probe()
	Set3DRenderSpaceToCurrentCamera(p:GetName())
	local cx, cy, cz = GuiRender3DPositionToWorldPosition(p:Get3DRenderSpaceOrigin())
	local fx, fy, fz = p:Get3DRenderSpaceForward()
	local rx, ry, rz = p:Get3DRenderSpaceRight()
	local ux, uy, uz = p:Get3DRenderSpaceUp()
	local dx, dy, dz = x - cx, y - cy, z - cz
	local depth = fx * dx + fy * dy + fz * dz
	if depth <= 1 then return nil end
	local w, h = GetWorldDimensionsOfViewFrustumAtDepth(depth)
	if not w or w == 0 or h == 0 then return nil end
	local sx = (rx * dx + ry * dy + rz * dz) * GuiRoot:GetWidth() / w
	local sy = -(ux * dx + uy * dy + uz * dz) * GuiRoot:GetHeight() / h
	return sx, sy, depth
end
