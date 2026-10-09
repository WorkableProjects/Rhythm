# Rhythm: Xcode Setup and iPhone Install Guide

Install Xcode, open `Rhythm.xcodeproj`, set one bundle ID prefix and your signing team, then press Run with your iPhone selected. Plan on about an hour the first time, most of it waiting for Xcode to download.

## What you need

| Item | Requirement |
| --- | --- |
| Mac | A macOS version the current Xcode supports (shown on Xcode's Mac App Store page) |
| Xcode | 26 or later (CI builds with Xcode 26.6) |
| Free disk space | About 40 GB for Xcode and an iOS simulator |
| iPhone | iOS 26 or later |
| Apple Account | Any Apple Account; a paid Developer Program membership is not required |
| Cable | A USB-C or Lightning cable that carries data, not just charging |

## Step 1: Install Xcode

1. Open the **App Store** on your Mac, search for **Xcode**, and click **Get**. Expect 30–60 minutes.
2. Open Xcode once. Accept the license and let it install its extra components.
3. When Xcode asks which platforms to install, include **iOS**. If you skipped it: **Xcode → Settings → Components** → install the latest iOS platform.
4. Sign in: **Xcode → Settings → Accounts → +** → **Apple Account**. A **Personal Team** appears under your name.

## Step 2: Get the code onto your Mac

```bash
mkdir -p ~/Developer && cd ~/Developer
git clone https://github.com/WorkableProjects/Rhythm.git
cd Rhythm
git checkout claude/kind-galileo-wduugk   # until this branch is merged
open Rhythm.xcodeproj
```

If Terminal asks to install command-line developer tools, click **Install** and run the commands again. Xcode may take a minute to resolve the local `RhythmCore` package the first time.

## Step 3: One-time project settings

Apple requires an app ID nobody else uses. Rhythm derives all of its IDs from one build setting, so you change it once.

1. In the left sidebar, click the blue **Rhythm** project icon.
2. Under **PROJECT** (not TARGETS), select **Rhythm** → **Build Settings** → **All**.
3. Search for `RHYTHM_BUNDLE_ID_PREFIX` and change `com.example` to something unique, such as `com.yourname` (letters, numbers, dots, hyphens).
4. Under **TARGETS**, select **Rhythm** → **Signing & Capabilities**. Tick **Automatically manage signing** and set **Team** to your Personal Team.
5. Repeat step 4 for **RhythmWidgetsExtension**.

Result: app `com.yourname.rhythm`, widgets `com.yourname.rhythm.widgets`, App Group `group.com.yourname.rhythm`.

## Step 4: Run in the Simulator first

The Simulator separates code problems from phone or signing problems.

1. In Xcode's toolbar, check the scheme is **Rhythm** and pick a simulator (e.g. **iPhone 17**).
2. **⌘B** to build. Fix any red errors first (see Troubleshooting).
3. **⌘R** to run. Tap **Explore a Sample** and check that Today shows the current period counting down.
4. Optional: **⌘U** runs all tests. From Terminal, `scripts/ci-ios.sh` does the same.

## Step 5: Prepare your iPhone

1. Unlock the iPhone and connect it to the Mac.
2. Tap **Trust** on the iPhone and enter your passcode.
3. In Xcode, open **Window → Devices and Simulators** and confirm the iPhone appears. The first connection can take a few minutes.
4. Turn on Developer Mode: **Settings → Privacy & Security → Developer Mode**, let the phone restart, then tap **Turn On**. If the option isn't there, do Step 6 once; iOS shows it after Xcode first tries to install an app.
5. Optional: tick **Connect via network** in Devices and Simulators to install over Wi-Fi later.

## Step 6: Install Rhythm on your iPhone

1. In Xcode's toolbar, change the destination to your iPhone.
2. Press **⌘R**. Xcode builds, signs, installs and opens Rhythm.
3. If the phone says **Untrusted Developer**: **Settings → General → VPN & Device Management** → your Apple Account → **Trust**, then ⌘R again.
4. Set up your schedule. Rhythm asks for notification permission only when you add your first reminder.
5. Live Activity: it's on by default. Check that Live Activities are allowed for Rhythm in the iPhone's Settings app. In Rhythm's **Settings → Live Activity**, **Start Now** shows it immediately and **Status** shows what iOS reports.
6. So it starts every school day without opening Rhythm, add the automation in **Settings → Live Activity → Start Automatically Every Day** (Shortcuts → Automation → Time of Day → Run Immediately → *Start Rhythm Live Activity*).
7. Widgets: long-press the Home Screen → **Edit → Add Widget** → search for Rhythm.

## Keeping it installed

- **Free Apple Account:** the app's signature expires after 7 days and Rhythm stops opening. Reconnect and press ⌘R; your data is kept. A free account can have 3 such apps installed at once.
- **Paid Developer Program:** signatures last a year, and you can share builds through TestFlight.
- **New code:** `cd ~/Developer/Rhythm && git pull`, then ⌘R.
- Don't delete Rhythm from the phone to fix a problem unless you're happy to lose your schedule. Export it first from **Settings → Export Timetable**.

## Troubleshooting

| Problem | Fix |
| --- | --- |
| "No account for team" or no team to choose | Xcode → Settings → Accounts → add your Apple Account, then reselect the team on both targets |
| "Bundle identifier is not available" | Change `RHYTHM_BUNDLE_ID_PREFIX` to something more unique (Step 3) |
| App Group or provisioning error | Remove the `com.apple.security.application-groups` entry from both `Config/Rhythm.entitlements` and `Config/RhythmWidgets.entitlements`. The app works; widgets show "Open Rhythm to update" |
| iPhone not in the destination list | Unlock it, reconnect, tap Trust, check Window → Devices and Simulators |
| "Developer Mode disabled" | Settings → Privacy & Security → Developer Mode, then restart |
| "iOS version not supported" / device not ready | Update Xcode to a release that supports the phone's iOS version |
| "Untrusted Developer" on launch | Settings → General → VPN & Device Management → Trust |
| App stopped opening after a week | Free-account signature expired; reconnect and press ⌘R |
| Red build errors | Product → Clean Build Folder (⇧⌘K) and build again; report the first error from the Issue navigator |
| Live Activity doesn't appear | Check Rhythm's Settings → Live Activity → Status and the message under it (it shows iOS's reason). Automatic display runs from an hour before first bell to last bell; use Start Now any time, and add the Shortcuts automation for a daily start without opening the app |
