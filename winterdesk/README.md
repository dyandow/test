# WinterDesk

A cozy winter scene that lives on your Mac desktop:

- **Snow** falls over everything, on a dimmed winter-night background with warm glowing lights.
- **Snow piles up on top of your windows.** Shake a window quickly back and forth to knock it off.
- **A red steam train** chugs along the bottom of the screen and plows the snow into a mound in front of it.
  Click it to blow the whistle.
- **A Christmas tree** you can drag anywhere. Click its branches to hang lights; click a light to remove it.
- **Tram cables:** drag from the little station at the top-center of the screen and let go anywhere.
  A cable is strung there and a red tram car rides down it and back. Drag the end post to move it,
  right-click it to take it down.

Everything is controlled from the ❄ icon in the menu bar (snow amount, dimming, train, tree, quit…).
Your tree, its lights and your cables are remembered between launches.

## Get it

### Option A: download the built app (no Xcode needed)

1. On GitHub, open **Actions → WinterDesk (Mac app)** and click the latest green run.
2. Download the **WinterDesk** artifact at the bottom, unzip it (twice if needed) to get `WinterDesk.app`.
3. Drag it to **Applications**. The first time, **right-click → Open** (it isn't notarized by Apple),
   or run `xattr -dr com.apple.quarantine /Applications/WinterDesk.app`.

### Option B: build it yourself

Needs macOS 13+ and Apple's command-line tools (`xcode-select --install`).

```bash
cd winterdesk
./build-app.sh
open build/WinterDesk.app
```

For quick tinkering, `swift run` also works (but "Open at Login" only works from the `.app`).

## Notes

- Works on the main display (the one with the menu bar).
- Snow on windows uses each window's position only; no screen-recording permission is needed.
- The overlay only grabs the mouse when the pointer is over the tree, train, station or a cable end;
  everywhere else, clicks go straight through to your apps.
