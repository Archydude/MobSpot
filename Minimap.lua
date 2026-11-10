-- MobSpot: minimap button (LibDBIcon, so minimap button collectors pick it up) and addon
-- compartment entry. Click for options, right-click to turn scanning on or off.

local _, ns = ...

local NAME = "MobSpot" -- the button's name with LibDBIcon
local LDBIcon = LibStub("LibDBIcon-1.0")
local registered = false

local function fillTooltip(tooltip)
	tooltip:SetText(ns.TITLE)
	if ns.db.enabled then
		tooltip:AddLine("Scanning for your mobs", 0.25, 1, 0.25)
	else
		tooltip:AddLine("Scanning is off", 1, 0.82, 0)
	end
	local on, total = 0, 0
	for _, mob in pairs(ns.db.mobs) do
		total = total + 1
		if mob.on then on = on + 1 end
	end
	tooltip:AddDoubleLine("Mobs on the list", on == total and total or (on .. " of " .. total), 1, 0.82, 0, 1, 1, 1)
	tooltip:AddLine(" ")
	tooltip:AddLine("Click for options, right-click to turn scanning on or off", 0.6, 0.6, 0.6)
end

local function onClick(mouseButton)
	if mouseButton == "RightButton" then
		ns.SetEnabled(not ns.db.enabled)
	else
		ns.OpenOptions()
	end
end

-- Shows or hides the minimap button, from the options or /ms minimap.
function ns.SetMinimapShown(shown)
	ns.db.minimap.hide = not shown
	if registered then
		if shown then LDBIcon:Show(NAME) else LDBIcon:Hide(NAME) end
	end
	ns.Fire("SettingChanged", "minimap")
end

ns.On("PLAYER_LOGIN", function()
	local launcher = LibStub("LibDataBroker-1.1"):NewDataObject(NAME, {
		type = "launcher",
		label = ns.TITLE,
		icon = ns.ICON,
		OnClick = function(_, mouseButton) onClick(mouseButton) end,
		OnTooltipShow = fillTooltip,
	})
	LDBIcon:Register(NAME, launcher, ns.db.minimap)
	registered = true
end)

-- Addon compartment (the addon menu on the minimap), named in the .toc.
function MobSpot_OnAddonCompartmentClick(_, mouseButton)
	onClick(mouseButton)
end

function MobSpot_OnAddonCompartmentEnter(_, menuButton)
	GameTooltip:SetOwner(menuButton, "ANCHOR_LEFT")
	fillTooltip(GameTooltip)
	GameTooltip:Show()
end

function MobSpot_OnAddonCompartmentLeave()
	GameTooltip:Hide()
end
