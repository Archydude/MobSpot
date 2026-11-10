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
Alerts you when a mob on your list is close by. Add mobs with one key, by name or NPC ID, and get a sound, an on-screen alert and a marker over the mob.
```

**Main category:** `Map & Minimap`
**Additional categories:** `Combat`

**License:** `MIT License`

**Logo / avatar:** `MobSpot\images\logo-v1.png` (not made yet)

**Description** (paste everything between the lines)

---
```markdown
## Never miss the mob you're hunting

MobSpot keeps a list of the mobs you're looking for and alerts you the moment one of them is close by. Put a rare or a quest mob on the list and go about your business. Made for **WoW Forever**.

### Add mobs your way
- **One key:** target a mob and press **Track/Untrack Target** to put it on the list. Press it again to take it off.
- **By name or NPC ID:** type it on the options page, handy for a rare you haven't met yet.
- Untick a mob for a while without losing it. The list is shared by all your characters.

### Spotted as soon as it shows
- A listed mob is spotted the moment its nameplate shows. The scan radius is your nameplate distance, 30 to 100 yards, set with a slider.
- Rares the game marks on the map or minimap are spotted too, and the alert says how many yards away they are.
- MobSpot can turn enemy nameplates on for you, and keeps your radius and nameplates the way you set them, even when another addon resets them at login.

### An alert you won't miss
- The mob's name and how close it is, big at the top of the screen.
- A sound that plays even with sound effects turned down: a dozen game alerts, or any sound your other addons share.
- A chat line and a flash of the screen edges.
- You pick how soon the same mob can alert again.

### A marker over the mob
A skull over its nameplate, so you can pick it out of a crowd. Or a red cross, star, moon, green arrow, map pin, quest mark, treasure chest and more, in any size, bobbing, pulsing, spinning or still. Only you see it.

### Good to know
- **/ms** or the minimap button opens the options.
- Only mobs: the game doesn't let addons see herbs, ore or other things you gather.
- Mobs are spotted no further out than nameplates or map markers show. There's no marker in dungeons and raids.

**Feedback and bug reports are welcome** in the comments.
```
---

**Source / Issues links:** `https://github.com/Archydude/MobSpot` and `https://github.com/Archydude/MobSpot/issues`

## B. Upload File form

**File:** `dist\MobSpot-1.0.0.zip`

**Display name**
```
MobSpot 1.0.0
```

**Release type:** `Release`

**Game versions:** Forever `1.60.1`.

**Changelog** (paste only the newest part; paste older parts too if they never went up)
```markdown
1.0.0
- First release: keep a list of mobs to look for and get an alert when one is close by.
- Target a mob and press your MobSpot key to put it on the list, or press it again to take it off. You can also type a mob's name or NPC ID on the options page.
- The scan radius is your nameplate distance, 30 to 100 yards, set with a slider on the options page. MobSpot can turn enemy nameplates on for you, and keeps both that way when another addon resets them at login.
- Mobs the game marks on the map are spotted too, with how far away they are.
- The alert: the mob's name at the top of the screen, a sound (a dozen game sounds, or any sound your other addons share), a chat line and a flash of the screen edges, each one an option. You pick how soon the same mob can alert again.
- A marker over the nameplate of a mob on your list, so you can pick it out: a skull or one of a dozen others, in the size you pick, bobbing, pulsing, spinning or still.
```
