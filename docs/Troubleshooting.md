# Vibrdrome Troubleshooting

## "Can't connect to server"

- **Check the URL format.** Include the scheme (e.g., `https://your-server.example.com`). Do not add a trailing slash or path.
- **Verify credentials.** Double-check your username and password in Settings.
- **Test server accessibility.** Open the server URL in a web browser on the same network. If it does not load there, the issue is with your server or network, not Vibrdrome.
- **Use Test Connection.** In Settings, tap **Test Connection** after entering your details. The error message will indicate whether the problem is network, authentication, or server-side.
- **Check your firewall/VPN.** If you are connecting remotely, ensure your server is exposed to the internet or that your VPN is active.

## "Music won't play"

- **Check server compatibility.** Vibrdrome requires a Subsonic-compatible server (Navidrome, Airsonic, etc.) that supports streaming.
- **Check bitrate settings.** If you set a very low bitrate limit under Settings > Playback Quality, some servers may fail to transcode. Try raising or removing the limit.
- **Check your network.** Playback requires an active connection unless the track is downloaded. Switch between Wi-Fi and cellular to isolate the issue.
- **Try a different track.** If only specific files fail, the issue may be with those files on the server (unsupported codec, corrupt file).

## "Downloads not working"

- **Check storage space.** Open your device's storage settings and ensure there is enough free space.
- **Verify server allows downloads.** Some Subsonic server configurations restrict download access per user. Check your Navidrome user permissions.
- **Check network stability.** Downloads require a stable connection. They will resume if interrupted, but persistent network issues will cause failures.

## "CarPlay not showing Vibrdrome"

- See the [CarPlay Guide](CarPlay-Guide.md) for detailed CarPlay troubleshooting.
- The app requires a CarPlay Audio entitlement in its provisioning profile. If you are building from source, ensure the entitlement is present.
- Restart your iPhone and reconnect to CarPlay.

## "Battery drain"

- **Lower streaming quality.** High bitrate streaming uses more network radio time and CPU for decoding. Reduce the bitrate limit in Settings.
- **Disable the visualizer.** The audio visualizer uses GPU resources. Turn it off when battery life is a concern.
- **Download music.** Playing downloaded tracks avoids network usage entirely, which significantly reduces battery consumption.

## "Lyrics not showing"

- **Server requirement.** Lyrics require an OpenSubsonic-compatible server. Navidrome version 0.49 or later supports the lyrics API.
- **Not all songs have lyrics.** Lyrics are fetched from the server. If the server does not have lyrics for a track (embedded or from an external provider), none will display.
- **Check server version.** Open your Navidrome web UI and verify the version under Settings.

## "App crashes"

- **Clear the cache.** Go to Settings > Clear Cache. This removes cached images and temporary audio data.
- **Update the app.** Check for a newer version of Vibrdrome.
- **Restart your device.** A restart can resolve low-memory conditions.
- **Check for large libraries.** Extremely large libraries (50,000+ tracks) may cause memory pressure on older devices. If this is an issue, consider browsing by genre or using search instead of loading the full library.

## Resetting the App

If nothing else works:

1. Go to Settings in Vibrdrome.
2. Remove all servers.
3. Clear the cache.
4. Close and relaunch the app.
5. Re-add your server.

This resets the app to a clean state without needing to reinstall.
