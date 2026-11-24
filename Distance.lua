-- MobSpot: /ms distance
-- A test of the scan radius: says how far away the target is and whether its nameplate shows,
-- and says so again each time either changes, until the target changes or the command is typed
-- again.
--
-- The game gives addons no distance to a mob. It does say whether an item could be used on it,
-- and every item has a fixed reach, so asking about items of different reaches narrows the
-- distance down to a span ("35 to 40 yards"). The yards walked since the command was typed are
-- exact, so standing on the mob when typing it gives the real distance while walking away.

local _, ns = ...

local WATCH_EVERY = 0.2   -- seconds between looks while the test runs
local ITEM_WAIT = 1       -- seconds given to the game to fetch the items on the first run

-- { reach in yards, items with that reach }. Only items this game has are asked about.
local HARM = { -- items used on enemies
	{ 5, 8149, 16308, 17117 },
	{ 10, 9606, 17626, 17689 },
	{ 15, 4559 },
	{ 20, 1191, 4388, 10645 },
	{ 25, 13289 },
	{ 30, 835, 1404, 4941, 7734, 10716 },
	{ 35, 18904, 1399 },
	{ 40, 4945, 8348 },
	{ 45, 221316, 23836, 32698 },
	{ 60, 32825, 37887 },
	{ 70, 41265 },
	{ 80, 35278, 28131 },
	{ 100, 33119, 23715, 17162, 5418 },
}
local HELP = { -- items used on friends
	{ 5, 1970, 8149, 16991 },
	{ 10, 17626, 21267 },
	{ 15, 1251, 2581 },
	{ 20, 12450, 21519 },
	{ 25, 13289 },
	{ 30, 954, 1180, 1851 },
	{ 35, 18904 },
	{ 40, 1713, 5205, 18640 },
	{ 45, 221316, 32698 },
	{ 50, 221315 },
	{ 60, 32825, 37887 },
	{ 70, 41265 },
	{ 80, 35278, 28131 },
	{ 100, 23715, 17162, 5418 },
}

local getItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
local itemInRange = C_Item and C_Item.IsItemInRange or IsItemInRange

local function requestItems()
	if not (C_Item and C_Item.RequestLoadItemDataByID) then return end
	for _, list in ipairs({ HARM, HELP }) do
		for _, row in ipairs(list) do
			for i = 2, #row do C_Item.RequestLoadItemDataByID(row[i]) end
		end
	end
end

-- true when `item` reaches `unit`, false when it doesn't, nil when the game won't say.
local function reaches(item, unit)
	if not getItemInfo(item) then return nil end
	local result = ns.Plain(itemInRange(item, unit))
	if result == true or result == 1 then return true end
	if result == false or result == 0 then return false end
	return nil
end

-- The first answer the items of one reach give for `unit`.
local function rowReaches(row, unit)
	for i = 2, #row do
		local answer = reaches(row[i], unit)
		if answer ~= nil then return answer end
	end
end

local NEAR -- the row of the furthest reach a nameplate shows at
for _, row in ipairs(HARM) do
	if row[1] == ns.RADIUS_MAX then NEAR = row end
end

-- true when `unit`, an enemy, is within nameplate distance, false when it's further away, nil
-- when the game won't say. Scan.lua asks as a nameplate goes: gone from view, or gone for real?
function ns.InReach(unit)
	if not (NEAR and ns.Plain(UnitExists(unit)) == true and ns.Plain(UnitCanAttack("player", unit)) == true) then
		return nil
	end
	return rowReaches(NEAR, unit)
end

ns.On("PLAYER_LOGIN", function()
	if not (NEAR and C_Item and C_Item.RequestLoadItemDataByID) then return end
	for i = 2, #NEAR do C_Item.RequestLoadItemDataByID(NEAR[i]) end
end)

-- The span the target's distance is in: `over` yards or more, `within` yards or less. Either
-- can be nil; both are nil when the game gives no answer for this target.
local function span()
	local list
	if ns.Plain(UnitCanAttack("player", "target")) == true then
		list = HARM
	elseif ns.Plain(UnitCanAssist("player", "target")) == true and not InCombatLockdown() then
		list = HELP
	else
		return
	end
	local over
	for _, row in ipairs(list) do
		local answer = rowReaches(row, "target")
		if answer == true then return over, row[1] end
		if answer == false then over = row[1] end
	end
	return over, nil
end

local function spanText(over, within)
	if over and within then return over .. " to " .. within .. " yards away" end
	if within then return "within " .. within .. " yards" end
	if over then return "over " .. over .. " yards away" end
	return "the game gives no distance for it"
end

local function barShown()
	return C_NamePlate.GetNamePlateForUnit("target") ~= nil
end

local position = ns.PlayerSpot

local watch -- the running test: { ticker, x, y, last }

local function stop(silent)
	if not watch then return end
	watch.ticker:Cancel()
	watch = nil
	if not silent then ns.Print("distance test stopped.") end
end

local function line()
	local dist = spanText(span())
	local shown = barShown()
	local text = dist .. ", nameplate " .. (shown and "showing" or "hidden")
	local x, y = position()
	if watch and watch.x and x then
		local walked = math.sqrt((x - watch.x) ^ 2 + (y - watch.y) ^ 2)
		if walked >= 1 then text = text .. string.format(", %.0f yards from where you started", walked) end
	end
	return text, dist .. (shown and "1" or "0")
end

local function start()
	local name = ns.Plain(UnitName("target")) or "Your target"
	local x, y = position()
	watch = { x = x, y = y }
	local text, state = line()
	watch.last = state
	ns.Print(name .. ": " .. text .. ". The scan radius is " .. string.format("%.0f", ns.Radius()) .. " yards.")
	ns.Print("walk away and it says so each time this changes. /ms distance again stops it.")
	watch.ticker = C_Timer.NewTicker(WATCH_EVERY, function()
		if not UnitExists("target") then
			stop()
			return
		end
		local now, nowState = line()
		if nowState ~= watch.last then
			watch.last = nowState
			ns.Print(now .. ".")
		end
	end)
end

local asked = false -- the items were requested from the game

function ns.TestDistance()
	if watch then
		stop()
		return
	end
	if not UnitExists("target") then
		ns.Print("target something first, then type /ms distance.")
		return
	end
	if asked then
		start()
		return
	end
	asked = true
	requestItems()
	C_Timer.After(ITEM_WAIT, function()
		if UnitExists("target") and not watch then start() end
	end)
end

ns.On("PLAYER_TARGET_CHANGED", function() stop() end)
