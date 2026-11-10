-- MobSpot: finding listed mobs
-- Two ways, each run once a second and on the game's own updates:
--   nameplates    every mob with a nameplate (and your target, mouseover and focus); the scan
--                 radius is the game's nameplate distance. Listed mobs get a skull (Marker.lua).
--   map markers   mobs the game marks on the map and minimap, with their real distance
-- Forever's game refuses TargetUnit from addons before it looks for the unit, so the old
-- "refused means it's near" trick can't tell anything there (tested 2026-11-10).

local _, ns = ...

local TICK = 1           -- seconds between scans
ns.ALERT_AGAIN_MIN, ns.ALERT_AGAIN_MAX = 5, 300 -- the setting's range, in seconds
local MAX_PLATES = 40    -- nameplate1 .. nameplate40

local byName, byNpc = {}, {} -- lookups built from the list: [lowercase name] / [npcID] = key
local seen = {}              -- [key] = when it was last found

local function rebuild()
	wipe(byName)
	wipe(byNpc)
	for key, mob in pairs(ns.db.mobs) do
		if mob.on then
			byName[key] = key
			if mob.npcID then byNpc[mob.npcID] = key end
		end
	end
	for key in pairs(seen) do
		if not byName[key] then seen[key] = nil end
	end
end

-- The list key for a creature, by its NPC ID when there is one, else by its name.
local function match(guid, name)
	local npcID = ns.NpcID(guid)
	if npcID and byNpc[npcID] then
		local key = byNpc[npcID]
		if ns.db.mobs[key].unnamed then key = ns.NameMob(key, name) end -- added by ID: now named
		return key
	end
	name = ns.Plain(name)
	if type(name) ~= "string" then return end
	local key = byName[name:lower()]
	if key and npcID and not ns.db.mobs[key].npcID then
		ns.db.mobs[key].npcID = npcID -- learned now, so a renamed or translated mob still matches
		byNpc[npcID] = key
	end
	return key
end

-- A listed mob was found. `how` is "near" (a nameplate, target, mouseover or focus) or "map"
-- (with `yards`, nil when the map can't tell).
local function found(key, how, yards)
	local now = GetTime()
	local last = seen[key]
	seen[key] = now
	if not (last and now - last < ns.db.alertAgain) then ns.Alert(ns.db.mobs[key], how, yards) end
end

---------------------------------------------------------------------------
-- Scan radius: the game's nameplate distance
---------------------------------------------------------------------------

ns.RADIUS_MIN, ns.RADIUS_MAX = 10, 100
local APPLY_DELAY = 1 -- seconds after entering the world or leaving combat before putting them back

-- The radius and "nameplates on" are the game's own settings, which other addons may set on
-- every login. So MobSpot keeps what the player picked (ns.db.radius, ns.db.nameplates) and puts
-- it back once the player is in the world, and after combat.

function ns.Radius()
	return tonumber(C_CVar.GetCVar("nameplateMaxDistance")) or 40
end

-- Mobs only get a nameplate when enemy nameplates are on and shown out of combat too.
function ns.NameplatesOn()
	return C_CVar.GetCVarBool("nameplateShowEnemies") and C_CVar.GetCVarBool("nameplateShowAll")
end

-- Puts the picked radius and nameplates back where something else changed them. The game
-- doesn't allow it in combat; it's done again when combat ends.
local function apply()
	if InCombatLockdown() then return end
	local changed = false
	local radius = ns.db.radius
	if radius and math.floor(ns.Radius() + 0.5) ~= radius then
		C_CVar.SetCVar("nameplateMaxDistance", tostring(radius))
		changed = true
	end
	if ns.db.nameplates and not ns.NameplatesOn() then
		C_CVar.SetCVar("nameplateShowEnemies", "1")
		C_CVar.SetCVar("nameplateShowAll", "1")
		changed = true
	end
	if changed then ns.Fire("SettingChanged", "nameplates") end
end

-- Sets the nameplate distance. The game keeps it within its own limit, which ns.Radius() shows
-- afterwards. During combat it waits for combat to end; returns false then.
function ns.SetRadius(yards)
	ns.db.radius = math.floor(yards + 0.5)
	if InCombatLockdown() then return false end
	apply()
	ns.Fire("SettingChanged", "radius")
	return true
end

function ns.TurnOnNameplates()
	if InCombatLockdown() then
		ns.Print("leave combat first, then try again.")
		return
	end
	ns.db.nameplates = true
	apply()
end

local function applySoon()
	C_Timer.After(APPLY_DELAY, apply)
end
ns.On("PLAYER_ENTERING_WORLD", applySoon)
ns.On("PLAYER_REGEN_ENABLED", applySoon)

---------------------------------------------------------------------------
-- Nameplates, target, mouseover, focus
---------------------------------------------------------------------------

-- The list key of a living listed mob on `unit`, after alerting for it; nil for anything else.
local function checkUnit(unit)
	if not UnitExists(unit) then return end
	local player, dead = ns.Plain(UnitIsPlayer(unit)), ns.Plain(UnitIsDead(unit))
	if player ~= false or dead ~= false then return end
	local key = match(UnitGUID(unit), UnitName(unit))
	if key then found(key, "near") end
	return key
end

local function checkPlate(unit)
	ns.Mark(unit, checkUnit(unit) ~= nil)
end

local function scanUnits()
	for i = 1, MAX_PLATES do checkPlate("nameplate" .. i) end
	checkUnit("target")
	checkUnit("mouseover")
	checkUnit("focus")
end

---------------------------------------------------------------------------
-- Map markers
---------------------------------------------------------------------------

-- Yards from the player to a map marker, or nil when the map can't tell (indoors, instances).
local function markerYards(guid)
	local mapID = C_Map.GetBestMapForUnit("player")
	if not mapID then return end
	local spot = C_VignetteInfo.GetVignettePosition(guid, mapID)
	local me = C_Map.GetPlayerMapPosition(mapID, "player")
	if not (spot and me) then return end
	local _, a = C_Map.GetWorldPosFromMapPos(mapID, spot)
	local _, b = C_Map.GetWorldPosFromMapPos(mapID, me)
	if not (a and b) then return end
	local dx, dy = a.x - b.x, a.y - b.y
	return math.sqrt(dx * dx + dy * dy)
end

local function scanMarkers()
	if not (ns.db.mapMarkers and C_VignetteInfo) then return end
	local radius = ns.Radius()
	for _, guid in ipairs(C_VignetteInfo.GetVignettes() or {}) do
		local info = C_VignetteInfo.GetVignetteInfo(guid)
		if info and not info.isDead then
			local key = match(info.objectGUID, info.name)
			if key then
				local yards = markerYards(guid)
				if not yards or yards <= radius then found(key, "map", yards) end
			end
		end
	end
end

---------------------------------------------------------------------------
-- Running the scans
---------------------------------------------------------------------------

local function tick()
	if not ns.db.enabled or not next(byName) then
		ns.ClearMarks()
		return
	end
	scanUnits()
	scanMarkers()
end

ns.Listen("Loaded", rebuild)
ns.Listen("MobsChanged", rebuild)

ns.On("PLAYER_LOGIN", function()
	C_Timer.NewTicker(TICK, tick)
end)

local function onUnit(unit)
	if ns.db.enabled then checkUnit(unit) end
end
ns.On("NAME_PLATE_UNIT_ADDED", function(unit)
	if ns.db.enabled then checkPlate(unit) end
end)
ns.On("PLAYER_TARGET_CHANGED", function() onUnit("target") end)
ns.On("UPDATE_MOUSEOVER_UNIT", function() onUnit("mouseover") end)

ns.On("VIGNETTE_MINIMAP_UPDATED", function()
	if ns.db.enabled then scanMarkers() end
end)
