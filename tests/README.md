# Regression tests

Two test programs, built apart from the app. CI runs them on Linux x64 and arm64 for every pull request that touches `src/`, `tests/` or the build ([regression-tests.yml](../.github/workflows/regression-tests.yml)). They need CMake, a C++17 compiler and Qt 6's development packages (Core, Concurrent, Gui, Network, Qml, Quick and Test), and libdrm's on Linux. Neither needs mpv or a display.

```sh
cmake -S tests -B build-tests
cmake --build build-tests --parallel
ctest --test-dir build-tests --output-on-failure
```

- **storage_search** (`storage_search_test.cpp`):
  - Local Files' search keeps the first 200 matches by name.
  - A search replaced by the next is never reported.
  - The backend can go away while a search runs.
  - Settings and resume points survive a restart.
  - A save that can't be made (the data folder read-only) leaves the old file as it was. Run as root, that test skips itself: root writes to a read-only folder anyway.
  - State files keep their permissions, and a token is owner-only from its first write.
- **playback_retire** (`playback_retire_test.cpp`, Linux only). A video is asked for while another plays in an mpv process, against a stand-in for mpv: a shell script first on `PATH` that writes down when it starts, is told to quit and exits.
  - The app goes on while the old player quits, and the new one starts only once it has gone.
  - Of several videos asked for in a row, only the last plays.
  - Stopped while it waits, nothing starts and its player is told once.
  - Stopped and followed at once by another, that one plays and the stop isn't reported.
  - A player that ignores being told to quit is killed a second on.

## On a Raspberry Pi

What the tests can't reach, above all the screen changing hands (DRM and the VT), wants checking on the device:

- Search a large USB or NAS library while moving about the menus. The menus keep up, and no more than 200 results are kept.
- Start A, then B, then C quickly (NFC cards, say). Only C plays, once A has gone, and the menus never freeze meanwhile.
- Press back while the next video waits for the old one. Nothing starts, and the menus come back about 200 ms after the old player has gone. Repeat with Transparent Background on.
- Tap a card just as a video ends. The new one plays, and the menus don't take the screen from it.
- Cut the power while settings are being changed and while a video's resume point is saved. Every file comes back as the old JSON or the new, never cut short.
- Fill the data folder, or make it read-only. A save then logs why and leaves the old file.
