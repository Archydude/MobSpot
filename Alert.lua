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

local function layout()
	for i, row in ipairs(showing) do
		row:ClearAllPoints()
		row:SetPoint("TOP", UIParent, "TOP", 0, MESSAGE_TOP - (i - 1) * MESSAGE_ROW)
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

local function flashScreen()
	if not flash then buildFlash() end
	flash:Show()
	flash.pulse:Restart()
	C_Timer.After(FLASH_FOR, function()
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

local function show(name, how, yards, testing, count, key)
	local detail = detailText(how, yards, count)
	if ns.db.screenText then showMessage(name, detail, key, count) end
	if ns.db.chatLine then
		ns.Print("|cffff8040" .. name .. "|r" .. (count and ": " or " ") .. detail .. (testing and " (test)." or "."))
	end
	ns.PlayAlertSound(ns.db.sound)
	if ns.db.flash then flashScreen() end
end

-- A listed mob or a rare (list key `key`) was found. `how` is "near" or "map" (with `yards`).
-- `count` is how many of it are in range, when each one alerts on its own.
function ns.Alert(key, mob, how, yards, count)
	if mob then show(mob.rare and (mob.name .. " (rare)") or mob.name, how, yards, false, count, key) end
end

function ns.TestAlert()
	show("Test Mob", "near", nil, true)
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
