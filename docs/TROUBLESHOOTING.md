# Troubleshooting

Messages in quotes are the ones Orbit shows. Orbit's bundle identifier, used in some commands below, is `io.github.ntony46.orbit`. If you build Orbit yourself with a different `PRODUCT_BUNDLE_IDENTIFIER` in `Config/Local.xcconfig`, use yours instead.

## First launch

### Orbit is blocked or "can't be opened"

**Cause.** Release builds are signed ad hoc and not notarized. A downloaded copy carries the quarantine mark, so Gatekeeper checks it on first launch and refuses it, saying Apple could not verify that Orbit is free of malware.

**Fix.** Click Done, not Move to Trash. Then open System Settings > Privacy & Security, find the note that Orbit was blocked in the Security section, click Open Anyway and confirm. On current macOS, right-click > Open shows the same warning again, so use Open Anyway.

Do not turn off Gatekeeper or strip the quarantine mark to get past this.

`spctl -a -vv Orbit.app` reports `rejected` for every ad-hoc signed copy, including one you build yourself. That is expected: Gatekeeper only stops a copy that carries the quarantine mark, and Open Anyway lets that copy through.

### "Orbit is damaged and can't be opened"

**Cause.** The app's signature does not match its contents. This happens when the download was incomplete, or when the zip was extracted by a tool that dropped parts of the app bundle.

**Fix.** Delete the copy, download the zip again, compare its checksum if the release lists one, and extract it by double-clicking it in Finder. You can check the signature yourself; this prints nothing when the signature is intact:

```
codesign --verify --deep --strict /Applications/Orbit.app
```

If it still fails, build Orbit from source instead of working around the check.

## Signing in

### "No Spotify Client ID is configured."

**Cause.** Your copy has no Client ID built in and none is set in Settings.

**Fix.** Create a Spotify Developer app as described in [SPOTIFY_SETUP.md](SPOTIFY_SETUP.md) and paste its Client ID into Settings > Spotify > Spotify Client ID.

### "Port 8888 is in use, so sign-in can't finish."

**Cause.** Orbit receives Spotify's sign-in callback on `127.0.0.1:8888`, and another program is already listening on that port. Jupyter and many local development servers use 8888 by default. The port is fixed because it is part of the registered redirect URI.

**Fix.** Find the program:

```
lsof -nP -iTCP:8888 -sTCP:LISTEN
```

Quit it, then click Sign In again. Orbit holds the port only while a sign-in is in progress, so you can restart the other program afterwards.

While the port is taken, Orbit does not open the browser, so no sign-in callback goes to the other program. If you do not recognize the program holding the port, look into it before quitting it.

### Spotify's page shows an error instead of the Agree button

**Cause.** The Client ID is wrong, or the redirect URI registered for the app does not match what Orbit sends.

**Fix.** In the Spotify Developer Dashboard, check that the app's redirect URIs include exactly `http://127.0.0.1:8888/callback` and that the Client ID in Orbit matches the dashboard.

### Sign-in never finishes

**Cause.** Orbit waits five minutes for the browser to return to `127.0.0.1:8888/callback`, then gives up.

**Fix.** Click Sign In again and finish in the browser tab that opens. If the browser cannot reach `127.0.0.1`, check that no proxy or browser extension intercepts local addresses.

If the browser shows "Sign-in didn't finish.", the callback did not carry the code Orbit was waiting for: Spotify reported an error, or the tab belonged to an earlier sign-in attempt. Close it, click Sign In again and use the newest tab.

### "This Spotify account isn't enabled for this Orbit client."

**Cause.** Spotify answered a Web API request with HTTP 403. The Client ID belongs to a Development Mode app, and your Spotify account is not on its User Management list. Spotify's sign-in page may still let you through; the refusal comes on the requests after it.

**Fix.** Ask the app's owner to add your name and your Spotify account's email under User Management in the Spotify Developer Dashboard, then sign in again. Alternatively create your own app and use its Client ID. In Settings > Spotify, the Open Developer Dashboard button next to the error opens the dashboard.

### "Your Spotify session has expired."

**Cause.** Spotify rejected the stored refresh token, for example because you removed Orbit's access in your Spotify account or the developer app was deleted. Orbit also shows this at launch when the stored session lacks a permission Orbit needs; see the next entry.

**Fix.** Click Sign In.

### Orbit asks you to sign in every time it launches

**Cause.** One of two things:

- At launch Orbit checks the permissions (scopes) recorded with your stored session, and signs out a session that lacks one it needs, showing "Your Spotify session has expired." This is expected once after an update that needs a new permission. If it happens after every sign-in, Spotify is granting Orbit fewer permissions than it asks for.
- Orbit could not read its keychain item, for example because you clicked Deny when macOS asked whether Orbit may use it. Orbit then starts signed out, with no error.

**Fix.** For the first, remove Orbit at [spotify.com/account/apps](https://www.spotify.com/account/apps/), then sign in again and approve every permission on Spotify's page. If it keeps happening, report it with your Orbit version. For the second, sign in and click Always Allow when macOS asks about the keychain item. If you build Orbit yourself, see the next section.

## Keychain prompts after an update or rebuild

**Cause.** Orbit keeps your tokens in the login keychain. The keychain lets an app read its item without asking only if the app's signature matches the one that saved it. Each ad-hoc signed build has a different signature, so after installing an update or rebuilding, macOS asks whether Orbit may use the item.

**Fix.** Enter your login password and click Always Allow. That covers the current build; the next update or rebuild asks once more. If you build Orbit yourself, sign it with a certificate to stop the prompts, as described under [Stable signing](DEVELOPMENT.md#stable-signing-stop-repeat-permission-prompts) in DEVELOPMENT.md; `Scripts/install-local.sh` builds and installs such a copy. Grants then survive every rebuild signed with that certificate, because macOS ties them to the certificate rather than to one build.

## Automation

### "Orbit isn't allowed to control Spotify."

**Cause.** You declined the macOS prompt, or turned Orbit off under Automation. Without it Orbit cannot send commands to the Spotify app on this Mac. When you are signed in, it sends commands through the Web API instead.

**Fix.** Open System Settings > Privacy & Security > Automation, expand Orbit and turn on Spotify. The button next to the message in Orbit goes there directly.

### Orbit is not listed under Automation, or macOS never asked

**Cause.** Orbit asks only when Spotify is running and you use a playback control or click Allow in Orbit. Until then Settings > Spotify shows "Not asked yet" or "Checked when Spotify is running". After a denial, or after an ad-hoc signed update, macOS may keep an old decision and not ask again.

**Fix.** Open Spotify, then click Allow in Settings > Spotify or press play in Orbit. If no prompt appears, reset Orbit's Automation decisions, quit and reopen Orbit, and try again:

```
tccutil reset AppleEvents io.github.ntony46.orbit
```

## Playback

### "Spotify isn't running."

**Cause.** Orbit controls the Spotify desktop app and never launches it by sending a command.

**Fix.** Click Open Spotify in Orbit, which starts Spotify without bringing its window forward, or open Spotify yourself.

### "Spotify isn't installed on this Mac."

**Fix.** Install the Spotify desktop app from spotify.com, then reopen Orbit.

### "No Spotify device is active."

**Cause.** The command went through the Web API and no Spotify device is currently active, for example because Spotify has been idle for a while or nothing has played yet.

**Fix.** Start playback in Spotify, or open the device picker in Orbit's player and choose a device. Devices appear there only while Spotify is open on them.

### "Spotify Premium is required for remote playback control."

**Cause.** Spotify only accepts playback commands through the Web API from Premium accounts. That route is used for other devices, for switching devices, and as the fallback when Automation is unavailable.

**Fix.** Control the Spotify app on this Mac instead, with Automation allowed. Those commands go directly to the app and do not involve the Web API.

### "Spotify didn't start playing that."

**Cause.** Spotify accepted the command but Orbit never saw it playing what you chose.

**Fix.** Check Spotify, then try again from the error.

### "Spotify is limiting requests right now." or "This app's Spotify request quota is used up for now."

**Cause.** Spotify answered with HTTP 429. The first is a short-term rate limit. The second means the Development Mode quota is spent; that quota is shared by every user of the Client ID and every Development Mode app on the owner's account.

**Fix.** Wait. Orbit shows how long when Spotify says, stops sending Web API requests until then, and keeps local playback controls working in the meantime. To use less quota, keep Orbit collapsed or hidden when you are not using it. If the quota runs out often, consider using your own Client ID instead of a shared one.

### "Spotify doesn't share the tracks of playlists you don't own."

This is a Spotify restriction, not an error. You can still play the playlist.

## The pill

### The pill is missing or offscreen

**Fix.** Click the Orbit item in the menu bar:

- Show Pill, if it was hidden.
- Reset Position, if it is off the edge of a display or on a display you cannot see. The same button is in Settings > Behavior.
- Open Player, to open Orbit regardless.

Also check Settings > Behavior: the pill hides while another app is full screen, and can be set to hide when Spotify quits. Orbit has no Dock icon; opening Orbit again from Finder or Spotlight while it runs also shows the panel.

### The menu bar item is missing

Orbit has no Dock icon, so the menu bar item is the main way back in when the pill is hidden. If the menu bar is too crowded, the item may not fit. Opening Orbit again from Finder or Spotlight while it runs brings up the panel. A global shortcut for Open or close Orbit, if you recorded one, does the same.
