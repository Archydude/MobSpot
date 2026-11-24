-- MobSpot: the alert
-- A message at the top of the screen, a sound, a chat line and a screen-edge flash, each one an
-- option.

local _, ns = ...

local SHOW_FOR = 6   -- seconds the message stays before it fades
local FADE = 2       -- seconds the fade takes
local FLASH_FOR = 1.6

-- The game's own sounds. One the game doesn't have (its SOUNDKIT name is missing) is left out.
local GAME_SOUNDS = {
	{ key = "raidwarning", name = "Raid warning", kit = "RAID_WARNING" },
	{ key = "readycheck", name = "Ready check", kit = "READY_CHECK" },
	{ key = "alarm", name = "Alarm clock", kit = "ALARM_CLOCK_WARNING_3" },
	{ key = "alarmshort", name = "Alarm clock, short", kit = "ALARM_CLOCK_WARNING_2" },
	{ key = "bossemote", name = "Boss emote", kit = "RAID_BOSS_EMOTE_WARNING" },
	{ key = "bosswhisper", name = "Boss whisper", kit = "UI_RAID_BOSS_WHISPER_WARNING" },
	{ key = "mapping", name = "Map ping", kit = "MAP_PING" },
	{ key = "pvpqueue", name = "Battleground ready", kit = "PVP_THROUGH_QUEUE" },
	{ key = "questdone", name = "Quest complete", kit = "IG_QUEST_LIST_COMPLETE" },
	{ key = "keystone", name = "Keystone upgrade", kit = "UI_70_CHALLENGE_MODE_KEYSTONE_UPGRADE" },
	{ key = "toast", name = "Friend online", kit = "UI_BNET_TOAST" },
	{ key = "coins", name = "Coins", kit = "LOOT_WINDOW_COIN_SOUND" },
}

ns.SOUNDS = {}
for _, sound in ipairs(GAME_SOUNDS) do
	local kit = SOUNDKIT and SOUNDKIT[sound.kit]
	if kit then ns.SOUNDS[#ns.SOUNDS + 1] = { key = sound.key, name = sound.name, kit = kit } end
end
ns.SOUNDS[#ns.SOUNDS + 1] = { key = "none", name = "No sound" }

-- Sounds other addons share through LibSharedMedia; the saved key is "lsm:" plus its name.
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
local LSM_PREFIX = "lsm:"
local FALLBACK = "raidwarning" -- when a shared sound's addon isn't loaded (any more)

-- Names of the shared sounds, sorted, without LibSharedMedia's own "None".
function ns.SharedSounds()
	if not LSM then return {} end
	local out = {}
	for _, name in ipairs(LSM:List("sound")) do
		if name ~= "None" then out[#out + 1] = name end
	end
	return out
end

function ns.SharedSoundKey(name) return LSM_PREFIX .. name end

function ns.PlayAlertSound(key)
	if type(key) == "string" and key:sub(1, #LSM_PREFIX) == LSM_PREFIX then
		local file = LSM and LSM:Fetch("sound", key:sub(#LSM_PREFIX + 1), true)
		if file then
			PlaySoundFile(file, "Master")
			return
		end
		key = FALLBACK
	end
	for _, sound in ipairs(ns.SOUNDS) do
		if sound.key == key and sound.kit then
			PlaySound(sound.kit, "Master") -- heard even with sound effects turned down
			return
		end
	end
end

---------------------------------------------------------------------------
-- Message and flash
---------------------------------------------------------------------------

local flash

-- The message is up to MAX_MESSAGES rows under one another, one per mob name, the oldest on top.
local MAX_MESSAGES = 3
local MESSAGE_TOP = -140 -- the first row, from the top of the screen
local MESSAGE_ROW = 58   -- from one row to the next
local rows = {}          -- every row built so far
local showing = {}       -- the rows on screen, top to bottom

-- Where the first row's top middle sits, from the top middle of the screen: where the player
-- dragged it in Edit Mode, else the usual spot.
local function messageSpot()
	local spot = ns.db.messageSpot
	if type(spot) == "table" and spot.x and spot.y then return spot.x, spot.y end
	return 0, MESSAGE_TOP
end

local function layout()
	local x, y = messageSpot()
	for i, row in ipairs(showing) do
		row:ClearAllPoints()
		row:SetPoint("TOP", UIParent, "TOP", x, y - (i - 1) * MESSAGE_ROW)
	end
end

local function hideRow(row)
	row:Hide()
	row.id, row.key, row.kept, row.leaving = nil, nil, nil, nil
	for i, other in ipairs(showing) do
		if other == row then
			table.remove(showing, i)
			break
		end
	end
	layout()
end

local function buildRow()
	local row = CreateFrame("Frame", nil, UIParent)
	row:SetSize(700, MESSAGE_ROW)
	row:SetFrameStrata("HIGH")
	row:EnableMouse(false)
	row:Hide()

	row.title = row:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	row.title:SetPoint("TOP")
	row.title:SetTextColor(1, 0.5, 0.25)
	row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	row.detail:SetPoint("TOP", row.title, "BOTTOM", 0, -6)

	local function fader(delay)
		local fade = row:CreateAnimationGroup()
		local alpha = fade:CreateAnimation("Alpha")
		alpha:SetFromAlpha(1)
		alpha:SetToAlpha(0)
		alpha:SetStartDelay(delay)
		alpha:SetDuration(FADE)
		fade:SetScript("OnFinished", function() hideRow(row) end)
		return fade
	end
	row.fade = fader(SHOW_FOR) -- after an alert
	row.fadeNow = fader(0)     -- when a kept message's mob is gone
	rows[#rows + 1] = row
	return row
end

-- The row for the mob `id`: the one it already has, else a free one, else the oldest one's.
local function rowFor(id)
	for _, row in ipairs(showing) do
		if row.id == id then return row end
	end
	local row
	if #showing >= MAX_MESSAGES then
		row = table.remove(showing, 1)
	else
		for _, other in ipairs(rows) do
			if not other:IsShown() then
				row = other
				break
			end
		end
		row = row or buildRow()
	end
	showing[#showing + 1] = row
	return row
end

---------------------------------------------------------------------------
-- Moving the message: a box to drag while the game's Edit Mode is open
---------------------------------------------------------------------------

local MOVER_WIDTH = 420
local MOVER_EDGE = 2 -- the box's outline
local mover

local function placeMover()
	local x, y = messageSpot()
	mover:ClearAllPoints()
	mover:SetPoint("TOP", UIParent, "TOP", x, y)
end

local function buildMover()
	mover = CreateFrame("Frame", nil, UIParent)
	mover:SetSize(MOVER_WIDTH, MAX_MESSAGES * MESSAGE_ROW)
	mover:SetFrameStrata("HIGH")
	mover:SetFrameLevel(50)
	mover:SetClampedToScreen(true)
	mover:SetMovable(true)
	mover:EnableMouse(true)
	mover:RegisterForDrag("LeftButton")
	mover:Hide()

	local fill = mover:CreateTexture(nil, "BACKGROUND")
	fill:SetAllPoints()
	fill:SetColorTexture(0.1, 0.5, 0.9, 0.3)
	local function edge(point, other, width, height)
		local line = mover:CreateTexture(nil, "BORDER")
		line:SetColorTexture(0.4, 0.8, 1, 0.9)
		line:SetPoint(point)
		line:SetPoint(other)
		if width then line:SetWidth(width) else line:SetHeight(height) end
	end
	edge("TOPLEFT", "TOPRIGHT", nil, MOVER_EDGE)
	edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, MOVER_EDGE)
	edge("TOPLEFT", "BOTTOMLEFT", MOVER_EDGE)
	edge("TOPRIGHT", "BOTTOMRIGHT", MOVER_EDGE)

	local title = mover:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("CENTER", 0, 12)
	title:SetText("MobSpot alert")
	local hint = mover:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	hint:SetPoint("TOP", title, "BOTTOM", 0, -6)
	hint:SetText("Drag to move. Right-click to put it back.")

	mover:SetScript("OnDragStart", mover.StartMoving)
	mover:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local middle, top = self:GetCenter(), self:GetTop()
		if middle and top then
			ns.db.messageSpot = {
				x = math.floor(middle - UIParent:GetWidth() / 2 + 0.5),
				y = math.floor(top - UIParent:GetHeight() + 0.5),
			}
		end
		placeMover()
		layout()
	end)
	mover:SetScript("OnMouseUp", function(_, button)
		if button ~= "RightButton" then return end
		ns.db.messageSpot = false
		placeMover()
		layout()
	end)
end

local function showMover()
	if not mover then buildMover() end
	placeMover()
	mover:Show()
end

local function hideMover()
	if mover then mover:Hide() end
end

ns.On("PLAYER_LOGIN", function()
	if not EditModeManagerFrame then return end
	EditModeManagerFrame:HookScript("OnShow", showMover)
	EditModeManagerFrame:HookScript("OnHide", hideMover)
end)

local function buildFlash()
	flash = CreateFrame("Frame", nil, UIParent)
	flash:SetAllPoints()
	flash:SetFrameStrata("BACKGROUND")
	flash:EnableMouse(false)
	flash:Hide()
	local tex = flash:CreateTexture(nil, "BACKGROUND")
	tex:SetTexture("Interface\\FullScreenTextures\\LowHealth")
	tex:SetBlendMode("ADD")
	tex:SetVertexColor(1, 0.55, 0.1)
	tex:SetAllPoints()
	local pulse = flash:CreateAnimationGroup()
	pulse:SetLooping("BOUNCE")
	local alpha = pulse:CreateAnimation("Alpha")
	alpha:SetFromAlpha(0)
	alpha:SetToAlpha(0.9)
	alpha:SetDuration(0.3)
	flash.pulse = pulse
end

-- Shows the message. With `key` (the mob it's about) and "keep the message" on it stays until
-- none of that mob is in range; else it fades after a few seconds. `count` is the total it
-- shows, kept up to date while it's on screen.
local function showMessage(title, detail, key, count)
	local id = key or title
	local row = rowFor(id)
	row.title:SetText(title)
	row.detail:SetText(detail)
	row.fade:Stop()
	row.fadeNow:Stop()
	row:SetAlpha(1)
	row:Show()
	row.id, row.key, row.count, row.leaving = id, key, count, nil
	row.kept = key ~= nil and ns.db.keepMessage
	if not row.kept then row.fade:Play() end
	layout()
end

local flashTimer
local function flashScreen()
	if not flash then buildFlash() end
	flash:Show()
	flash.pulse:Restart()
	if flashTimer then flashTimer:Cancel() end
	flashTimer = C_Timer.NewTimer(FLASH_FOR, function()
		flashTimer = nil
		flash.pulse:Stop()
		flash:Hide()
	end)
	if FlashClientIcon then FlashClientIcon() end
end

---------------------------------------------------------------------------
-- The alert
---------------------------------------------------------------------------

-- "close by" or "32 yards away".
local function where(how, yards)
	if how == "map" and yards then
		return math.floor(yards + 0.5) .. " yards away"
	end
	return "close by"
end

-- "is close by", or with a total "3 close by".
local function detailText(how, yards, count)
	if not count then return "is " .. where(how, yards) end
	if how == "map" and yards then return count .. " in range, this one " .. where(how, yards) end
	return count .. " " .. where(how, yards)
end

local function show(name, how, yards, testing, count, key, sound)
	local detail = detailText(how, yards, count)
	if ns.db.screenText then showMessage(name, detail, key, count) end
	if ns.db.chatLine then
		ns.Print("|cffff8040" .. name .. "|r" .. (count and ": " or " ") .. detail .. (testing and " (test)." or "."))
	end
	ns.PlayAlertSound(sound)
	if ns.db.flash then flashScreen() end
end

-- A listed mob, a rare or enemy players (list key `key`) were found. `how` is "near" or "map"
-- (with `yards`). `count` is how many are in range, for the alerts that show a total.
function ns.Alert(key, mob, how, yards, count)
	if not mob then return end
	local name = mob.rare and (mob.name .. " (rare)") or mob.name
	show(name, how, yards, false, count, key, mob.players and ns.db.playerSound or ns.db.sound)
end

function ns.TestAlert()
	show("Test Mob", "near", nil, true, nil, nil, ns.db.sound)
end

-- After each scan: a kept message goes once its mob is out of range, and a message with a total
-- shows the total as it is now.
-- A kept message that started to go stays after all when its mob is back in range.
local function scanned(row)
	local count = ns.InRange(row.key)
	if row.kept and (count == 0 or not ns.db.keepMessage) then
		row.kept, row.leaving = false, true
		row.fadeNow:Play()
		return
	end
	if row.leaving and count > 0 and ns.db.keepMessage then
		row.fadeNow:Stop()
		row:SetAlpha(1)
		row.kept, row.leaving = true, nil
	end
	if row.count and count > 0 and count ~= row.count then
		row.count = count
		row.detail:SetText(detailText("near", nil, count))
	end
end

ns.Listen("Scanned", function()
	for _, row in ipairs(showing) do
		if row.key then scanned(row) end
	end
end)
