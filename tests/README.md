# Search, playback and storage regressions

Requires CMake, a C++17 compiler and Qt 6 development packages (Core,
Concurrent, Network, Qml and Test). These tests do not need mpv or a display.

```sh
cmake -S tests -B build-tests
cmake --build build-tests --parallel
ctest --test-dir build-tests --output-on-failure
```

The tests cover sorted/capped results, superseded searches, destruction with
a search pending, and settings/history reloads.

Additional checks on a Raspberry Pi:

- Search a large USB/NAS library while navigating the UI. Check memory usage
  and input latency; search result storage should remain capped at 200 entries.
- Start A, then B, then C rapidly. Only C should start after A exits. Repeat
  with a player that ignores SIGTERM: the one-second timer must kill A without
  freezing the UI. No two players should hold the display simultaneously.
- Press Stop while a replacement is waiting. The pending video must not start;
  the menus and display must return. Repeat switching to embedded playback.
- Interrupt the application during repeated settings/history saves. Each file
  should remain valid old or new JSON. Also test a full filesystem and an
  unwritable data directory: failed saves should log an error and preserve the
  previous file. Atomic replacement does not guarantee durability against all
  storage hardware or filesystem failures.

The Windows review environment lacked Qt development tools and a C++ compiler;
the C++ tests and hardware checks were not run there.
