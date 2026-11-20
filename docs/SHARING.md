# Sharing Orbit with friends

If you have a Spotify Developer app, you can build a copy of Orbit with your Client ID built in, so your friends don't have to create their own app or paste an ID. Development Mode allows five users per app, including you.

## Build a copy

1. In the [Spotify Developer Dashboard](https://developer.spotify.com/dashboard), go to your app's **Settings > User Management** and add each friend's name and Spotify account email.
2. Build the disk image:

   ```
   Scripts/archive.sh --friends
   ```

   This uses `SPOTIFY_CLIENT_ID` from `Config/Local.xcconfig`. To pass it for one build instead: `SPOTIFY_CLIENT_ID=your_client_id Scripts/archive.sh --friends`. The output is `dist/Orbit-<version>-friends.dmg`, always signed ad hoc.
3. Send the file directly (AirDrop, Messages) along with the install steps below.

For updates, build and send a new image.

> **Keep it private.** The image contains your Client ID. Everyone using it shares your app's request quota, and only accounts on your User Management list can sign in. Never attach it to a public release. Plain `Scripts/archive.sh` builds the public image, `dist/Orbit-<version>.dmg`, which has no Client ID.

## Install a copy a friend sent you

You need macOS 26 or later, the Spotify app for Mac, and your friend needs to have added your Spotify account to their list.

1. Open the `.dmg`, drag Orbit onto the Applications folder, then eject the Orbit disk in Finder's sidebar.
2. Open Orbit. When macOS says it couldn't verify Orbit, click **Done** (not Move to Trash). Then go to **System Settings > Privacy & Security**, scroll to Security, click **Open Anyway**, and confirm. You only do this once.
3. Orbit has no Dock icon. Click the pill on your screen, then **Library > Connect Spotify**. Sign in with the account your friend added, click **Agree**, and close the tab once it says you're signed in.
4. The first time you use the play controls, macOS asks whether Orbit may control Spotify. Click **Allow**.
