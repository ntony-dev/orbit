# Troubleshooting

Find what you're seeing below, then follow the fix. Text in quotes is exactly what Orbit shows.

| Problem | Go to |
|---|---|
| macOS won't open Orbit | [Orbit won't open](#orbit-wont-open) |
| "Orbit is damaged" | [Orbit is damaged](#orbit-is-damaged) |
| Can't sign in to Spotify | [Signing in](#signing-in) |
| macOS keeps asking for your password after an update | [Password prompts after an update](#password-prompts-after-an-update) |
| Play, pause or skip don't work | [Controlling Spotify](#controlling-spotify) |
| An error in the player or library | [Playback errors](#playback-errors) |
| You can't find Orbit on screen | [Finding Orbit](#finding-orbit) |

## Opening Orbit

### Orbit won't open

macOS says Apple could not verify that Orbit is free of malware. This is expected the first time: Orbit isn't notarized by Apple.

1. Click **Done**. Don't click Move to Trash.
2. Open **System Settings > Privacy & Security**.
3. Scroll down to **Security**, where it says Orbit was blocked, and click **Open Anyway**.
4. Confirm with your password or Touch ID.

You only do this once per download. Right-click > Open doesn't work for this on current macOS.

> Don't turn off Gatekeeper or use Terminal tricks to get past this. If you'd rather not trust a downloaded app, build Orbit yourself (see Install in the [README](../README.md)).

### Orbit is damaged

> "Orbit is damaged and can't be opened."

The download was incomplete or got corrupted.

1. Delete Orbit from Applications.
2. Download the disk image again from Releases.
3. Open it and drag Orbit onto the Applications folder.

Still happening? Build Orbit yourself instead (see Install in the [README](../README.md)).

<details>
<summary>Technical details</summary>

<br>

- The app's signature doesn't match its contents. Check it with the command below; it prints nothing when the signature is intact.

  ```
  codesign --verify --deep --strict /Applications/Orbit.app
  ```

- If the release lists a SHA-256 checksum, compare it with `shasum -a 256 ~/Downloads/Orbit-<version>.dmg`.
- `spctl -a -vv Orbit.app` says `rejected` for every copy of Orbit, including one you build yourself. That's expected and harmless: macOS only blocks a downloaded copy, and Open Anyway lets it through.

</details>

## Signing in

### No Client ID

> "No Spotify Client ID is configured."

Orbit needs your Client ID before you can sign in. Follow [Connect Orbit to Spotify](SPOTIFY_SETUP.md), then paste the ID into **Settings > Spotify**.

### Port 8888 is busy

> "Port 8888 is in use, so sign-in can't finish."

Another app on your Mac is using the connection Orbit needs for sign-in. It's usually a developer tool, such as Jupyter or a local web server.

1. Quit that app.
2. Click **Sign In** in Orbit again.

You can reopen the other app once you're signed in.

<details>
<summary>Find which app it is</summary>

<br>

Run this in Terminal:

```
lsof -nP -iTCP:8888 -sTCP:LISTEN
```

If you don't recognize the app, look into it before quitting it. While the port is taken, Orbit doesn't open the browser, so your sign-in never reaches that app. The port can't be changed: it's part of the redirect URI registered with Spotify.

</details>

### Spotify shows an error instead of Agree

The Client ID or the redirect URI doesn't match your Spotify app. In the [Spotify Developer Dashboard](https://developer.spotify.com/dashboard), open your app's **Settings** and check:

- **Redirect URIs** includes exactly `http://127.0.0.1:8888/callback`.
- **Client ID** matches the one in Orbit's **Settings > Spotify**.

### Sign-in never finishes

Orbit waits five minutes for you to finish in the browser, then stops waiting.

1. Click **Sign In** again.
2. Finish in the newest browser tab, and close any older Spotify tabs.

If the page says "Sign-in didn't finish.", that tab was from an earlier attempt or Spotify reported an error. Sign in again and use the new tab.

If the browser can't load the page at all, a proxy or browser extension may be blocking `127.0.0.1`.

### Your account isn't allowed

> "This Spotify account isn't enabled for this Orbit client."

Your Spotify account isn't on the app's user list.

- **Your own Client ID:** in the [Spotify Developer Dashboard](https://developer.spotify.com/dashboard), open your app's **Settings > User Management** and add your name and the email address of your Spotify account. Then sign in again.
- **A friend's copy:** ask your friend to add your account the same way.

The **Open Developer Dashboard** button next to the error in Settings > Spotify takes you there.

### Signed out unexpectedly

> "Your Spotify session has expired."

Click **Sign In** again. This happens if you removed Orbit's access in your Spotify account, the Spotify app behind your Client ID was deleted, or an update needs a permission you haven't approved yet.

### Orbit asks you to sign in every time

- **If macOS asked about Orbit's keychain item and you clicked Deny:** sign in again, and click **Always Allow** when macOS asks.
- **If you see "Your Spotify session has expired." every launch:** remove Orbit at [spotify.com/account/apps](https://www.spotify.com/account/apps/), then sign in again and approve everything on Spotify's page. If it keeps happening, report it with your Orbit version.

### Password prompts after an update

After you install a new version, macOS asks whether Orbit may use its saved sign-in in your keychain. Enter your Mac password and click **Always Allow**. This happens once per update, because each version of Orbit is signed differently.

<details>
<summary>Stop the prompts if you build Orbit yourself</summary>

<br>

Sign your builds with a certificate instead of ad hoc. macOS then recognizes every rebuild as the same app. See [Stable signing](DEVELOPMENT.md#stable-signing-stop-repeat-permission-prompts) in DEVELOPMENT.md; `Scripts/install-local.sh` builds and installs a copy signed that way.

</details>

## Controlling Spotify

### Orbit isn't allowed to control Spotify

> "Orbit isn't allowed to control Spotify."

You clicked Don't Allow when macOS asked, or turned it off later.

1. Click **Open Automation Settings** next to the message in Orbit, or open **System Settings > Privacy & Security > Automation**.
2. Find **Orbit** and turn on **Spotify**.

Until then, Orbit controls Spotify through Spotify's servers if you're signed in.

### macOS never asked

macOS only asks once Spotify is open and you press play in Orbit. Until then, Settings > Spotify shows "Not asked yet" or "Checked when Spotify is running".

1. Open Spotify.
2. Press play in Orbit, or click **Allow…** in Settings > Spotify.

<details>
<summary>Still no prompt?</summary>

<br>

macOS may be remembering an old answer. Reset it in Terminal, quit and reopen Orbit, and try again:

```
tccutil reset AppleEvents io.github.ntony46.orbit
```

If you built Orbit with your own `PRODUCT_BUNDLE_IDENTIFIER` in `Config/Local.xcconfig`, use that instead of `io.github.ntony46.orbit`.

</details>

### Spotify isn't running

> "Spotify isn't running."

Click **Open Spotify** in Orbit, which starts Spotify without bringing its window forward, or open Spotify yourself. Orbit never opens Spotify on its own.

### Spotify isn't installed

> "Spotify isn't installed on this Mac."

Install the Spotify app from [spotify.com/download](https://www.spotify.com/download/), then reopen Orbit.

## Playback errors

| Message | What to do |
|---|---|
| "No Spotify device is active." | Start playing something in Spotify, or choose a device from the device button in Orbit's player. Devices only appear while Spotify is open on them. |
| "Spotify Premium is required for remote playback control." | Control Spotify on this Mac instead, with Orbit allowed to control it. Controlling other devices needs Premium. |
| "Spotify didn't start playing that." | Check Spotify, then try again. |
| "This device can't be controlled remotely." | Choose another device. |
| "This item isn't available on Spotify anymore." | Click **Refresh Now** in Settings > Spotify, then try again. |
| "Can't reach Spotify." | Check your internet connection. Play, pause and skip on this Mac keep working. |
| "Spotify is limiting requests right now." | Wait. Orbit shows how long, and play, pause and skip keep working meanwhile. |
| "This app's Spotify request quota is used up for now." | Wait, as above. To use less, set **Settings > Spotify > Synchronization** to **Less often**. |
| "Spotify doesn't share the tracks of playlists you don't own." | Not an error. Spotify only lists songs in playlists you own or collaborate on, but you can still play the playlist. |

## Finding Orbit

### The pill is missing

Click the Orbit icon in the top menu bar, then:

- **Show Pill**, if it was hidden.
- **Reset Position**, if it's off the edge of the screen or on a display you can't see. The same button is in Settings > Behavior.
- **Open Player**, to open Orbit anyway.

The pill also hides on its own while another app is full screen, and when Spotify quits if you turned that on. Both are in Settings > Behavior.

### The menu bar icon is missing

If your top menu bar is crowded, Orbit's icon may not fit. To open Orbit anyway:

- Open Orbit again from Finder or Spotlight.
- Or use your **Open or close Orbit** shortcut, if you set one in Settings > Shortcuts.
