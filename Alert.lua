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

local message, flash

local function buildMessage()
	message = CreateFrame("Frame", nil, UIParent)
	message:SetSize(700, 90)
	message:SetPoint("TOP", 0, -140)
	message:SetFrameStrata("HIGH")
	message:EnableMouse(false)
	message:Hide()

	message.title = message:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	message.title:SetPoint("TOP")
	message.title:SetTextColor(1, 0.5, 0.25)
	message.detail = message:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	message.detail:SetPoint("TOP", message.title, "BOTTOM", 0, -6)

	local fade = message:CreateAnimationGroup()
	local alpha = fade:CreateAnimation("Alpha")
	alpha:SetFromAlpha(1)
	alpha:SetToAlpha(0)
	alpha:SetStartDelay(SHOW_FOR)
	alpha:SetDuration(FADE)
	fade:SetScript("OnFinished", function() message:Hide() end)
	message.fade = fade
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

local function showMessage(title, detail)
	if not message then buildMessage() end
	message.title:SetText(title)
	message.detail:SetText(detail)
	message.fade:Stop()
	message:SetAlpha(1)
	message:Show()
	message.fade:Play()
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

-- "close by (within 40 yards)" or "32 yards away".
local function where(how, yards)
	if how == "map" and yards then
		return math.floor(yards + 0.5) .. " yards away"
	end
	return "close by (within " .. math.floor(ns.Radius() + 0.5) .. " yards)"
end

local function show(name, how, yards, testing)
	local detail = where(how, yards)
	if ns.db.screenText then showMessage(name, "is " .. detail) end
	if ns.db.chatLine then
		ns.Print("|cffff8040" .. name .. "|r is " .. detail .. (testing and " (test)." or "."))
	end
	ns.PlayAlertSound(ns.db.sound)
	if ns.db.flash then flashScreen() end
end

-- A listed mob or a rare was found. `how` is "near" or "map" (with `yards`).
function ns.Alert(mob, how, yards)
	if mob then show(mob.rare and (mob.name .. " (rare)") or mob.name, how, yards) end
end

function ns.TestAlert()
	show("Test Mob", "near", nil, true)
end
