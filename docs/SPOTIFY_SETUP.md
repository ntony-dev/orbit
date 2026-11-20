# Connect Orbit to Spotify

Orbit needs a free "Client ID" from Spotify before it can show your playlists and search. You make one yourself in about five minutes. You only do this once.

**You need:** Spotify Premium, and Orbit already open on your Mac.

**Got Orbit from a friend?** Their copy already has a Client ID. Skip to [step 4](#4-sign-in).

## 1. Create your Spotify app

1. Go to the [Spotify Developer Dashboard](https://developer.spotify.com/dashboard) and log in with your Spotify account. If Spotify asks you to accept its developer terms or verify your email, do that first.
2. Click **Create app**.
3. Fill in the form:

   | Field | What to enter |
   |---|---|
   | App name | `Orbit` |
   | App description | `My Orbit` |
   | Redirect URIs | `http://127.0.0.1:8888/callback`, then click **Add** |
   | APIs used | Tick **Web API** |

4. Tick the box to accept Spotify's terms, then click **Save**.

> Copy the redirect URI exactly as shown. Sign-in won't work if it differs by even one character.

## 2. Add your own account

1. On your app's page, click **Settings**, then the **User Management** tab.
2. Enter your name and the email address of your Spotify account, and add it.

## 3. Copy the Client ID into Orbit

1. Still in **Settings**, open the **Basic Information** tab and copy the **Client ID**.
2. In Orbit, open **Settings > Spotify**. To get there, click the Orbit icon in the top menu bar (near the clock) and choose **Settings…**.
3. Paste the ID into the **Client ID** field at the bottom and click **Save**.

## 4. Sign in

1. In **Settings > Spotify**, click **Sign In…**. You can also click **Connect Spotify** in Orbit's Library tab.
2. Your browser opens Spotify's page. Click **Agree**.
3. When the page says **"You're signed in to Orbit."**, close the tab.
4. The first time you press play in Orbit, macOS asks if Orbit may control Spotify. Click **Allow**.

That's it. Settings > Spotify now says **Signed in as** and your name.

Something not working? See [Troubleshooting](TROUBLESHOOTING.md).

## More details

<details>
<summary><b>What Orbit can see and do on your account</b></summary>

<br>

Spotify shows this list on the page where you click Agree.

| Permission | Used for |
|---|---|
| `user-read-playback-state` | Seeing what's playing, on which device, and your device list |
| `user-modify-playback-state` | Play, pause, skip, seek, volume, shuffle, repeat, switching devices, adding to the queue |
| `user-read-currently-playing` | Seeing the current song and the queue |
| `playlist-read-private` | Listing your private playlists |
| `playlist-read-collaborative` | Listing collaborative playlists |
| `user-library-read` | Reading Liked Songs, and whether the current song is liked |
| `user-library-modify` | Liking or unliking the current song |

- **What Orbit can't do:** create, edit or delete playlists, follow anything, or read your email or account details.
- **After an update:** if a newer Orbit needs a permission your sign-in doesn't have, it signs you out and shows "Your Spotify session has expired." Sign in again to approve it.
- **Revoking access:** Sign Out removes your sign-in from this Mac. To cut Orbit off on Spotify's side too, remove it at [spotify.com/account/apps](https://www.spotify.com/account/apps/).

The permissions are listed in `OrbitKit/Sources/SpotifyKit/Auth/AuthorizationRequest.swift`. How sign-in is secured is in [PRIVACY.md](PRIVACY.md#security).

</details>

<details>
<summary><b>Spotify's limits on personal apps</b></summary>

<br>

Your Spotify app runs in what Spotify calls Development Mode. That means:

- **Up to five accounts.** Only accounts listed under User Management can sign in. Anyone else gets "This Spotify account isn't enabled for this Orbit client."
- **Premium required.** The account that owns the app needs Spotify Premium.
- **One shared request budget.** Everyone using your Client ID, plus any other Development Mode apps you own, share one budget. If it runs out, Orbit shows "This app's Spotify request quota is used up for now." A short burst limit shows "Spotify is limiting requests right now." Either way, Orbit waits as long as Spotify asks, and play, pause and skip keep working.
- **Playlist tracks.** Spotify only shares the songs in playlists you own or collaborate on. Other playlists still play, but Orbit shows "Spotify doesn't share the tracks of playlists you don't own." instead of a track list.
- **Search.** At most 10 songs, 10 albums and 10 playlists per search.

</details>

<details>
<summary><b>How often Orbit talks to Spotify</b></summary>

<br>

Playback in the Spotify app on this Mac reaches Orbit straight from the app. To notice playback on your other devices, Orbit checks Spotify's servers on a schedule. Set it in **Settings > Spotify > Synchronization**:

| Setting | What it does |
|---|---|
| **Automatically** (default) | Every few seconds while the panel is open and another device is playing; less often while only the pill shows. No checks while Spotify on this Mac is playing and only the pill shows. |
| **Less often** | The same, with intervals three times as long. Saves battery and request budget. |
| **Only while Orbit is open** | No checks while only the pill shows. |

Orbit never checks while it's hidden.

- **Playlists** reload when you open the panel, if Orbit's copy is more than five minutes old.
- **Refresh Now**, next to the setting, reloads your playlists, devices and Liked Songs straight away, plus any playlist Orbit has already loaded. Use it after editing a playlist in Spotify.

</details>

<details>
<summary><b>Changing or removing your Client ID</b></summary>

<br>

- **Change it:** paste the new ID in Settings > Spotify and click **Save**, then click **Reconnect**. Your current sign-in keeps the old ID until you do.
- **Go back to a friend's built-in ID:** clear the field and click **Save**.
- **Which one is in use:** the line under the field says "Using your Client ID.", "Using the Client ID built into this copy." or "No Client ID configured. Sign-in needs one."
- **Building Orbit yourself:** you can build your Client ID into your copy instead. See [DEVELOPMENT.md](DEVELOPMENT.md#build-and-run).

</details>
