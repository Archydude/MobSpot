# MobSpot

Alerts you when a mob on your list is close by. Made for WoW Forever.

Type `/ms` (or `/mobspot`) for the options, or find them under Esc > Options > AddOns > MobSpot.

## Adding mobs

- **With a key:** set **MobSpot: Track/Untrack Target** under Esc > Options > Keybindings > AddOns > MobSpot. Target a mob and press it to put the mob on the list; press it again with the mob targeted to take it off.
- **By name or ID:** type the name on the options page, exactly as the game shows it, or the mob's NPC ID (the number in its Wowhead link), and press Enter. Handy for a rare you haven't met yet. A mob added by ID shows its name once the game knows it, at the latest when it's first spotted.
- `/ms target` does the same as the key.

Each mob on the list has a tick box to stop looking for it for a while without losing it, and an X to take it off. The list is shared by all your characters.

## How far it looks

- **Nameplates:** a listed mob is spotted as soon as its nameplate shows, so the scan radius is the game's nameplate distance. The slider on the options page sets it (the game may keep it lower than you pick), and it changes how far away every nameplate shows. Enemy nameplates have to be on, also out of combat: the options page says when they aren't and has a button to turn them on. The radius you pick and the nameplates MobSpot turns on stay that way, also when another addon resets them each time you log in. Your target, mouseover and focus count too.
- **Map markers:** rare mobs the game marks on the map or minimap are spotted within your scan radius, and the alert says how far away they are.

While a mob stays close by it alerts only once. It alerts again after it has been out of reach for a while: 30 seconds unless you pick another time on the options page (5 seconds to 5 minutes).

## The alert

- The mob's name and how close it is, at the top of the screen.
- A sound: one of a dozen game alert sounds (raid warning, ready check, alarm clock, boss emote, map ping and more), any sound your other addons share, or none. It plays even with sound effects turned down. If the addon a shared sound comes from isn't loaded, you hear the raid warning instead.
- A line in chat.
- A flash of the screen edges, and the game's taskbar icon blinks when the game is in the background.
- A marker over the mob's nameplate for as long as it shows, so you can pick it out. The skull is the default; you can pick a red cross, star, moon, green arrow, map pin, quest mark, treasure chest, spiky star, glowing orb and more, set its size, and have it bob up and down, pulse, spin or stay still. The options page shows a preview. Only you see it, and it doesn't show in dungeons and raids, where the game keeps nameplates from addons.

Each one can be turned off. **Test alert** (or `/ms test`) shows how it looks.

## Commands

| Command | What it does |
|---|---|
| `/ms` | options |
| `/ms on`, `/ms off` | scan for your mobs, or stop |
| `/ms target` | add your target to the list, or take it off |
| `/ms add <name or ID>` | add a mob by name or NPC ID |
| `/ms remove <name or ID>` | take a mob off the list |
| `/ms list` | show the list |
| `/ms test` | show a test alert |
| `/ms minimap` | show or hide the minimap button |

The minimap button opens the options; right-click it to turn scanning on or off.

## Limits

- Only mobs. Herbs, ore and other things you gather can't be seen by addons.
- A mob is spotted no further out than nameplates show, or than a map marker is shown. The game doesn't let addons look further.
- In some instances the game hides mob names from addons, so nothing there is spotted.
