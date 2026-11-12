# Setting up Spotify for Orbit

Orbit reads your library and controls Spotify Connect through Spotify's Web API. Spotify only lets an app use the Web API with a Client ID, which you get by registering a Spotify Developer app. Orbit uses Authorization Code with PKCE, so it needs only the Client ID. There is no client secret and no server.

If someone gave you a copy of Orbit with their Client ID built in, you do not need your own app. Ask them to add your Spotify account under User Management (step 3), then go to [First sign-in](#first-sign-in).

## 1. Create the app

1. Sign in at the [Spotify Developer Dashboard](https://developer.spotify.com/dashboard) with the Spotify account that will own the app. That account needs Spotify Premium (see [Development Mode](#what-development-mode-means)).
2. Click Create app and fill in:
   - **App name** and **App description:** anything, for example "Orbit" and "Personal Spotify controller".
   - **Redirect URIs:** add exactly

     ```
     http://127.0.0.1:8888/callback
     ```

     Use `127.0.0.1`, not `localhost`, with `http`, port `8888` and the path `/callback`, and no trailing slash. Orbit sends this exact URI and Spotify rejects anything that does not match a registered one.
   - **APIs used:** select Web API. Orbit uses nothing else.
3. Accept the terms and save.

Ignore the client secret. Orbit never asks for it; do not put it in Orbit's settings, in `Config/Local.xcconfig` or anywhere in the repository.

## 2. Copy the Client ID

Open the app's Settings in the dashboard. The Client ID is under Basic Information. A Client ID is not a secret, but anyone who uses it shares your app's user list and quota.

## 3. Add users

In the app's Settings, open User Management and add each person who will use Orbit with this Client ID: their name and the email address of their Spotify account. Development Mode allows up to five users. Add yourself as well if you are not sure whether the owner is included automatically.

An account that is not on the list can open Spotify's sign-in page, but its requests are refused and Orbit shows "This Spotify account isn't enabled for this Orbit client."

## 4. Give Orbit the Client ID

Orbit reads the Client ID from two places:

- **In the app:** Settings > Spotify, in the Spotify Client ID section at the bottom. Paste the ID into the Client ID field and click Save or press Return. Orbit stores it in its preferences.
- **At build time:** `SPOTIFY_CLIENT_ID` in `Config/Local.xcconfig`, which the build writes into the app's `Info.plist` as `SpotifyClientID`.

```
cp Config/Local.example.xcconfig Config/Local.xcconfig
```

```
SPOTIFY_CLIENT_ID = your_client_id_here
```

The ID entered in Settings wins whenever it is not blank. Clear the field and click Save to go back to the ID built into your copy. The line under the field says which one is in use: "Using your Client ID.", "Using the Client ID built into this copy." or "No Client ID configured. Sign-in needs one."

Orbit reads the Client ID each time you sign in, so a change takes effect without relaunching. An existing session keeps the Client ID it was created with, so after changing it, click Reconnect (or Sign Out, then Sign In) in Settings > Spotify.

## First sign-in

1. Open Settings > Spotify and click Sign In…. Settings opens from Orbit's menu bar item, from the gear in the expanded player, or with Command-comma while the panel is open. You can also click Connect Spotify in the panel.
2. Orbit starts a listener on `127.0.0.1:8888` and opens Spotify's authorization page in your default browser.
3. Check the permissions listed (see [Scopes](#scopes)) and click Agree. If you approved Orbit's Client ID before, Spotify may skip this page and go straight to the next step.
4. Spotify sends the browser back to `http://127.0.0.1:8888/callback`. The page should say "You're signed in to Orbit." You can close the tab.
5. Settings > Spotify shows "Signed in as" followed by your Spotify display name.

Orbit waits up to five minutes for the browser to come back. Your tokens go into your login keychain, and Orbit restores the session on the next launch and refreshes the access token as needed. Sign Out deletes the stored tokens from your Mac but cannot revoke them at Spotify.

To revoke Orbit's access on Spotify's side as well, remove it at [spotify.com/account/apps](https://www.spotify.com/account/apps/). The README's [Security notes](../README.md#security-notes) describe what the sign-in protects against and what it cannot.

## Scopes

Orbit requests these scopes, taken from `OrbitKit/Sources/SpotifyKit/Auth/AuthorizationRequest.swift`:

| Scope | Used for |
|---|---|
| `user-read-playback-state` | Reading what is playing, on which device, and the device list |
| `user-modify-playback-state` | Play, pause, skip, seek, volume, shuffle, repeat, switching devices and adding to the queue |
| `user-read-currently-playing` | Reading the current track and the queue |
| `playlist-read-private` | Listing your private playlists |
| `playlist-read-collaborative` | Listing collaborative playlists |
| `user-library-read` | Reading Liked Songs and whether the current track is saved |
| `user-library-modify` | Saving the current track to Liked Songs or removing it |

Orbit cannot create, edit or delete playlists, follow anything, or read your email or account details. At launch Orbit checks the scopes recorded with your stored session. If one it needs is missing, for example because a newer version of Orbit asks for more, it signs you out and shows "Your Spotify session has expired." Sign in again to grant the full set.

## What Development Mode means

Spotify Developer apps run in Development Mode unless Spotify grants them extended access. For someone using Orbit, that means:

- **Five-user allowlist.** Only the accounts listed under User Management can use the app. Everyone else gets refused requests. If you want to share Orbit with more people, each group of up to five needs its own developer app and Client ID.
- **The owner needs Premium.** Spotify requires the account that owns the developer app to have Spotify Premium.
- **One shared quota.** Requests from every user of the Client ID, and from every other Development Mode app on the owner's developer account, count against one quota. When it runs out, Spotify answers with HTTP 429 and Orbit shows "This app's Spotify request quota is used up for now." Short-term rate limits show "Spotify is limiting requests right now." In both cases Orbit stops sending Web API requests until the wait Spotify names has passed, and local playback controls keep working.
- **Playlist tracks.** Spotify returns a playlist's tracks only if you own it or collaborate on it. For other playlists Orbit shows the name and artwork and can still play the playlist, but it shows "Spotify doesn't share the tracks of playlists you don't own." instead of a track list.
- **Search page size.** A search returns at most 10 results per type. Orbit asks for 10 songs, 10 albums and 10 playlists.

## How often Orbit talks to Spotify

Playback in the Spotify app on this Mac reaches Orbit directly from the app, without Spotify's servers. To notice playback on your other devices, Orbit checks the Web API on a schedule, which you set under Settings > Spotify > Synchronization:

- **Automatically** (the default). Every few seconds while the panel is open and another device is playing; less often while only the pill shows; never while Orbit is hidden. While Spotify on this Mac is playing and only the pill shows, Orbit does not check at all.
- **Less often.** The same schedule with intervals three times as long, for less battery and quota use.
- **Only while Orbit is open.** No checks while only the pill shows. The open panel still checks.

Your list of playlists is reloaded when you open the panel, if Orbit's copy is more than five minutes old. Refresh Now, next to the setting, reloads your playlists and devices straight away, along with Liked Songs and the tracks of any playlist Orbit has already loaded, for example after you edit a playlist in Spotify.
