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
local MESSAGE_ROW = 68   -- from one row to the next
local rows = {}          -- every row built so far
local showing = {}       -- the rows on screen, top to bottom

local BANNER_STYLES = {
	rare   = { title = { 1, 0.82, 0.25 }, line = { 1, 0.78, 0.2, 0.85 }, atlas = "VignetteKill" },
	player = { title = { 1, 0.3, 0.3 },   line = { 1, 0.25, 0.25, 0.85 } },
	mob    = { title = { 1, 0.58, 0.22 }, line = { 1, 0.55, 0.2, 0.85 } },
}

local function styleFont(fs, size, ox, oy)
	if fs.GetFont and fs.SetFont then
		local path = fs:GetFont()
		if path then fs:SetFont(path, size, "OUTLINE") end
	end
	if fs.SetShadowOffset then fs:SetShadowOffset(ox, oy) end
	if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, 0.9) end
end

local function sizeRow(row)
	local tw = row.title:GetStringWidth() or 0
	local dw = row.detail:GetStringWidth() or 0
	row:SetWidth(math.max(260, math.min(680, math.max(tw, dw) + 64)))
end

local layoutCache

local function syncLayoutNames(layoutInfo)
	local layouts = (type(layoutInfo) == "table" and layoutInfo.layouts)
		or (EditModeManagerFrame and EditModeManagerFrame.layoutInfo and EditModeManagerFrame.layoutInfo.layouts)
	if type(layouts) ~= "table" then return end
	if layoutCache and #layoutCache == #layouts and ns.db and ns.db.messageLayouts then
		for i = 1, #layouts do
			local oldName = layoutCache[i]
			local newName = layouts[i] and layouts[i].layoutName
			if oldName and newName and oldName ~= newName
				and ns.db.messageLayouts[oldName] and not ns.db.messageLayouts[newName] then
				ns.db.messageLayouts[newName] = ns.db.messageLayouts[oldName]
				ns.db.messageLayouts[oldName] = nil
			end
		end
	end
	layoutCache = {}
	for i = 1, #layouts do
		layoutCache[i] = layouts[i] and layouts[i].layoutName or false
	end
end

local function activeLayoutName()
	if not (EditModeManagerFrame and EditModeManagerFrame.GetActiveLayoutInfo) then return nil end
	local info = EditModeManagerFrame:GetActiveLayoutInfo()
	local name = info and info.layoutName
	if type(name) == "string" and name ~= "" then return name end
end

local function readLayout()
	local name = activeLayoutName()
	return name and ns.db and ns.db.messageLayouts and ns.db.messageLayouts[name] or nil
end

local function writeLayout()
	local name = activeLayoutName()
	if not (name and ns.db) then return nil end
	ns.db.messageLayouts = ns.db.messageLayouts or {}
	if not ns.db.messageLayouts[name] then
		ns.db.messageLayouts[name] = {}
	end
	return ns.db.messageLayouts[name]
end

local function setMessageSpot(val)
	local lay = writeLayout()
	if lay then
		lay.spot = val
	elseif ns.db then
		ns.db.messageSpot = val
	end
end

local function setMessageField(field, dbKey, val)
	local lay = writeLayout()
	if lay then
		lay[field] = val
	elseif ns.db then
		ns.db[dbKey] = val
	end
end

-- Where the first row's top middle sits, from the top middle of the screen: where the player
-- dragged it in Edit Mode, else the usual spot.
local function messageSpot()
	local lay = readLayout()
	local spot
	if lay and lay.spot ~= nil then
		spot = lay.spot
	else
		spot = ns.db and ns.db.messageSpot
	end
	if type(spot) == "table" and spot.x and spot.y then return spot.x, spot.y end
	return 0, MESSAGE_TOP
end

local function alertScale()
	local lay = readLayout()
	local v = (lay and lay.scale ~= nil) and lay.scale or (ns.db and ns.db.messageScale)
	return math.max(0.7, math.min(1.6, tonumber(v) or 1))
end

local function alertBgAlpha()
	local lay = readLayout()
	local a = (lay and lay.bgAlpha ~= nil) and lay.bgAlpha or (ns.db and ns.db.messageBgAlpha)
	if type(a) ~= "number" then return 0.68 end
	return math.max(0, math.min(1, a))
end

local function alertGrow()
	local lay = readLayout()
	local g = (lay and lay.grow ~= nil) and lay.grow or (ns.db and ns.db.messageGrow)
	return g == "up" and "up" or "down"
end

local function alertMax()
	local lay = readLayout()
	local m = (lay and lay.max ~= nil) and lay.max or (ns.db and ns.db.messageMax)
	return math.max(1, math.min(5, math.floor((tonumber(m) or MAX_MESSAGES) + 0.5)))
end

local function applyRowStyle(row)
	local alpha = alertBgAlpha()
	if row.bg then row.bg:SetColorTexture(0.05, 0.06, 0.09, alpha) end
	if row.topLine then row.topLine:SetShown(alpha > 0) end
	if row.bottomLine then row.bottomLine:SetShown(alpha > 0) end
end

local syncClicks
local syncDistDriver

local function layout()
	local x, y = messageSpot()
	local scale = alertScale()
	local sign = alertGrow() == "up" and 1 or -1
	for i, row in ipairs(showing) do
		local dy = sign * (i - 1) * MESSAGE_ROW * scale
		row:SetScale(scale)
		row:ClearAllPoints()
		row:SetPoint("TOP", UIParent, "TOP", x / scale, (y + dy) / scale)
	end
	if syncClicks then syncClicks() end
end

local function hideRow(row)
	row:Hide()
	row.id, row.key, row.kept, row.leaving, row.targetName, row.pin, row.how, row.yards = nil, nil, nil, nil, nil, nil, nil, nil
	for i, other in ipairs(showing) do
		if other == row then
			table.remove(showing, i)
			break
		end
	end
	if syncDistDriver then syncDistDriver() end
	layout()
end

local clicksDirty = false

local function ensureClick(row)
	if row.click then return row.click end
	local click = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
	click:SetSize(700, MESSAGE_ROW)
	click:SetFrameStrata("HIGH")
	click:SetFrameLevel(row:GetFrameLevel() + 1)
	click:RegisterForClicks("AnyUp", "AnyDown")
	if click.SetAttribute then click:SetAttribute("type1", "macro") end
	click:Hide()
	click:SetScript("OnEnter", function()
		GameTooltip:SetOwner(click, "ANCHOR_BOTTOM")
		GameTooltip:SetText(row.targetName or row.title:GetText(), 1, 1, 1)
		local canPin = row.pin and ns.db and ns.db.waypoint ~= "none"
		GameTooltip:AddLine(canPin and "Click to target and set waypoint" or "Click to target", 0.8, 0.8, 0.8)
		GameTooltip:Show()
	end)
	click:SetScript("OnLeave", function() GameTooltip:Hide() end)
	click:SetScript("PostClick", function()
		if row.pin and ns.db and ns.db.waypoint and ns.db.waypoint ~= "none" then
			ns.SetWaypoint(row.targetName or row.title:GetText(), row.pin, ns.db.waypoint, row.key, row.pin.objectGUID)
		end
	end)
	row.click = click
	return click
end

function syncClicks()
	if InCombatLockdown() then
		clicksDirty = true
		return
	end
	clicksDirty = false
	local x, y = messageSpot()
	local scale = alertScale()
	local sign = alertGrow() == "up" and 1 or -1
	local slotOf = {}
	for i, row in ipairs(showing) do slotOf[row] = i end
	for _, row in ipairs(rows) do
		local idx = row:IsShown() and row.targetName and slotOf[row]
		if idx then
			local click = ensureClick(row)
			local dy = sign * (idx - 1) * MESSAGE_ROW * scale
			if click.SetAttribute then
				click:SetAttribute("macrotext1", "/targetexact " .. row.targetName)
			end
			click:SetScale(scale)
			click:SetSize(row:GetWidth(), MESSAGE_ROW)
			click:ClearAllPoints()
			click:SetPoint("TOP", UIParent, "TOP", x / scale, (y + dy) / scale)
			click:Show()
		elseif row.click then
			row.click:Hide()
		end
	end
end

ns.On("PLAYER_REGEN_ENABLED", function()
	if clicksDirty then syncClicks() end
end)

local function buildRow()
	local row = CreateFrame("Frame", nil, UIParent)
	row:SetSize(420, MESSAGE_ROW)
	row:SetFrameStrata("HIGH")
	row:EnableMouse(false)
	row:Hide()

	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints()
	row.bg:SetColorTexture(0.05, 0.06, 0.09, 0.68)

	row.topLine = row:CreateTexture(nil, "ARTWORK")
	row.topLine:SetHeight(2)
	row.topLine:SetPoint("TOPLEFT", 16, 0)
	row.topLine:SetPoint("TOPRIGHT", -16, 0)

	row.bottomLine = row:CreateTexture(nil, "ARTWORK")
	row.bottomLine:SetHeight(2)
	row.bottomLine:SetPoint("BOTTOMLEFT", 16, 0)
	row.bottomLine:SetPoint("BOTTOMRIGHT", -16, 0)

	row.title = row:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	row.title:SetPoint("TOP", 0, -9)
	styleFont(row.title, 22, 2, -2)

	row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	row.detail:SetPoint("TOP", row.title, "BOTTOM", 0, -5)
	styleFont(row.detail, 15, 1, -1)

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
	local limit = alertMax()
	while #showing > limit do
		local old = table.remove(showing, 1)
		old:Hide()
	end
	if #showing >= limit then
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
-- Moving and styling the message in Edit Mode
---------------------------------------------------------------------------

local MOVER_EDGE = 2 -- the box's outline
local mover
local editPanel
local refreshEditPanel

local function placeMover()
	if not mover then return end
	local x, y = messageSpot()
	local scale = alertScale()
	local up = alertGrow() == "up"
	local preview = mover.preview
	if preview then
		applyRowStyle(preview)
		sizeRow(preview)
		preview:SetScale(scale)
		preview:ClearAllPoints()
		if up then
			preview:SetPoint("BOTTOM", mover, "BOTTOM", 0, 0)
		else
			preview:SetPoint("TOP", mover, "TOP", 0, 0)
		end
	end
	local w = (preview and preview:GetWidth() or 320) * scale
	local h = alertMax() * MESSAGE_ROW * scale
	mover:SetSize(w, h)
	mover:ClearAllPoints()
	if up then
		mover:SetPoint("BOTTOM", UIParent, "TOP", x, y - MESSAGE_ROW * scale)
	else
		mover:SetPoint("TOP", UIParent, "TOP", x, y)
	end
end

local function placeEditPanel()
	if not (editPanel and mover) then return end
	editPanel:ClearAllPoints()
	if (mover:GetBottom() or 300) < 290 then
		editPanel:SetPoint("BOTTOM", mover, "TOP", 0, 10)
	else
		editPanel:SetPoint("TOP", mover, "BOTTOM", 0, -10)
	end
end

local function applyAllStyles()
	for _, row in ipairs(rows) do applyRowStyle(row) end
	placeMover()
	layout()
	if editPanel and editPanel:IsShown() then placeEditPanel() end
end

local function buildEditPanel()
	local p = CreateFrame("Frame", nil, UIParent)
	p:SetSize(288, 258)
	p:SetFrameStrata("DIALOG")
	p:SetFrameLevel(100)
	p:EnableMouse(true)
	p:Hide()

	local bg = p:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.06, 0.07, 0.1, 0.94)
	local function border(a, b, w, h)
		local line = p:CreateTexture(nil, "BORDER")
		line:SetColorTexture(0.35, 0.45, 0.65, 0.9)
		line:SetPoint(a)
		line:SetPoint(b)
		if w then line:SetWidth(w) else line:SetHeight(h) end
	end
	border("TOPLEFT", "TOPRIGHT", nil, 1)
	border("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
	border("TOPLEFT", "BOTTOMLEFT", 1)
	border("TOPRIGHT", "BOTTOMRIGHT", 1)

	local header = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	header:SetPoint("TOPLEFT", 14, -12)
	header:SetWidth(236)
	header:SetJustifyH("LEFT")
	header:SetWordWrap(false)
	header:SetText("MobSpot Alert")

	local close = CreateFrame("Button", nil, p, "UIPanelCloseButtonNoScripts")
	close:SetSize(24, 24)
	close:SetPoint("TOPRIGHT", -4, -4)
	close:SetScript("OnClick", function() p:Hide() end)

	local updaters = {
		function()
			local name = activeLayoutName()
			header:SetText(name and ("MobSpot Alert · " .. name) or "MobSpot Alert")
		end,
	}
	local function addSlider(labelText, y, minVal, maxVal, step, getVal, setVal, formatVal)
		local label = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		label:SetPoint("TOPLEFT", 14, y)
		label:SetText(labelText)
		local valText = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		valText:SetPoint("TOPRIGHT", -14, y)

		local slider = CreateFrame("Frame", nil, p, "MinimalSliderWithSteppersTemplate")
		slider:SetSize(256, 20)
		slider:SetPoint("TOPLEFT", 16, y - 18)
		slider:Init(getVal(), minVal, maxVal, math.floor((maxVal - minVal) / step + 0.5))
		local syncing = false
		slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, picked)
			local snapped = math.floor(picked / step + 0.5) * step
			valText:SetText(formatVal(snapped))
			if syncing then return end
			setVal(snapped)
			applyAllStyles()
		end, slider)
		updaters[#updaters + 1] = function()
			local v = getVal()
			syncing = true
			slider:SetValue(v)
			syncing = false
			valText:SetText(formatVal(v))
		end
	end

	addSlider("Scale", -44, 0.7, 1.6, 0.05, alertScale,
		function(v) setMessageField("scale", "messageScale", v) end,
		function(v) return math.floor(v * 100 + 0.5) .. "%" end)
	addSlider("Background", -92, 0, 1, 0.05, alertBgAlpha,
		function(v) setMessageField("bgAlpha", "messageBgAlpha", v) end,
		function(v) return math.floor(v * 100 + 0.5) .. "%" end)
	addSlider("Max alerts", -140, 1, 5, 1, alertMax,
		function(v) setMessageField("max", "messageMax", v) end,
		function(v) return tostring(v) end)

	local growLabel = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	growLabel:SetPoint("TOPLEFT", 14, -194)
	growLabel:SetText("Stack direction")

	local growBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
	growBtn:SetSize(116, 24)
	growBtn:SetPoint("TOPRIGHT", -14, -188)
	growBtn:SetScript("OnClick", function()
		setMessageField("grow", "messageGrow", alertGrow() == "up" and "down" or "up")
		refreshEditPanel()
		applyAllStyles()
	end)
	updaters[#updaters + 1] = function()
		growBtn:SetText(alertGrow() == "up" and "Grow up" or "Grow down")
	end

	local resetBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
	resetBtn:SetSize(110, 24)
	resetBtn:SetPoint("BOTTOMLEFT", 14, 12)
	resetBtn:SetText("Reset")
	resetBtn:SetScript("OnClick", function()
		local name = activeLayoutName()
		if name and ns.db then
			ns.db.messageLayouts = ns.db.messageLayouts or {}
			local customGlobal = ns.db.messageSpot ~= false
				or (ns.db.messageScale ~= nil and ns.db.messageScale ~= 1)
				or (ns.db.messageBgAlpha ~= nil and ns.db.messageBgAlpha ~= 0.68)
				or (ns.db.messageGrow ~= nil and ns.db.messageGrow ~= "down")
				or (ns.db.messageMax ~= nil and ns.db.messageMax ~= 3)
			ns.db.messageLayouts[name] = customGlobal and {
				spot = false, scale = 1, bgAlpha = 0.68, grow = "down", max = 3,
			} or nil
		elseif ns.db then
			ns.db.messageSpot = false
			ns.db.messageScale = 1
			ns.db.messageBgAlpha = 0.68
			ns.db.messageGrow = "down"
			ns.db.messageMax = 3
		end
		refreshEditPanel()
		applyAllStyles()
	end)

	local doneBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
	doneBtn:SetSize(110, 24)
	doneBtn:SetPoint("BOTTOMRIGHT", -14, 12)
	doneBtn:SetText("Done")
	doneBtn:SetScript("OnClick", function() p:Hide() end)

	refreshEditPanel = function()
		for _, fn in ipairs(updaters) do fn() end
	end
	editPanel = p
end

local function buildMover()
	mover = CreateFrame("Frame", nil, UIParent)
	mover:SetSize(320, MESSAGE_ROW)
	mover:SetFrameStrata("DIALOG")
	mover:SetFrameLevel(50)
	mover:SetClampedToScreen(true)
	mover:SetMovable(true)
	mover:EnableMouse(true)
	mover:RegisterForDrag("LeftButton")
	mover:Hide()

	local fill = mover:CreateTexture(nil, "BACKGROUND")
	fill:SetAllPoints()
	fill:SetColorTexture(0.46, 0.71, 0.83, 0.42)
	local function edge(point, other, width, height)
		local line = mover:CreateTexture(nil, "BORDER")
		line:SetColorTexture(0.62, 0.85, 0.96, 0.85)
		line:SetPoint(point)
		line:SetPoint(other)
		if width then line:SetWidth(width) else line:SetHeight(height) end
	end
	edge("TOPLEFT", "TOPRIGHT", nil, MOVER_EDGE)
	edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, MOVER_EDGE)
	edge("TOPLEFT", "BOTTOMLEFT", MOVER_EDGE)
	edge("TOPRIGHT", "BOTTOMRIGHT", MOVER_EDGE)

	local preview = CreateFrame("Frame", nil, mover)
	preview:SetSize(320, MESSAGE_ROW)
	preview.bg = preview:CreateTexture(nil, "BACKGROUND")
	preview.bg:SetAllPoints()
	preview.topLine = preview:CreateTexture(nil, "ARTWORK")
	preview.topLine:SetHeight(2)
	preview.topLine:SetPoint("TOPLEFT", 16, 0)
	preview.topLine:SetPoint("TOPRIGHT", -16, 0)
	preview.topLine:SetColorTexture(unpack(BANNER_STYLES.rare.line))
	preview.bottomLine = preview:CreateTexture(nil, "ARTWORK")
	preview.bottomLine:SetHeight(2)
	preview.bottomLine:SetPoint("BOTTOMLEFT", 16, 0)
	preview.bottomLine:SetPoint("BOTTOMRIGHT", -16, 0)
	preview.bottomLine:SetColorTexture(unpack(BANNER_STYLES.rare.line))
	preview.title = preview:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	preview.title:SetPoint("TOP", 0, -9)
	styleFont(preview.title, 22, 2, -2)
	local atlasPrefix = (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("VignetteKill"))
		and "|A:VignetteKill:20:20:0:-1|a " or ""
	preview.title:SetText(atlasPrefix .. "Rare Mob (rare)")
	preview.title:SetTextColor(unpack(BANNER_STYLES.rare.title))
	preview.detail = preview:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	preview.detail:SetPoint("TOP", preview.title, "BOTTOM", 0, -5)
	styleFont(preview.detail, 15, 1, -1)
	preview.detail:SetText("is |cffffd100120 yards|r away")
	mover.preview = preview

	mover:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("MobSpot Alert", 1, 1, 1)
		GameTooltip:AddLine("Drag to move · Click for options · Right-click to reset", 0.8, 0.8, 0.8)
		GameTooltip:Show()
	end)
	mover:SetScript("OnLeave", function() GameTooltip:Hide() end)

	mover:SetScript("OnMouseDown", function(self, button)
		if button == "LeftButton" then self.dragged = false end
	end)
	mover:SetScript("OnDragStart", function(self)
		self.dragged = true
		self:StartMoving()
	end)
	mover:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local middle = self:GetCenter()
		if middle then
			local scale = alertScale()
			local y
			if alertGrow() == "up" then
				local bottom = self:GetBottom()
				if bottom then y = math.floor(bottom - UIParent:GetHeight() + MESSAGE_ROW * scale + 0.5) end
			else
				local top = self:GetTop()
				if top then y = math.floor(top - UIParent:GetHeight() + 0.5) end
			end
			if y then
				setMessageSpot({
					x = math.floor(middle - UIParent:GetWidth() / 2 + 0.5),
					y = y,
				})
			end
		end
		placeMover()
		layout()
		if editPanel and editPanel:IsShown() then placeEditPanel() end
	end)
	mover:SetScript("OnMouseUp", function(self, button)
		if button == "RightButton" then
			setMessageSpot(false)
			placeMover()
			layout()
			if editPanel and editPanel:IsShown() then placeEditPanel() end
			return
		end
		if button == "LeftButton" and not self.dragged then
			if not editPanel then buildEditPanel() end
			if editPanel:IsShown() then
				editPanel:Hide()
			else
				refreshEditPanel()
				placeEditPanel()
				editPanel:Show()
			end
		end
	end)
end

local function showMover()
	syncLayoutNames()
	if not mover then buildMover() end
	placeMover()
	mover:Show()
end

local function hideMover()
	if mover then mover:Hide() end
	if editPanel then editPanel:Hide() end
end

local function onLayoutChanged(layoutInfo)
	if not ns.db then return end
	syncLayoutNames(layoutInfo)
	applyAllStyles()
	if editPanel and editPanel:IsShown() and refreshEditPanel then
		refreshEditPanel()
	end
end

ns.On("EDIT_MODE_LAYOUTS_UPDATED", onLayoutChanged)

ns.On("PLAYER_LOGIN", function()
	if not EditModeManagerFrame then return end
	syncLayoutNames()
	EditModeManagerFrame:HookScript("OnShow", showMover)
	EditModeManagerFrame:HookScript("OnHide", hideMover)
	for _, method in ipairs({ "SelectLayout", "RenameOrCopyLayout", "RenameSelectedLayout", "UpdateLayoutInfo", "SaveLayouts" }) do
		if EditModeManagerFrame[method] then
			hooksecurefunc(EditModeManagerFrame, method, function() onLayoutChanged() end)
		end
	end
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
local function showMessage(title, detail, key, count, targetName, pin, how, yards, kind)
	local id = key or title
	local row = rowFor(id)
	local st = BANNER_STYLES[kind] or BANNER_STYLES.mob
	local prefix = (st.atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(st.atlas))
		and ("|A:" .. st.atlas .. ":20:20:0:-1|a ") or ""
	row.title:SetText(prefix .. title)
	row.title:SetTextColor(unpack(st.title))
	row.topLine:SetColorTexture(unpack(st.line))
	row.bottomLine:SetColorTexture(unpack(st.line))
	row.detail:SetText(detail)
	row.fade:Stop()
	row.fadeNow:Stop()
	row:SetAlpha(1)
	row:Show()
	row.id, row.key, row.count, row.leaving, row.targetName, row.pin, row.how = id, key, count, nil, targetName, pin, how
	row.yards = yards and math.floor(yards + 0.5) or nil
	row.kept = key ~= nil and ns.db.keepMessage
	if not row.kept then row.fade:Play() end
	applyRowStyle(row)
	sizeRow(row)
	if syncDistDriver then syncDistDriver() end
	layout()
end

function ns.DismissAlert(key, name)
	if not (key or name) then return end
	local lowerName = type(name) == "string" and name ~= "" and name:lower() or nil
	for i = #showing, 1, -1 do
		local row = showing[i]
		if (key and row.key == key) or (lowerName and row.targetName and row.targetName:lower() == lowerName) then
			row.fade:Stop()
			row.fadeNow:Stop()
			hideRow(row)
		end
	end
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
-- Waypoints (Blizzard map pin / WaypointUI / TomTom)
---------------------------------------------------------------------------

ns.WAYPOINTS = {
	{ key = "none", name = "Off" },
	{ key = "pin", name = "Map pin" },
	{ key = "tomtom", name = "TomTom" },
	{ key = "both", name = "Map pin and TomTom" },
}
ns.DEFAULT_WAYPOINT = "pin"

local activeWaypoint

function ns.ClearWaypoint(key, guid)
	if not activeWaypoint then return false end
	if key or guid then
		if not (guid and activeWaypoint.guid == guid) and not (key and activeWaypoint.key == key) then
			return false
		end
	end
	local wp = activeWaypoint
	activeWaypoint = nil
	if wp.hasPin and C_Map and C_Map.HasUserWaypoint and C_Map.HasUserWaypoint()
		and C_Map.GetUserWaypoint and C_Map.ClearUserWaypoint then
		local cur = C_Map.GetUserWaypoint()
		if cur and cur.uiMapID == wp.pin.mapID and cur.position then
			local cx, cy
			if cur.position.GetXY then
				cx, cy = cur.position:GetXY()
			else
				cx, cy = cur.position.x, cur.position.y
			end
			if cx and cy and math.abs(cx - wp.pin.x) < 0.001 and math.abs(cy - wp.pin.y) < 0.001 then
				C_Map.ClearUserWaypoint()
			end
		end
	end
	if wp.tomtomUid and TomTom and TomTom.RemoveWaypoint then
		TomTom:RemoveWaypoint(wp.tomtomUid)
	end
	return true
end

function ns.ClearMissingVignette(present)
	if activeWaypoint and activeWaypoint.pin and activeWaypoint.pin.vignetteGUID
		and not present[activeWaypoint.pin.vignetteGUID] then
		ns.ClearWaypoint()
	end
end

function ns.SetWaypoint(name, pin, mode, key, guid)
	mode = mode or (ns.db and ns.db.waypoint) or "none"
	if not (pin and pin.mapID and pin.x and pin.y) or mode == "none" then return false end
	if activeWaypoint and activeWaypoint.tomtomUid and TomTom and TomTom.RemoveWaypoint then
		TomTom:RemoveWaypoint(activeWaypoint.tomtomUid)
		activeWaypoint.tomtomUid = nil
	end
	local setPin, setTomTom, tomtomUid = false, false, nil
	if mode == "pin" or mode == "both" then
		if C_Map and C_Map.CanSetUserWaypointOnMap and UiMapPoint and UiMapPoint.CreateFromCoordinates
			and C_Map.CanSetUserWaypointOnMap(pin.mapID) then
			C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(pin.mapID, pin.x, pin.y))
			if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
				C_SuperTrack.SetSuperTrackedUserWaypoint(true)
			end
			setPin = true
		end
	end
	if mode == "tomtom" or mode == "both" then
		if TomTom and TomTom.AddWaypoint then
			tomtomUid = TomTom:AddWaypoint(pin.mapID, pin.x, pin.y, {
				title = name,
				from = "MobSpot",
				persistent = false,
				minimap = true,
				world = true,
			})
			setTomTom = true
		end
	end
	if setPin or setTomTom then
		activeWaypoint = {
			key = key,
			guid = guid or pin.objectGUID,
			pin = pin,
			hasPin = setPin,
			tomtomUid = tomtomUid,
		}
		return true
	end
	return false
end

local function pinLink(pin)
	if not (pin and pin.mapID and pin.x and pin.y) then return "" end
	if not (C_Map and C_Map.CanSetUserWaypointOnMap and C_Map.CanSetUserWaypointOnMap(pin.mapID)) then return "" end
	return string.format(" |cffffff00|Hworldmap:%d:%d:%d|h[|A:Waypoint-MapPin-ChatIcon:13:13:0:0|a %.1f, %.1f]|h|r",
		pin.mapID, math.floor(pin.x * 10000 + 0.5), math.floor(pin.y * 10000 + 0.5), pin.x * 100, pin.y * 100)
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

local function bannerWhere(how, yards)
	if how == "map" and yards then
		return "|cffffd100" .. math.floor(yards + 0.5) .. " yards|r away"
	end
	return "|cff55ff88close by|r"
end

local function bannerDetail(how, yards, count)
	if not count then return "is " .. bannerWhere(how, yards) end
	if how == "map" and yards then
		return "|cffffd100" .. count .. "|r in range, this one " .. bannerWhere(how, yards)
	end
	return "|cffffd100" .. count .. "|r " .. bannerWhere(how, yards)
end

local DIST_INTERVAL = 0.2
local distDriver = CreateFrame("Frame")
local distElapsed = 0

local function liveYards(pin)
	if not (pin and pin.mapID and C_Map and C_Map.GetPlayerMapPosition and C_Map.GetWorldPosFromMapPos) then return end
	local spot = pin.vignetteGUID and C_VignetteInfo and C_VignetteInfo.GetVignettePosition
		and C_VignetteInfo.GetVignettePosition(pin.vignetteGUID, pin.mapID) or pin.spot
	local me = spot and C_Map.GetPlayerMapPosition(pin.mapID, "player")
	if not me then return end
	local _, a = C_Map.GetWorldPosFromMapPos(pin.mapID, spot)
	local _, b = C_Map.GetWorldPosFromMapPos(pin.mapID, me)
	if not (a and b) then return end
	local dx, dy = a.x - b.x, a.y - b.y
	return math.sqrt(dx * dx + dy * dy)
end

local function updateDistances(_, elapsed)
	distElapsed = distElapsed + elapsed
	if distElapsed < DIST_INTERVAL then return end
	distElapsed = 0
	for _, row in ipairs(showing) do
		if row.how == "map" and row.pin then
			local yards = liveYards(row.pin)
			if yards then
				local rounded = math.floor(yards + 0.5)
				if rounded ~= row.yards then
					row.yards = rounded
					row.detail:SetText(bannerDetail("map", rounded, row.count))
					sizeRow(row)
				end
			end
		end
	end
end

function syncDistDriver()
	local active = false
	for _, row in ipairs(showing) do
		if row.how == "map" and row.pin then
			active = true
			break
		end
	end
	if active then
		if not distDriver:GetScript("OnUpdate") then
			distElapsed = 0
			distDriver:SetScript("OnUpdate", updateDistances)
		end
	else
		distDriver:SetScript("OnUpdate", nil)
	end
end

local function show(name, how, yards, testing, count, key, sound, targetName, pin, kind)
	local detail = detailText(how, yards, count)
	if ns.db.screenText then showMessage(name, bannerDetail(how, yards, count), key, count, targetName, pin, how, yards, kind) end
	if ns.db.chatLine then
		ns.Print("|cffff8040" .. name .. "|r" .. (count and ": " or " ") .. detail .. (testing and " (test)." or ".") .. pinLink(pin))
	end
	if pin and not testing and ns.db.autoWaypoint then ns.SetWaypoint(targetName or name, pin, nil, key, pin.objectGUID) end
	ns.PlayAlertSound(sound)
	if ns.db.flash then flashScreen() end
end

function ns.AttachPin(key, yards, pin)
	if not key then return end
	for _, row in ipairs(showing) do
		if row.key == key then
			if pin then row.pin = pin end
			if yards then
				row.how = "map"
				row.yards = math.floor(yards + 0.5)
				row.detail:SetText(bannerDetail("map", row.yards, row.count))
				sizeRow(row)
			end
		end
	end
	syncDistDriver()
end

-- A listed mob, a rare or enemy players (list key `key`) were found. `how` is "near" or "map"
-- (with `yards`). `count` is how many are in range, for the alerts that show a total.
-- `pin` is { mapID, x, y } when found on the map.
function ns.Alert(key, mob, how, yards, count, pin)
	if not mob then return end
	local name = mob.rare and (mob.name .. " (rare)") or mob.name
	local targetName = (not mob.players) and mob.name or nil
	local kind = mob.players and "player" or (mob.rare and "rare" or "mob")
	show(name, how, yards, false, count, key, mob.players and ns.db.playerSound or ns.db.sound, targetName, pin, kind)
end

function ns.TestAlert()
	show("Test Mob", "near", nil, true, nil, nil, ns.db.sound, nil, nil, "mob")
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
		row.detail:SetText(bannerDetail("near", nil, count))
		sizeRow(row)
	end
end

ns.Listen("Scanned", function()
	for _, row in ipairs(showing) do
		if row.key then scanned(row) end
	end
end)
