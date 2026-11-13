-- MobSpot: options
-- Esc > Options > AddOns > MobSpot, or /ms. One page: the mob list, the scan radius, map
-- markers, the alert, keybinds and the minimap button.

local _, ns = ...

local WIDTH = 620     -- the page's content
local ROW_HEIGHT = 26 -- mob list rows
local LIST_ROWS = 7   -- rows the mob list shows before it scrolls
local SOUND_MENU_HEIGHT = 400 -- the sound menu scrolls past this

local category
local content
local refreshers = {} -- functions that bring one control up to date with the settings

local function refreshAll()
	for _, refresh in ipairs(refreshers) do refresh() end
end

-- The game doesn't let addons open its settings during combat, so a request then waits for the fight to end.
local openAfterCombat -- the function to run when combat ends

local function waitForCombatEnd(open, what)
	if not openAfterCombat then
		ns.Print(what .. " open when you leave combat.")
	end
	openAfterCombat = open
end

ns.On("PLAYER_REGEN_ENABLED", function()
	local open = openAfterCombat
	if open then
		openAfterCombat = nil
		open()
	end
end)

function ns.OpenOptions()
	if not category then return end
	if InCombatLockdown() then
		waitForCombatEnd(ns.OpenOptions, "the options")
		return
	end
	Settings.OpenToCategory(category:GetID())
end

---------------------------------------------------------------------------
-- Building blocks
---------------------------------------------------------------------------

local function tooltip(frame, title, body)
	frame:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(title, 1, 1, 1)
		if body then GameTooltip:AddLine(body, nil, nil, nil, true) end
		GameTooltip:Show()
	end)
	frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

local function text(parent, font, value, width)
	local fs = parent:CreateFontString(nil, "ARTWORK", font or "GameFontHighlight")
	fs:SetJustifyH("LEFT")
	if width then fs:SetWidth(width) end
	if value then fs:SetText(value) end
	return fs
end

local function heading(value, y)
	local fs = text(content, "GameFontNormalLarge", value)
	fs:SetPoint("TOPLEFT", 16, y)
	return fs
end

local function checkbox(label, help, get, set)
	local check = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
	local fs = text(check, "GameFontHighlight", label)
	fs:SetPoint("LEFT", check, "RIGHT", 4, 1)
	check.label = fs
	check:SetHitRectInsets(0, -fs:GetStringWidth() - 8, 0, 0)
	check:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
	tooltip(check, label, help)
	table.insert(refreshers, function() check:SetChecked(get()) end)
	return check
end

local function setting(key)
	return function() return ns.db[key] end, function(v)
		ns.db[key] = v
		ns.Fire("SettingChanged", key)
	end
end

-- A slider for the setting `key`, from `minValue` to `maxValue` in steps of `step`, at x, y.
-- `describe(value)` is the text beside it.
local function settingSlider(x, y, minValue, maxValue, step, key, describe)
	local slider = CreateFrame("Frame", nil, content, "MinimalSliderWithSteppersTemplate")
	slider:SetSize(260, 20)
	slider:SetPoint("TOPLEFT", x, y)
	local value = text(content, "GameFontHighlight")
	value:SetPoint("LEFT", slider, "RIGHT", 12, 0)
	slider:Init(ns.db[key], minValue, maxValue, (maxValue - minValue) / step)
	local syncing = false
	slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, picked)
		local v = math.floor(picked + 0.5)
		value:SetText(describe(v))
		if syncing or ns.db[key] == v then return end
		ns.db[key] = v
		ns.Fire("SettingChanged", key)
	end, slider)
	table.insert(refreshers, function()
		syncing = true
		slider:SetValue(ns.db[key])
		syncing = false
		value:SetText(describe(ns.db[key]))
	end)
	return slider
end

local function button(parent, label, width, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetText(label)
	b:SetSize(width, 24)
	b:SetScript("OnClick", onClick)
	return b
end

---------------------------------------------------------------------------
-- Mobs to look for
---------------------------------------------------------------------------

local mobList, mobEmpty

local function drawMobRow(row, data)
	if not row.name then
		row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
		row.check:SetSize(24, 24)
		row.check:SetPoint("LEFT", 2, 0)
		row.check:SetScript("OnClick", function(self)
			ns.SetMobOn(self:GetParent().key, self:GetChecked() and true or false)
		end)
		tooltip(row.check, "Look for this mob", "Untick to stop looking for it without taking it off the list.")
		row.name = text(row, "GameFontHighlight")
		row.name:SetPoint("LEFT", row.check, "RIGHT", 6, 0)
		row.name:SetPoint("RIGHT", -120, 0)
		row.name:SetWordWrap(false)
		row.id = text(row, "GameFontDisable")
		row.id:SetPoint("RIGHT", -34, 0)
		row.remove = CreateFrame("Button", nil, row, "UIPanelCloseButtonNoScripts")
		row.remove:SetSize(22, 22)
		row.remove:SetPoint("RIGHT", -4, 0)
		row.remove:SetScript("OnClick", function(self) ns.RemoveMob(self:GetParent().key) end)
		tooltip(row.remove, "Remove", "Takes the mob off the list.")
	end
	row.key = data.key
	row.check:SetChecked(data.mob.on)
	row.name:SetText(data.mob.name)
	row.name:SetTextColor(data.mob.on and 1 or 0.5, data.mob.on and 1 or 0.5, data.mob.on and 1 or 0.5)
	row.id:SetText((data.mob.npcID and not data.mob.unnamed) and ("ID " .. data.mob.npcID) or "")
end

local function addTyped(box)
	if ns.AddTyped(box:GetText()) then box:SetText("") end
	box:ClearFocus()
end

local function buildMobs(y)
	heading("Mobs to look for", y)
	y = y - 30

	local box = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
	box:SetSize(240, 20)
	box:SetPoint("TOPLEFT", 24, y)
	box:SetAutoFocus(false)
	box:SetFontObject("GameFontHighlight")
	box:SetScript("OnEnterPressed", addTyped)
	box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	local hint = text(box, "GameFontDisable", "Type a mob's name or ID")
	hint:SetPoint("LEFT", 2, 0)
	box:HookScript("OnTextChanged", function(self) hint:SetShown(self:GetText() == "") end)
	box:HookScript("OnEditFocusGained", function() hint:Hide() end)
	box:HookScript("OnEditFocusLost", function(self) hint:SetShown(self:GetText() == "") end)
	tooltip(box, "Add a mob by name or ID",
		"Type its name exactly as the game shows it, or its NPC ID (the number in its Wowhead link), then press Enter.")

	local add = button(content, "Add", 70, function() addTyped(box) end)
	add:SetPoint("LEFT", box, "RIGHT", 8, 0)
	y = y - 32

	local scrollBox = CreateFrame("Frame", nil, content, "WowScrollBoxList")
	scrollBox:SetPoint("TOPLEFT", 16, y)
	scrollBox:SetSize(WIDTH - 30, ROW_HEIGHT * LIST_ROWS)
	-- A sunken box around the list, so an empty or short list still reads as a list.
	local inset = CreateFrame("Frame", nil, content, "InsetFrameTemplate")
	inset:SetPoint("TOPLEFT", scrollBox, "TOPLEFT", -4, 4)
	inset:SetPoint("BOTTOMRIGHT", scrollBox, "BOTTOMRIGHT", 4, -4)
	inset:SetFrameLevel(scrollBox:GetFrameLevel() - 1)
	local bar = CreateFrame("EventFrame", nil, content, "MinimalScrollBar")
	bar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 6, 0)
	bar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 6, 0)
	local view = CreateScrollBoxListLinearView()
	view:SetElementExtent(ROW_HEIGHT)
	view:SetElementInitializer("Button", drawMobRow)
	ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, bar, view)
	bar:SetHideIfUnscrollable(true)
	mobList = scrollBox

	mobEmpty = text(content, "GameFontDisable", nil, WIDTH - 40)
	mobEmpty:SetPoint("TOPLEFT", scrollBox, "TOPLEFT", 8, -6)

	table.insert(refreshers, function()
		mobList:SetDataProvider(CreateDataProvider(ns.SortedMobs()), ScrollBoxConstants.RetainScrollPosition)
		local key = ns.BoundKey(ns.BIND_ADD)
		mobEmpty:SetText("Nothing here yet. Target a mob and press "
			.. (key and key or "your MobSpot key (set it under Keybinds below)")
			.. ", or type its name or ID above.")
		mobEmpty:SetShown(ns.MobCount() == 0)
	end)
	y = y - ROW_HEIGHT * LIST_ROWS - 20

	local get, set = setting("rares")
	checkbox("Scan rares automatically",
		"Alerts you for any rare mob close by, also ones that aren't on your list, and puts the marker over it. They don't go on the list.",
		get, set):SetPoint("TOPLEFT", 16, y)
	return y - 40
end

---------------------------------------------------------------------------
-- Scan radius
---------------------------------------------------------------------------

local function buildRadius(y)
	heading("Scan radius", y)
	y = y - 26
	local about = text(content, "GameFontHighlight",
		"A mob is spotted as soon as its nameplate shows, so the radius is the game's nameplate distance. "
			.. "It changes how far away every nameplate shows, and the game may keep it lower than you pick.",
		WIDTH - 20)
	about:SetPoint("TOPLEFT", 20, y)
	y = y - 44

	local slider = CreateFrame("Frame", nil, content, "MinimalSliderWithSteppersTemplate")
	slider:SetSize(260, 20)
	slider:SetPoint("TOPLEFT", 20, y)
	local value = text(content, "GameFontHighlight")
	value:SetPoint("LEFT", slider, "RIGHT", 12, 0)
	local step = 5
	slider:Init(ns.Radius(), ns.RADIUS_MIN, ns.RADIUS_MAX, (ns.RADIUS_MAX - ns.RADIUS_MIN) / step)
	local syncing = false
	local function showValue()
		value:SetText(math.floor(ns.Radius() + 0.5) .. " yards")
	end
	slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, picked)
		if syncing then return end
		if not ns.SetRadius(picked) then
			value:SetText("|cffffd100" .. math.floor(picked + 0.5) .. " yards after combat|r")
			return
		end
		showValue()
	end, slider)
	table.insert(refreshers, function()
		syncing = true
		slider:SetValue(ns.Radius())
		syncing = false
		showValue()
	end)
	y = y - 34

	local status = text(content, "GameFontHighlight", nil, WIDTH - 200)
	status:SetPoint("TOPLEFT", 20, y)
	local turnOn = button(content, "Turn on nameplates", 170, function() ns.TurnOnNameplates() end)
	turnOn:SetPoint("TOPRIGHT", content, "TOPLEFT", WIDTH, y + 4)
	tooltip(turnOn, "Turn on nameplates", "Shows enemy nameplates, also out of combat, so MobSpot can spot mobs by them.")
	table.insert(refreshers, function()
		if ns.NameplatesOn() then
			status:SetText("|cff40ff40Enemy nameplates are on.|r")
			turnOn:Hide()
		else
			status:SetText("|cffff6060Enemy nameplates are off or only show in combat, so mobs aren't spotted by them.|r")
			turnOn:Show()
		end
	end)
	return y - 40
end

---------------------------------------------------------------------------
-- Map markers
---------------------------------------------------------------------------

local function buildOther(y)
	heading("Map markers", y)
	y = y - 30
	local get, set = setting("mapMarkers")
	local markers = checkbox("Mobs the game marks on the map",
		"Rare mobs the game puts a marker on, on the map or minimap, are spotted within your scan radius, and the alert says how far away they are.",
		get, set)
	markers:SetPoint("TOPLEFT", 16, y)
	return y - 44
end

---------------------------------------------------------------------------
-- Alert
---------------------------------------------------------------------------

local function buildAlert(y)
	heading("Alert", y)
	y = y - 30

	local label = text(content, "GameFontHighlight", "Sound")
	label:SetPoint("TOPLEFT", 22, y - 6)
	local menu = CreateFrame("DropdownButton", nil, content, "WowStyle1DropdownTemplate")
	menu:SetWidth(180)
	menu:SetPoint("TOPLEFT", 90, y)
	if menu.Text then menu.Text:SetFontObject("GameFontHighlight") end
	local function radio(root, name, key)
		root:CreateRadio(name, function() return ns.db.sound == key end, function()
			ns.db.sound = key
			ns.PlayAlertSound(key)
		end)
	end
	menu:SetupMenu(function(_, root)
		if root.SetScrollMode then root:SetScrollMode(SOUND_MENU_HEIGHT) end
		root:CreateTitle("Game sounds")
		for _, sound in ipairs(ns.SOUNDS) do radio(root, sound.name, sound.key) end
		-- listed each time the menu opens, since other addons may add theirs later
		local shared = ns.SharedSounds()
		if #shared > 0 then
			root:CreateDivider()
			root:CreateTitle("Shared by your other addons")
			for _, name in ipairs(shared) do radio(root, name, ns.SharedSoundKey(name)) end
		end
	end)
	table.insert(refreshers, function() menu:GenerateMenu() end)
	local test = button(content, "Test alert", 110, function() ns.TestAlert() end)
	test:SetPoint("LEFT", menu, "RIGHT", 16, 0)
	tooltip(test, "Test alert", "Shows the alert as it would look for a mob on your list. Same as /ms test.")
	y = y - 36

	local again = text(content, "GameFontHighlight",
		"While a mob stays close by it alerts only once. It alerts again after it has been out of reach for:",
		WIDTH - 20)
	again:SetPoint("TOPLEFT", 20, y)
	y = y - 24
	settingSlider(20, y, ns.ALERT_AGAIN_MIN, ns.ALERT_AGAIN_MAX, 5, "alertAgain", function(s)
		return s < 60 and (s .. " seconds")
			or (s % 60 == 0 and (s / 60 .. (s == 60 and " minute" or " minutes")))
			or string.format("%d min %d s", math.floor(s / 60), s % 60)
	end)
	y = y - 36

	local get, set = setting("screenText")
	checkbox("Message at the top of the screen", "The mob's name and how close it is, for a few seconds.", get, set)
		:SetPoint("TOPLEFT", 16, y)
	y = y - 30
	get, set = setting("chatLine")
	checkbox("Line in chat", "The same, in your chat window, so you can look back at it.", get, set)
		:SetPoint("TOPLEFT", 16, y)
	y = y - 30
	get, set = setting("flash")
	checkbox("Flash the screen edges", "Also makes the game's icon blink on your taskbar while the game is in the background.", get, set)
		:SetPoint("TOPLEFT", 16, y)
	return y - 44
end

---------------------------------------------------------------------------
-- Nameplate marker
---------------------------------------------------------------------------

local PREVIEW_BOX = 120 -- the preview's box, wide enough for the biggest marker

local function buildMarker(y)
	heading("Nameplate marker", y)
	local top = y
	y = y - 30

	local get, set = setting("marker")
	checkbox("Show a marker over the mob's nameplate",
		"Shows a marker over a listed mob's nameplate for as long as it shows, so you can pick the mob out. Only you see it. Not in dungeons and raids, where the game keeps nameplates from addons.",
		get, set):SetPoint("TOPLEFT", 16, y)
	y = y - 36

	-- A dropdown picking one of `list` ({ key, name }) for the setting `key`.
	local function choice(label, list, key, default, decorate)
		local fs = text(content, "GameFontHighlight", label)
		fs:SetPoint("TOPLEFT", 22, y - 6)
		local menu = CreateFrame("DropdownButton", nil, content, "WowStyle1DropdownTemplate")
		menu:SetWidth(200)
		menu:SetPoint("TOPLEFT", 110, y)
		if menu.Text then menu.Text:SetFontObject("GameFontHighlight") end
		menu:SetupMenu(function(_, root)
			for _, item in ipairs(list) do
				local name = (decorate and decorate(item) or "") .. item.name
					.. (item.key == default and " |cff808080(default)|r" or "")
				root:CreateRadio(name, function() return ns.db[key] == item.key end, function()
					ns.db[key] = item.key
					ns.Fire("SettingChanged", key)
				end)
			end
		end)
		table.insert(refreshers, function() menu:GenerateMenu() end)
		y = y - 40
	end
	choice("Marker", ns.MARKERS, "markerStyle", ns.DEFAULT_MARKER, function(m) return ns.MarkerIcon(m, 16) .. " " end)
	choice("Animation", ns.MOTIONS, "markerMotion", ns.DEFAULT_MOTION)

	local size = text(content, "GameFontHighlight", "Size")
	size:SetPoint("TOPLEFT", 22, y - 2)
	settingSlider(110, y, ns.MARKER_SIZE_MIN, ns.MARKER_SIZE_MAX, 2, "markerSize", function(v)
		return v .. (v == 34 and " (default)" or "")
	end)

	-- The preview, moving the way it does over a nameplate.
	local box = CreateFrame("Frame", nil, content, "InsetFrameTemplate")
	box:SetSize(PREVIEW_BOX, PREVIEW_BOX)
	box:SetPoint("TOPRIGHT", content, "TOPLEFT", WIDTH, top - 30)
	local preview = ns.NewMarker(box)
	preview:SetPoint("CENTER")
	preview:SetFrameLevel(box:GetFrameLevel() + 5)
	table.insert(refreshers, function()
		preview:SetAlpha(ns.db.marker and 1 or 0.35)
	end)
	return math.min(y - 44, top - 30 - PREVIEW_BOX - 20)
end

---------------------------------------------------------------------------
-- Keybinds and minimap button
---------------------------------------------------------------------------

local function bindLine(label, binding, y)
	local fs = text(content, "GameFontHighlight", nil, WIDTH - 200)
	fs:SetPoint("TOPLEFT", 22, y)
	table.insert(refreshers, function()
		local key = ns.BoundKey(binding)
		fs:SetText(label .. ": " .. (key and ("|cffffd100" .. key .. "|r") or "|cff808080no key set|r"))
	end)
end

local EXPAND_TRIES = { 0, 0.1, 0.3 } -- seconds after opening to look for MobSpot's section

-- Expands MobSpot's section on the Keybindings page, the way clicking its header does.
-- True once it's open (or already was), false while the page hasn't drawn it yet.
local function expandKeybindSection()
	local list = SettingsPanel and SettingsPanel.GetSettingsList and SettingsPanel:GetSettingsList()
	local box = list and list.ScrollBox
	if not (box and box.FindFrameByPredicate) then return true end
	local frame = box:FindFrameByPredicate(function(_, elementData)
		return elementData and elementData.data and elementData.data.name == ns.BIND_SECTION
	end)
	if not frame then return false end
	local data = frame.GetElementData and frame:GetElementData().data
	if data and not data.expanded and frame.Button then frame.Button:Click() end
	return true
end

-- Opens the game's Keybindings page scrolled to MobSpot's own section, opened up.
local function openKeybinds()
	if not Settings.KEYBINDINGS_CATEGORY_ID then
		ns.Print("set it under Esc > Options > Keybindings > MobSpot.")
		return
	end
	if InCombatLockdown() then
		waitForCombatEnd(openKeybinds, "the keybindings")
		return
	end
	Settings.OpenToCategory(Settings.KEYBINDINGS_CATEGORY_ID, ns.BIND_SECTION)
	local done = false
	for _, delay in ipairs(EXPAND_TRIES) do
		C_Timer.After(delay, function()
			if not done then done = expandKeybindSection() end
		end)
	end
end

local function buildKeybinds(y)
	heading("Keybinds", y)
	y = y - 30
	bindLine("Track/Untrack Target", ns.BIND_ADD, y)
	local set = button(content, "Set keybinds", 130, openKeybinds)
	set:SetPoint("TOPRIGHT", content, "TOPLEFT", WIDTH, y + 4)
	tooltip(set, "Set keybinds", "Opens the game's keybindings at MobSpot's key.")
	y = y - 40

	local minimap = checkbox("Show minimap button", "Same as /ms minimap.",
		function() return not ns.db.minimap.hide end, function(v) ns.SetMinimapShown(v) end)
	minimap:SetPoint("TOPLEFT", 16, y)
	return y - 40
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------

local function build()
	local panel = CreateFrame("Frame")
	panel.name = ns.TITLE

	local scroll = CreateFrame("ScrollFrame", nil, panel)
	scroll:SetPoint("TOPLEFT", 0, -4)
	scroll:SetPoint("BOTTOMRIGHT", -22, 4)
	local bar = CreateFrame("EventFrame", nil, panel, "MinimalScrollBar")
	bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 6, 0)
	bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 6, 0)
	ScrollUtil.InitScrollFrameWithScrollBar(scroll, bar)
	bar:SetHideIfUnscrollable(true)
	scroll:EnableMouseWheel(true)

	content = CreateFrame("Frame", nil, scroll)
	content:SetSize(WIDTH + 20, 1)
	scroll:SetScrollChild(content)

	local title = text(content, "GameFontNormalHuge", ns.TITLE)
	title:SetPoint("TOPLEFT", 16, -16)
	local sub = text(content, "GameFontHighlight", "Alerts you when a mob on your list is close by.")
	sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)

	local y = -70
	local get, set = function() return ns.db.enabled end, function(v) ns.SetEnabled(v) end
	checkbox("Scan for my mobs", "Same as /ms on and /ms off.", get, set):SetPoint("TOPLEFT", 16, y)
	y = y - 44

	y = buildMobs(y)
	y = buildRadius(y)
	y = buildOther(y)
	y = buildAlert(y)
	y = buildMarker(y)
	y = buildKeybinds(y)
	content:SetHeight(-y + 24)

	panel:SetScript("OnShow", refreshAll)
	category = Settings.RegisterCanvasLayoutCategory(panel, ns.TITLE)
	Settings.RegisterAddOnCategory(category)
end

ns.Listen("Loaded", build)

local function refreshIfShown()
	if content and content:IsVisible() then refreshAll() end
end
ns.Listen("MobsChanged", refreshIfShown)
ns.Listen("SettingChanged", refreshIfShown)
ns.On("UPDATE_BINDINGS", refreshIfShown)
ns.On("CVAR_UPDATE", refreshIfShown)
