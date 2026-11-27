# MobSpot

Alerts you when a mob on your list, any rare, or an enemy player is close by. Made for Retail and WoW Forever.

Type `/ms` (or `/mobspot`) for the options, or find them under Esc > Options > AddOns > MobSpot.

## Adding mobs

- **With a key:** set **MobSpot: Track/Untrack Target** under Esc > Options > Keybindings > MobSpot (the **Set keybinds** button on the options page takes you there). Target a mob and press it to put the mob on the list; press it again with the mob targeted to take it off.
- **By name or ID:** type the name on the options page, exactly as the game shows it, or the mob's NPC ID (the number in its Wowhead link), and press Enter. Handy for a rare you haven't met yet. A mob added by ID shows its name once the game knows it, at the latest when it's first spotted.
- `/ms target` does the same as the key.

**Scan rares automatically** (on by default), under the list, alerts you for any rare mob close by, on your list or not, with "(rare)" after its name. They don't go on the list.

**Scan enemy-faction players** and **Scan players you can attack**, under it, alert you for players: any player of the other faction, or any player you can attack right now. All of them share one **Enemy players** line that says how many are close by, with a sound of its own (**Sound for players**) and a nameplate marker of its own (**Marker for players**: any of the markers, or none). Players don't alert in battlegrounds and arenas unless you turn on **Scan players in battlegrounds and arenas too**.

Each mob on the list has a tick box to stop looking for it for a while without losing it, and an X to take it off. The list is shared by all your characters.

## How far it looks

- **Nameplates:** a listed mob is spotted as soon as its nameplate shows. Enemy nameplates have to be on, also out of combat: the **Nameplates** section on the options page says when they aren't and has a button to turn them on, keeping them on if another addon resets them at login. Your target, mouseover and focus count too.
- **Map markers:** rare mobs the game marks on the map or minimap are spotted across the zone, with live-updating yard distances as you move (even if you hover them from afar), plus a clickable waypoint link in chat. Under **Map markers**, pick **Map pin** (used by WaypointUI too), **TomTom**, both, or **Off**, and optionally turn on **Set waypoint automatically**. Waypoints clear automatically when the rare dies or leaves the map.

While a mob stays close by it alerts only once. It alerts again when it has left and come back. With **Alert for each mob of the same name** on, every mob of that name gets its own alert, and the message shows how many are in range, kept up to date while it's on screen.

## The alert

- A stylized banner at the top of the screen with the mob's name and distance, for up to 5 mobs at once. Click the banner out of combat to target the mob (and set its waypoint when a map-marker rare is shown); it dismisses right away when the mob dies. With **Keep the message on screen** on, it stays for as long as the mob is in range, and 1 minute more when you look away from the mob.
- **Edit Mode:** open the game's Edit Mode to drag the **MobSpot alert** box anywhere, right-click to reset its position, or left-click it to adjust **Scale**, **Background**, **Max alerts**, and **Stack direction** (**Grow down** or **Grow up**). Each Edit Mode layout preset keeps its own position and style settings, and renaming a layout carries them over.
- A sound: one of a dozen game alert sounds (raid warning, ready check, alarm clock, boss emote, map ping and more), any sound your other addons share, or none. It plays even with sound effects turned down. If the addon a shared sound comes from isn't loaded, you hear the raid warning instead.
- A line in chat.
- A flash of the screen edges, and the game's taskbar icon blinks when the game is in the background.
- A marker over the mob's nameplate for as long as it shows, so you can pick it out. The skull is the default; you can pick a red cross, star, moon, green arrow, map pin, quest mark, treasure chest, spiky star, glowing orb and more, set its size, and have it bob up and down, pulse, spin or stay still. The options page shows a preview. Only you see it, and it doesn't show in dungeons and raids, where the game keeps nameplates from addons.

Each one can be turned off. **Test alert** (or `/ms test`) shows how it looks.

## Commands

| Command | What it does |
|---|---|
| `/ms` | options (`/ms options` or `/ms config` too) |
| `/ms on`, `/ms off` | scan for your mobs, or stop |
| `/ms target` | add your target to the list, or take it off |
| `/ms add <name or ID>` | add a mob by name or NPC ID |
| `/ms remove <name or ID>` | take a mob off the list |
| `/ms list` | show the list |
| `/ms test` | show a test alert |
| `/ms distance` | test how far your target is and whether its nameplate shows |
| `/ms minimap` | show or hide the minimap button |
| `/whatsnew` | open the What's New window |

The minimap button opens the options; right-click it to turn scanning on or off. Minimap button collectors pick it up, and it's in the addon menu on the minimap too.

## Limits

- Only mobs. Herbs, ore and other things you gather can't be seen by addons.
- A mob is spotted no further out than nameplates show, or than a map marker is shown. The game doesn't let addons look further.
- In some instances the game hides mob names from addons, so nothing there is spotted.

## Made with AI
This addon was made with AI.
