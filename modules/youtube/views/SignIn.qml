import QtQuick
import Components

// SIGN IN in the module's settings: Google's sign-in, full screen in Chromium,
// in the profile yt-dlp then reads the account from (YouTubeBackend).
WebPlayerLaunch {
    backend: youtubeBackend.browser
    serviceName: "YouTube"
    signInNote: "Use a spare Google account: YouTube can block one used through yt-dlp"
}
