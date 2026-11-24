-- MobSpot: finding listed mobs
-- Two ways, each run once a second and on the game's own updates:
--   nameplates    every mob with a nameplate (and your target, mouseover and focus); the scan
--                 radius is the game's nameplate distance. Listed mobs get a skull (Marker.lua).
--   map markers   mobs the game marks on the map and minimap, with their real distance
-- With "every rare" on, any rare mob counts too, listed or not (key "rare:<NPC ID or name>").
-- Forever's game refuses TargetUnit from addons before it looks for the unit, so the old
-- "refused means it's near" trick can't tell anything there (tested 2026-11-10).

local _, ns = ...

local TICK = 1           -- seconds between scans
local ALERT_AGAIN = 3    -- seconds a mob has to be out of reach before it alerts again
local FORGET_AFTER = 60  -- seconds after which a single mob that is gone is forgotten
local MAX_PLATES = 40    -- nameplate1 .. nameplate40

local byName, byNpc = {}, {} -- lookups built from the list: [lowercase name] / [npcID] = key
local seen = {}              -- [key] = when it was last found
local ones = {}              -- [key] = { [guid] = when that one mob was last found }
local IN_RANGE = TICK * 2.5  -- seconds: a mob found this recently counts as in range now
local waiting = {}           -- [key] = { how, yards }: "alert for each one" alerts held for a frame
-- The game takes a mob's nameplate away when the camera turns from it, though it's still there.
-- [guid] = { key, at = when, x, y = where the player stood } for mobs that lost theirs while in
-- reach; they stay counted as in range until the player has moved on or HIDDEN_FOR is up.
local hidden = {}
local LEFT_BEHIND = 45       -- yards the player moves before a mob behind the camera stops counting
local HIDDEN_FOR = 60        -- seconds a mob behind the camera counts at most
local plateGuid = {}         -- [nameplate unit] = the GUID of the listed mob on it

-- Where the player stands, in world yards, or nil where the game doesn't say (dungeons).
function ns.PlayerSpot()
	if not UnitPosition then return end
	local y, x = UnitPosition("player")
	y, x = ns.Plain(y), ns.Plain(x)
	if y and x then return x, y end
end

-- true while the mob `guid`, out of the camera's view, still counts as in range.
local function stillHidden(guid, now)
	local spot = hidden[guid]
	if not spot then return false end
	local gone = now - spot.at >= HIDDEN_FOR and "time is up"
	if not gone and spot.x then
		local x, y = ns.PlayerSpot()
		gone = x ~= nil and (x - spot.x) ^ 2 + (y - spot.y) ^ 2 > LEFT_BEHIND ^ 2 and "you moved on"
	end
	if gone then
		hidden[guid] = nil
		ns.Debug("a mob out of view stopped counting: " .. gone)
	end
	return not gone
end
local rares = {}             -- [rare key] = { name, rare = true }: rares found that aren't listed
local PLAYERS = "players:"   -- the one key every enemy player is found under
rares[PLAYERS] = { name = "Enemy players", players = true }
local RARE_KINDS = { rare = true, rareelite = true } -- the game's classifications counted as rare
local RARE_MARKER = "VignetteKill" -- the start of the map marker atlas of rare mobs

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
		if not byName[key] and not rares[key] then
			seen[key] = nil
			ones[key] = nil
		end
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

-- The key of an unlisted rare, after noting its name for the alert; nil when "every rare" is off.
local function rareKey(guid, name)
	if not ns.db.rares then return end
	name = ns.Plain(name)
	if type(name) ~= "string" or name == "" then return end
	local key = "rare:" .. (ns.NpcID(guid) or name:lower())
	rares[key] = rares[key] or { name = name, rare = true }
	return key
end

-- How many mobs of `key` are in range now.
local function inRange(key)
	local count, now = 0, GetTime()
	for guid, when in pairs(ones[key] or {}) do
		if now - when <= IN_RANGE or stillHidden(guid, now) then count = count + 1 end
	end
	return count
end

-- How many mobs of `key` are in range now, for the alert's message. At least 1 while the name is
-- still being found, also where the game doesn't tell its mobs apart.
function ns.InRange(key)
	local count = inRange(key)
	if count == 0 and seen[key] and GetTime() - seen[key] <= IN_RANGE then count = 1 end
	return count
end

-- Mobs of one name that show up in the same frame share one alert, which says how many are in
-- range, instead of an alert each on top of one another.
local function alertWaiting()
	for key, find in pairs(waiting) do
		waiting[key] = nil
		ns.Alert(key, ns.db.mobs[key] or rares[key], find.how, find.yards, ns.InRange(key))
	end
end

-- A listed mob or a rare was found. `how` is "near" (a nameplate, target, mouseover or focus) or
-- "map" (with `yards`, nil when the map can't tell). `guid` tells one mob of that name from
-- another: with "alert for each one" on, each of them alerts on its own.
local function found(key, how, yards, guid)
	local now = GetTime()
	local last = seen[key]
	seen[key] = now
	guid = ns.Plain(guid)
	local each = false
	if type(guid) == "string" then
		hidden[guid] = nil -- in view again
		ones[key] = ones[key] or {}
		if ns.db.alertEach then
			each = true
			last = ones[key][guid]
		end
		ones[key][guid] = now
	end
	if last and now - last < ALERT_AGAIN then return end
	if not (each or key == PLAYERS) then -- enemy players always show their total
		ns.Alert(key, ns.db.mobs[key] or rares[key], how, yards)
		return
	end
	if not next(waiting) then C_Timer.After(0, alertWaiting) end
	waiting[key] = { how = how, yards = yards }
end

-- Forgets single mobs that have been gone for a while; they'd alert again anyway.
local function forgetOnes()
	local now = GetTime()
	for key, list in pairs(ones) do
		for guid, when in pairs(list) do
			if now - when >= FORGET_AFTER then list[guid] = nil end
		end
		if not next(list) then ones[key] = nil end
	end
end

-- Mobs out of the camera's view that still count are treated as found, so they stay in the
-- total and don't alert again when the camera turns back.
local function keepHidden()
	local now = GetTime()
	for guid, spot in pairs(hidden) do
		local list = ones[spot.key]
		if not list then
			hidden[guid] = nil
		elseif stillHidden(guid, now) then
			list[guid] = now
			seen[spot.key] = now
		end
	end
end

-- A nameplate is going. A dead mob stops counting at once. One that is still in reach was only
-- turned away from, so it keeps counting; one that walked out of reach doesn't.
ns.On("NAME_PLATE_UNIT_REMOVED", function(unit)
	local live = ns.Plain(UnitGUID(unit))
	local guid = type(live) == "string" and live or plateGuid[unit]
	plateGuid[unit] = nil
	if not guid then return end
	for key, list in pairs(ones) do
		if list[guid] then
			local dead, reach = ns.Plain(UnitIsDead(unit)), ns.InReach(unit)
			ns.Debug(string.format("%s left view: unit %s, dead %s, in reach %s", key,
				UnitExists(unit) and "still there" or "gone", tostring(dead), tostring(reach)))
			if dead == true then
				list[guid] = nil
				hidden[guid] = nil
			elseif reach == true then
				local x, y = ns.PlayerSpot()
				hidden[guid] = { key = key, at = GetTime(), x = x, y = y }
			end
			return
		end
	end
end)

ns.On("PLAYER_ENTERING_WORLD", function() wipe(hidden) end)

---------------------------------------------------------------------------
-- Scan radius: the game's nameplate distance
---------------------------------------------------------------------------

ns.RADIUS_MIN, ns.RADIUS_MAX = 30, 40 -- the game shows no nameplate past 40 yards, whatever is set
local APPLY_DELAY = 1 -- seconds after entering the world or leaving combat before putting them back

-- The radius and "nameplates on" are the game's own settings, which other addons may set on
-- every login. So MobSpot keeps what the player picked (ns.db.radius, ns.db.nameplates) and puts
-- it back once the player is in the world, and after combat.

local function setDistance()
	return tonumber(C_CVar.GetCVar("nameplateMaxDistance")) or ns.RADIUS_MAX
end

-- The scan radius in yards: the nameplate distance, up to what the game really shows.
function ns.Radius()
	return math.min(setDistance(), ns.RADIUS_MAX)
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
	-- a pick from before the limits changed is brought inside them
	local radius = ns.db.radius and math.max(ns.RADIUS_MIN, math.min(ns.RADIUS_MAX, ns.db.radius))
	if radius and math.floor(setDistance() + 0.5) ~= radius then
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
	ns.db.radius = math.max(ns.RADIUS_MIN, math.min(ns.RADIUS_MAX, math.floor(yards + 0.5)))
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

-- true inside battlegrounds and arenas, where enemy players are everywhere.
local function pvpGround()
	local _, kind = IsInInstance()
	return kind == "pvp" or kind == "arena"
end

-- true when the player on `unit` is one the options ask to be alerted for.
local function wantedPlayer(unit)
	local faction, attack = ns.db.playersEnemy, ns.db.playersAttack
	if not (faction or attack) or (pvpGround() and not ns.db.playersPvp) then return false end
	if ns.Plain(UnitIsUnit(unit, "player")) ~= false or ns.Plain(UnitIsGhost(unit)) ~= false then return false end
	if attack and ns.Plain(UnitCanAttack("player", unit)) == true then return true end
	if not faction then return false end
	local mine, theirs = UnitFactionGroup("player"), ns.Plain(UnitFactionGroup(unit))
	return (mine ~= nil and theirs ~= nil and mine ~= theirs) or ns.Plain(UnitIsEnemy("player", unit)) == true
end

-- The key of a living listed mob or rare on `unit`, after alerting for it; nil for anything else.
-- An enemy player the options ask for gives the players' key.
local function checkUnit(unit)
	if not UnitExists(unit) then return end
	local player, dead = ns.Plain(UnitIsPlayer(unit)), ns.Plain(UnitIsDead(unit))
	if dead ~= false then return end
	if player == true then
		if not wantedPlayer(unit) then return end
		found(PLAYERS, "near", nil, UnitGUID(unit))
		return PLAYERS
	end
	if player ~= false then return end
	local guid = UnitGUID(unit)
	local key = match(guid, UnitName(unit))
	if not key and RARE_KINDS[ns.Plain(UnitClassification(unit)) or ""] then
		key = rareKey(guid, UnitName(unit))
	end
	if key then found(key, "near", nil, guid) end
	return key
end

local function checkPlate(unit)
	local key = checkUnit(unit)
	local guid = key and ns.Plain(UnitGUID(unit))
	plateGuid[unit] = type(guid) == "string" and guid or nil
	ns.Mark(unit, key and (key == PLAYERS and "player" or "mob"))
end

local function scanUnits()
	if C_NamePlate and C_NamePlate.GetNamePlates then
		for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
			if not plate:IsForbidden() and plate.namePlateUnitToken then
				checkPlate(plate.namePlateUnitToken)
			end
		end
	else
		for i = 1, MAX_PLATES do checkPlate("nameplate" .. i) end
	end
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
		if info and ns.Plain(info.isDead) ~= true then
			local key = match(info.objectGUID, info.name)
			local atlas = ns.Plain(info.atlasName)
			if not key and type(atlas) == "string" and atlas:sub(1, #RARE_MARKER) == RARE_MARKER then
				key = rareKey(info.objectGUID, info.name)
			end
			if key then
				local yards = markerYards(guid)
				if not yards or yards <= radius then found(key, "map", yards, info.objectGUID) end
			end
		end
	end
end

---------------------------------------------------------------------------
-- Running the scans
---------------------------------------------------------------------------

local function tick()
	if not ns.db.enabled or not (next(byName) or ns.db.rares or ns.db.playersEnemy or ns.db.playersAttack) then
		ns.ClearMarks()
	else
		scanUnits()
		scanMarkers()
		keepHidden()
		forgetOnes()
	end
	ns.Fire("Scanned") -- the alert's message follows who is still in range
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
ns.On("PLAYER_FOCUS_CHANGED", function() onUnit("focus") end)

ns.On("VIGNETTE_MINIMAP_UPDATED", function()
	if ns.db.enabled then scanMarkers() end
end)
