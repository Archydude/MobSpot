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
local activePlates = {}      -- [nameplate unit] = true for every nameplate currently shown
local deadGuids = {}         -- [guid] = GetTime() when seen dead, so lingering vignettes stay quiet
local DEAD_FORGET = 300
local seedPlates

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
		ns.Alert(key, ns.db.mobs[key] or rares[key], find.how, find.yards, ns.InRange(key), find.pin)
	end
end

-- A listed mob or a rare was found. `how` is "near" (a nameplate, target, mouseover or focus) or
-- "map" (with `yards`, nil when the map can't tell, and optional `pin` = { mapID, x, y }). `guid` tells
-- one mob of that name from another: with "alert for each one" on, each of them alerts on its own.
local function found(key, how, yards, guid, pin)
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
	if last and now - last < ALERT_AGAIN then
		if how == "map" and (yards or pin) and ns.AttachPin then ns.AttachPin(key, yards, pin) end
		return
	end
	if not (each or key == PLAYERS) then -- enemy players always show their total
		ns.Alert(key, ns.db.mobs[key] or rares[key], how, yards, nil, pin)
		return
	end
	if not next(waiting) then C_Timer.After(0, alertWaiting) end
	waiting[key] = { how = how, yards = yards, pin = pin }
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
	for guid, when in pairs(deadGuids) do
		if now - when >= DEAD_FORGET then deadGuids[guid] = nil end
	end
end

local function markDead(key, guid, name)
	if type(guid) == "string" then
		deadGuids[guid] = GetTime()
		hidden[guid] = nil
		if key and ones[key] then
			ones[key][guid] = nil
			if not next(ones[key]) then
				ones[key] = nil
				seen[key] = nil
			end
		else
			for k, list in pairs(ones) do
				if list[guid] then
					list[guid] = nil
					if not next(list) then
						ones[k] = nil
						seen[k] = nil
					end
					key = key or k
					break
				end
			end
		end
	end
	if key and (key:sub(1, 5) == "rare:" or (type(guid) ~= "string" and not ns.db.alertEach)) then
		ones[key] = nil
		seen[key] = nil
	end
	if ns.ClearWaypoint then ns.ClearWaypoint(key, guid) end
	if (not key or ns.InRange(key) == 0) and (key or name) and ns.DismissAlert then
		ns.DismissAlert(key, name)
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
	activePlates[unit] = nil
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
				markDead(key, guid, ns.Plain(UnitName(unit)))
			elseif reach == true then
				local x, y = ns.PlayerSpot()
				hidden[guid] = { key = key, at = GetTime(), x = x, y = y }
			end
			return
		end
	end
end)

ns.On("PLAYER_ENTERING_WORLD", function()
	wipe(hidden)
	seedPlates()
end)

---------------------------------------------------------------------------
-- Enemy nameplates
---------------------------------------------------------------------------

local IS_RETAIL = WOW_PROJECT_ID ~= nil and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
ns.RADIUS_MAX = IS_RETAIL and 60 or 40 -- the game's nameplate limit (60 on Retail, 40 on Forever)
local APPLY_DELAY = 1 -- seconds after entering the world or leaving combat before putting them back

-- "nameplates on" is the game's own setting, which other addons may set on every login.
-- So MobSpot remembers when the player had it turned on (ns.db.nameplates) and puts it back
-- once the player is in the world, and after combat.

-- Mobs only get a nameplate when enemy nameplates are on and shown out of combat too.
function ns.NameplatesOn()
	return C_CVar.GetCVarBool("nameplateShowEnemies") and C_CVar.GetCVarBool("nameplateShowAll")
end

-- Puts enemy nameplates back on where something else changed them. The game doesn't allow
-- it in combat; it's done again when combat ends.
local function apply()
	if InCombatLockdown() then return end
	if ns.db.nameplates and not ns.NameplatesOn() then
		C_CVar.SetCVar("nameplateShowEnemies", "1")
		C_CVar.SetCVar("nameplateShowAll", "1")
		ns.Fire("SettingChanged", "nameplates")
	end
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
	if dead ~= false then
		if dead == true and player == false then
			local guid = UnitGUID(unit)
			local plainGuid = ns.Plain(guid)
			local name = ns.Plain(UnitName(unit))
			local key = match(guid, name)
			if not key then
				local id = ns.NpcID and ns.NpcID(guid)
				key = id and ("rare:" .. id) or (type(name) == "string" and name ~= "" and ("rare:" .. name:lower()) or nil)
			end
			if key or plainGuid or name then markDead(key, plainGuid, name) end
		end
		return
	end
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

local function plateToken(plate)
	if not plate or plate:IsForbidden() then return end
	return plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
end

function seedPlates()
	wipe(activePlates)
	if C_NamePlate and C_NamePlate.GetNamePlates then
		for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
			local unit = plateToken(plate)
			if unit then activePlates[unit] = true end
		end
	end
	for i = 1, MAX_PLATES do
		local unit = "nameplate" .. i
		if UnitExists(unit) then activePlates[unit] = true end
	end
end

local function scanUnits()
	if C_NamePlate and C_NamePlate.GetNamePlates then
		for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
			local unit = plateToken(plate)
			if unit then activePlates[unit] = true end
		end
	end
	for unit in pairs(activePlates) do
		if UnitExists(unit) then
			checkPlate(unit)
		else
			activePlates[unit] = nil
		end
	end
	checkUnit("target")
	checkUnit("mouseover")
	checkUnit("focus")
end

---------------------------------------------------------------------------
-- Map markers
---------------------------------------------------------------------------

-- Yards from the player to a map marker, plus its mapID and normalized (x, y) coordinates.
-- Falls back to the parent zone map when inside a subzone, and returns nil yards where the map can't tell.
local function markerLocation(guid)
	local mapID = C_Map.GetBestMapForUnit("player")
	if not mapID then return end
	local spot = C_VignetteInfo.GetVignettePosition(guid, mapID)
	if not spot and C_Map.GetMapInfo then
		local info = C_Map.GetMapInfo(mapID)
		if info and info.parentMapID and info.parentMapID > 0 then
			spot = C_VignetteInfo.GetVignettePosition(guid, info.parentMapID)
			if spot then mapID = info.parentMapID end
		end
	end
	if not spot then return end
	local x, y
	if spot.GetXY then
		x, y = spot:GetXY()
	else
		x, y = spot.x, spot.y
	end
	local me = C_Map.GetPlayerMapPosition(mapID, "player")
	local yards
	if me and C_Map.GetWorldPosFromMapPos then
		local _, a = C_Map.GetWorldPosFromMapPos(mapID, spot)
		local _, b = C_Map.GetWorldPosFromMapPos(mapID, me)
		if a and b then
			local dx, dy = a.x - b.x, a.y - b.y
			yards = math.sqrt(dx * dx + dy * dy)
		end
	end
	return yards, mapID, x, y, spot
end

local function scanMarkers()
	if not (ns.db.mapMarkers and C_VignetteInfo) then return end
	local present = {}
	for _, guid in ipairs(C_VignetteInfo.GetVignettes() or {}) do
		local info = C_VignetteInfo.GetVignetteInfo(guid)
		local objGuid = info and ns.Plain(info.objectGUID)
		if info and ns.Plain(info.isDead) == true then
			local name = ns.Plain(info.name)
			local key = match(info.objectGUID, name)
			if not key then
				local id = ns.NpcID and ns.NpcID(objGuid)
				key = id and ("rare:" .. id) or (type(name) == "string" and name ~= "" and ("rare:" .. name:lower()) or nil)
			end
			markDead(key, objGuid, name)
		elseif info and not (objGuid and deadGuids[objGuid]) then
			local key = match(info.objectGUID, info.name)
			local atlas = ns.Plain(info.atlasName)
			if not key and type(atlas) == "string" and atlas:sub(1, #RARE_MARKER) == RARE_MARKER then
				key = rareKey(info.objectGUID, info.name)
			end
			if key then
				present[guid] = true
				local yards, mapID, x, y, spot = markerLocation(guid)
				local pin = (mapID and x and y) and {
					mapID = mapID,
					x = x,
					y = y,
					spot = spot,
					vignetteGUID = guid,
					objectGUID = objGuid,
				} or nil
				found(key, "map", yards, info.objectGUID, pin)
			end
		end
	end
	if C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") and ns.ClearMissingVignette then
		ns.ClearMissingVignette(present)
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
	seedPlates()
	C_Timer.NewTicker(TICK, tick)
end)

local function onUnit(unit)
	if ns.db.enabled then checkUnit(unit) end
end
ns.On("NAME_PLATE_UNIT_ADDED", function(unit)
	activePlates[unit] = true
	if ns.db.enabled then checkPlate(unit) end
end)
ns.On("PLAYER_TARGET_CHANGED", function() onUnit("target") end)
ns.On("PLAYER_REGEN_ENABLED", function() onUnit("target") end)
ns.On("UNIT_HEALTH", function(unit)
	if unit == "target" and ns.db.enabled and ns.Plain(UnitIsDead("target")) == true then
		checkUnit("target")
	end
end)
ns.On("UPDATE_MOUSEOVER_UNIT", function() onUnit("mouseover") end)
ns.On("PLAYER_FOCUS_CHANGED", function() onUnit("focus") end)

ns.On("VIGNETTE_MINIMAP_UPDATED", function()
	if ns.db.enabled then scanMarkers() end
end)
ns.On("VIGNETTES_UPDATED", function()
	if ns.db.enabled then scanMarkers() end
end)
