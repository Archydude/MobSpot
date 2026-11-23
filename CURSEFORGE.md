# MobSpot: CurseForge upload sheet

What to type into each CurseForge field, ready to copy and paste. The steps for a first upload and for releasing an update are in [UPLOADING.md](../UPLOADING.md).

Update this sheet with every release: the zip, the display name and the changelog, and rewrite the description so it covers everything in the new version.

## A. Project form

**Project name**
```
MobSpot
```

**Summary**
```
Alerts you when a mob on your list, or any rare, is close by. Add mobs with one key, by name or NPC ID, and get a sound, an on-screen alert and a marker over the mob.
```

**Main category:** `Map & Minimap`
**Additional categories:** `Combat`

**License:** `MIT License`

**Logo / avatar:** `MobSpot\images\logo-v1.png`

**Description** (paste everything between the lines)

---
```markdown
## Never miss the mob you're hunting

MobSpot keeps a list of the mobs you're looking for and alerts you the moment one of them is close by. Made for **WoW Forever**.

### Add mobs your way
- **One key:** target a mob and press **Track/Untrack Target** to put it on the list. Press it again to take it off.
- **By name or NPC ID:** type it on the options page, handy for a rare you haven't met yet.
- **Every rare:** turn on **Scan rares automatically** and any rare close by alerts you too, no list needed.
- The list is shared by all your characters.

### Spotted as soon as it shows
- A listed mob is spotted the moment its nameplate shows, up to 40 yards away. A slider sets how far.
- Rares the game marks on the map or minimap are spotted too, with how many yards away they are.
- MobSpot can turn enemy nameplates on for you and keep them on.

### An alert you won't miss
- The mob's name, big at the top of the screen, for up to 3 different mobs at once. It can stay for as long as the mob is in range.
- A sound that plays even with sound effects turned down: a dozen game alerts, or any sound your other addons share.
- A chat line and a flash of the screen edges.
- **Several of the same mob:** with **Alert for each mob of the same name**, every one that comes close gets its own alert, with the total in range on screen.
- A mob that leaves and comes back alerts again. Looking away for up to a minute doesn't count as leaving.

### A marker over the mob
A skull over its nameplate, so you can pick it out of a crowd, or one of a dozen other markers, in any size, bobbing, pulsing, spinning or still. Only you see it.

### Good to know
- **/ms** or the minimap button opens the options.
- Only mobs: the game doesn't let addons see herbs, ore or other things you gather.
- There's no marker in dungeons and raids.

This addon was made with AI.

**Feedback and bug reports are welcome** in the comments.
```
---

**Source / Issues links:** `https://github.com/Archydude/MobSpot` and `https://github.com/Archydude/MobSpot/issues`

## B. Upload File form

**File:** `dist\MobSpot-1.2.0.zip`

**Display name**
```
MobSpot 1.2.0
```

**Release type:** `Release`

**Game versions:** Forever `1.60.1`.

**Changelog** (paste only the newest part; paste older parts too if they never went up)
```markdown
1.2.0
- New option: **Alert for each mob of the same name**. Every mob of the same name that comes close gets its own alert, and the message shows how many of them are in range, kept up to date while it's on screen.
- New option: **Keep the message on screen, and 1 minute more when you look away**. The message stays for as long as the mob is in range, instead of fading after a few seconds.
- The message at the top of the screen shows up to 3 different mobs at once, one under the other.
- Turning the camera away from a mob no longer sets off its alert again when you turn back within a minute.
- A mob that leaves and comes back alerts again right away. The slider for how soon it can alert again is gone.
- The scan radius slider goes from 30 to 40 yards, since the game shows no nameplate further away than 40. A higher pick is brought down to 40.
- The alert says "close by", without the yards. A mob found by its map marker still says how many yards away it is.
- New command **/ms distance**: a test of how far away your target is and whether its nameplate shows.

1.1.1
- Fixed an error when opening the options during combat ("tried to call the protected function 'OpenSettingsPanel()'"). The options now open as soon as the fight ends.

1.1.0
- New option under the mob list: **Scan rares automatically**. Any rare mob close by alerts you, with "(rare)" after its name, and gets the marker over its nameplate, without going on your list.
- MobSpot's key has a MobSpot section of its own on the game's Keybindings page, and **Set keybinds** on the options page opens it right at the key. A key you already set stays set.

1.0.0
- First release: keep a list of mobs to look for and get an alert when one is close by.
- Target a mob and press your MobSpot key to put it on the list, or press it again to take it off. You can also type a mob's name or NPC ID on the options page.
- The scan radius is your nameplate distance, 30 to 100 yards, set with a slider on the options page. MobSpot can turn enemy nameplates on for you, and keeps both that way when another addon resets them at login.
- Mobs the game marks on the map are spotted too, with how far away they are.
- The alert: the mob's name at the top of the screen, a sound (a dozen game sounds, or any sound your other addons share), a chat line and a flash of the screen edges, each one an option. You pick how soon the same mob can alert again.
- A marker over the nameplate of a mob on your list, so you can pick it out: a skull or one of a dozen others, in the size you pick, bobbing, pulsing, spinning or still.
```
