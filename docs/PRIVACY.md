# Privacy, permissions and security

## The short version

**Orbit doesn't collect or send any personal data. It has no servers to send it to.** It talks only to Spotify, straight from your Mac. Nothing about you is ever sent to Orbit's developer or anyone else.

**What Orbit can access** in your Spotify account, once you approve it on Spotify's page:

- **Playback:** what's playing, your queue and your devices, so it can show and control them.
- **Your library:** your playlists and Liked Songs, to list them, and liking a song when you click the heart.
- **Search:** what you type in the search field, sent to Spotify to find music.

It can't create, edit or delete playlists, follow anything, or read your email. The exact permissions are listed in [Connect Orbit to Spotify](SPOTIFY_SETUP.md#more-details).

| Your… | Who can see it through Orbit |
|---|---|
| What you listen to | Only you and Spotify. Never the developer. |
| Spotify password | Only Spotify. You type it on Spotify's own page in your browser, and Orbit never sees it. |
| Email address | Nobody. Orbit doesn't ask Spotify for it. |
| Account details, such as country, plan or birthday | Nobody. Orbit doesn't ask Spotify for them. It reads only your public profile (name and picture), to show who's signed in. |
| Playlists, Liked Songs and searches | Only you and Spotify. They go straight between your Mac and Spotify. |
| Your sign-in | Only your Mac. It's kept in your keychain, never sent anywhere but Spotify. |

**What Orbit doesn't have:**

- **No analytics or tracking.** Nothing counts how you use Orbit.
- **No crash reports or update checks.** Orbit never contacts the developer.
- **No ads and no accounts.** There's nothing to sign up for except Spotify itself.
- **No listening history.** Orbit doesn't keep or log what you play.

**Using a copy a friend built?** To let you sign in, your friend added your name and email to their Spotify app, so they know the email you gave them. They can't see what you play or anything else in your account: that would need your sign-in, which stays on your Mac.

Orbit is open source, so you can check all this yourself. The code that talks to Spotify is in `OrbitKit/Sources/SpotifyKit`.

## Permissions

- **Automation for Spotify:** sends playback commands to the Spotify app and reads what's playing. macOS asks the first time you use a playback control while Spotify is running, or when you click Allow in Orbit. If you deny it, Orbit sends commands through the Web API instead, if you're signed in.
- **Keychain:** stores your Spotify tokens. macOS may ask again after Orbit is updated or rebuilt.
- **Login Items:** only if you turn on Launch at login. Approve it in System Settings > General > Login Items if macOS asks.

Orbit doesn't need Accessibility, Input Monitoring, Screen Recording, Full Disk Access, location, contacts or the microphone. Global shortcuts use system hot keys, and full-screen detection only reads window positions, so neither needs a permission. Orbit is not sandboxed.

## Your data

Orbit has no server, no accounts, no analytics, no crash reporting and no update checks.

### Sent to Spotify, and nowhere else

- **`accounts.spotify.com`:** the sign-in page (in your browser), the authorization code exchange, and token refreshes. Sign-in uses Authorization Code with PKCE, with no client secret.
- **`api.spotify.com`:** your profile, playlists, playlist tracks, Liked Songs, the search terms you type, playback state, devices and the queue, plus the commands you send.
- **Spotify's image servers:** artwork.

Commands to the Spotify app on your Mac go over local Apple events and stay on your Mac.

### Stored on your Mac

| What | Where |
|---|---|
| Spotify tokens | Login keychain, as "Orbit Spotify session". Deleted when you sign out, never written to logs. |
| Settings, including your Client ID | Orbit's preferences (`io.github.ntony46.orbit`) |
| Pinned and recent playlists | `~/Library/Application Support/Orbit/Library.json` |
| Artwork cache, up to 64 MB | Orbit's Caches folder |

To revoke Orbit's access on Spotify's side too, remove it at [spotify.com/account/apps](https://www.spotify.com/account/apps/).

## Security

### How sign-in works

Orbit uses Authorization Code with PKCE, the OAuth flow for apps that can't keep a client secret.

- **PKCE:** S256, with a fresh random verifier for each sign-in, kept only in memory.
- **State check:** a random `state` value for each sign-in. A callback with a missing or wrong `state` gets an error page, and the listener keeps waiting for the real one.
- **Callback listener:** bound to `127.0.0.1` port 8888 only, running only while a sign-in is in progress. It shuts down after the callback arrives or after five minutes.
- **No client secret,** so there's none to leak.
- **Tokens** are kept only in the login keychain and in memory.
- **No redirects:** token and Web API requests refuse HTTP redirects, so a token is never sent to another address.

### Risks Orbit can't remove

These come with any app that signs in through a browser and a local listener.

- **Client IDs are public.** A program running as you could start its own sign-in with Orbit's Client ID and its own listener on port 8888. If you approved Orbit before, Spotify may skip the consent screen and send that program a code.
- **Browser history** keeps the authorization code from the callback address. It's useless without the PKCE verifier, which only the Orbit that started the sign-in holds in memory.
- **Signing out** deletes tokens on your Mac but can't revoke them at Spotify. To fully cut off access, remove Orbit at [spotify.com/account/apps](https://www.spotify.com/account/apps/).
- **Malware running as you** can read Orbit's keychain item if you approve its access request, and can take port 8888 before Orbit does. In that case Orbit reports that the port is in use and doesn't open the browser, so no code is sent to that program.
