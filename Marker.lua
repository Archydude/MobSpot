-- MobSpot: a marker over a listed mob's nameplate
-- Drawn by MobSpot on the nameplate, so only the player sees it. The game's raid markers can't be
-- set by addons on Forever (SetRaidTarget is protected). Nameplates the game keeps from addons
-- (in dungeons and raids) get nothing. The player picks the marker, its size and its animation.
--
-- The animation is worked out every frame from the clock, not with the game's animation groups:
-- a looping "bounce" group shows one frame at the wrong spot each time it turns around.

local _, ns = ...

ns.MARKER_SIZE_MIN, ns.MARKER_SIZE_MAX = 16, 96

local BOB = 0.2           -- how far a bobbing marker moves, as a share of its size
local BOB_TIME = 1        -- seconds for one bob, up and back down
local SPIN_TIME = 3       -- seconds per turn
local PULSE_TIME = 1.2    -- seconds for one pulse, out and back in
local PULSE_SCALE = 1.25  -- how much a pulsing marker grows
local PULSE_FADE = 0.3    -- how much it fades at its biggest
local TAU = 2 * math.pi

local function raid(n) return "Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. n end

-- flip turns the picture upside down (an up arrow made to point at the mob).
local ALL = {
	{ key = "skull", name = "Skull", file = raid(8) },
	{ key = "cross", name = "Red cross", file = raid(7) },
	{ key = "star", name = "Star", file = raid(1) },
	{ key = "diamond", name = "Diamond", file = raid(3) },
	{ key = "moon", name = "Moon", file = raid(5) },
	{ key = "arrow", name = "Green arrow", atlas = "bags-greenarrow", flip = true },
	{ key = "pin", name = "Map pin", atlas = "Waypoint-MapPin-Tracked" },
	{ key = "quest", name = "Quest mark", atlas = "QuestNormal" },
	{ key = "rare", name = "Rare mob", atlas = "VignetteKill" },
	{ key = "treasure", name = "Treasure chest", atlas = "VignetteLoot" },
	{ key = "dungeon", name = "Dungeon skull", atlas = "DungeonSkull" },
	{ key = "spiky", name = "Spiky star", atlas = "ChallengeMode-SpikeyStar" },
	{ key = "orb", name = "Purple orb", atlas = "nameplates-icon-orb-purple" },
	{ key = "ring", name = "Arcane ring", atlas = "Mage-ArcaneCharge-CircleGlow" },
}
ns.DEFAULT_MARKER = "skull"

ns.MOTIONS = {
	{ key = "bob", name = "Bob up and down" },
	{ key = "pulse", name = "Pulse" },
	{ key = "spin", name = "Spin" },
	{ key = "none", name = "Stay still" },
}
ns.DEFAULT_MOTION = "bob"

-- The markers the game has pictures for. An atlas is drawn from its image file and the part of
-- the file it covers, so an atlas the game doesn't know is left out.
ns.MARKERS = {}
for _, m in ipairs(ALL) do
	if m.atlas then
		local info = C_Texture and C_Texture.GetAtlasInfo(m.atlas)
		local file = info and (info.file or info.filename)
		if file then
			m.file = file
			m.coords = { info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord }
			ns.MARKERS[#ns.MARKERS + 1] = m
		end
	else
		m.coords = { 0, 1, 0, 1 }
		ns.MARKERS[#ns.MARKERS + 1] = m
	end
end

function ns.MarkerInfo(key)
	for _, m in ipairs(ns.MARKERS) do
		if m.key == key then return m end
	end
	return ns.MARKERS[1]
end

-- "|A...|a" or "|T...|t" text that shows the marker's picture in a menu line.
function ns.MarkerIcon(m, size)
	if m.atlas then return ("|A:%s:%d:%d|a"):format(m.atlas, size, size) end
	return ("|T%s:%d:%d|t"):format(m.file, size, size)
end

---------------------------------------------------------------------------
-- Marker frames
---------------------------------------------------------------------------

local frames = {} -- every marker frame made, so a new pick or size reaches them all
local moving = {} -- [marker frame] = true while it's shown
local driver = CreateFrame("Frame")

-- 0 at the start of a cycle, 1 halfway, back to 0 at the end, easing in and out.
local function wave(now, period)
	return 0.5 - 0.5 * math.cos(now / period * TAU)
end

local function animate(marker, now)
	local size, icon = marker.size, marker.icon
	if marker.motion == "bob" then
		icon:SetPoint("CENTER", marker, "CENTER", 0, size * BOB * wave(now, BOB_TIME))
	elseif marker.motion == "pulse" then
		local w = wave(now, PULSE_TIME)
		local s = size * (1 + (PULSE_SCALE - 1) * w)
		icon:SetSize(s, s)
		icon:SetAlpha(1 - PULSE_FADE * w)
	elseif marker.motion == "spin" then
		icon:SetRotation(-(now % SPIN_TIME) / SPIN_TIME * TAU)
	end
end

local function onUpdate()
	local now = GetTime()
	for marker in pairs(moving) do animate(marker, now) end
end

local function track(marker, on)
	moving[marker] = on or nil
	driver:SetScript("OnUpdate", next(moving) and onUpdate or nil)
end

-- The game snaps textures to whole pixels, which makes slow motion move in visible steps.
-- Setting a new picture can turn it back on, so this runs after each one.
local function unsnap(icon)
	if icon.SetSnapToPixelGrid then
		icon:SetSnapToPixelGrid(false)
		icon:SetTexelSnappingBias(0)
	end
end

local function style(marker)
	local m = ns.MarkerInfo(ns.db.markerStyle)
	local size = ns.db.markerSize
	marker:SetSize(size, size)
	marker.size = size
	marker.motion = ns.db.markerMotion
	local icon = marker.icon
	icon:SetTexture(m.file)
	local left, right, top, bottom = unpack(m.coords)
	if m.flip then top, bottom = bottom, top end
	icon:SetTexCoord(left, right, top, bottom)
	unsnap(icon)
	-- back to rest, then the animation takes it from there
	icon:ClearAllPoints()
	icon:SetPoint("CENTER")
	icon:SetSize(size, size)
	icon:SetAlpha(1)
	icon:SetRotation(0)
	if marker:IsVisible() then animate(marker, GetTime()) end
end

-- A marker frame on `parent`: on a nameplate, or the preview on the options page.
function ns.NewMarker(parent)
	local marker = CreateFrame("Frame", nil, parent)
	marker:EnableMouse(false)
	marker.icon = marker:CreateTexture(nil, "OVERLAY")
	marker:SetScript("OnShow", function(self) track(self, true) end)
	marker:SetScript("OnHide", function(self) track(self, false) end)
	frames[#frames + 1] = marker
	style(marker)
	if marker:IsVisible() then track(marker, true) end
	return marker
end

---------------------------------------------------------------------------
-- On nameplates
---------------------------------------------------------------------------

local shown = {} -- [nameplate unit] = the marker frame on it

local function markerFor(plate)
	local marker = plate.MobSpotMarker
	if marker then return marker end
	marker = ns.NewMarker(plate)
	marker:SetPoint("BOTTOM", plate, "TOP", 0, 4)
	marker:SetFrameLevel(plate:GetFrameLevel() + 20)
	marker:Hide()
	plate.MobSpotMarker = marker
	return marker
end

local function hide(unit)
	local marker = shown[unit]
	if not marker then return end
	shown[unit] = nil
	marker:Hide()
end

-- Shows the marker over `unit`'s nameplate when `listed` is true, else takes it off.
function ns.Mark(unit, listed)
	if not (listed and ns.db.marker) then
		hide(unit)
		return
	end
	if shown[unit] then return end
	local plate = C_NamePlate.GetNamePlateForUnit(unit)
	if not plate or plate:IsForbidden() then return end
	local marker = markerFor(plate)
	shown[unit] = marker
	marker:Show()
end

function ns.ClearMarks()
	for unit in pairs(shown) do hide(unit) end
end

ns.On("NAME_PLATE_UNIT_REMOVED", hide)

ns.Listen("SettingChanged", function(name)
	if (name == "marker" and not ns.db.marker) or (name == "enabled" and not ns.db.enabled) then
		ns.ClearMarks()
	elseif name == "markerStyle" or name == "markerSize" or name == "markerMotion" then
		for _, marker in ipairs(frames) do style(marker) end
	end
end)
