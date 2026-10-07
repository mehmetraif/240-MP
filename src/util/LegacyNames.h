#pragma once
#include <QString>

// OSD/OS was 240-MP. What a system set up before the name changed still calls
// by the old name is read here, so it goes on working:
//   - its environment: OSD/OS reads OSDOS_<NAME>, and MP240_<NAME> when that
//     is not set (a launcher, service or image from before);
//   - its data: the 240-MP data folder beside OSD/OS's is moved to it, and
//     module ids in its JSON files (com.240mp.x) are renamed (com.osdos.x).
namespace legacy {

// An environment variable by its OSD/OS name, else by its 240-MP name.
QString env(const char *name, const QString &fallback = QString());
bool envIsSet(const char *name);
int envInt(const char *name);

// The 240-MP data folder beside dataRoot (~/.local/share/240-MP beside
// ~/.local/share/OSD-OS), moved to dataRoot when dataRoot is not there yet or
// is empty. Returns the folder to use: the old one, should the move fail.
QString migrateDataFolder(const QString &dataRoot);

// The module ids in dataRoot's JSON files and its NFC tags, renamed where they
// still have their 240-MP prefix. Files without one are not touched.
void migrateModuleIds(const QString &dataRoot);

} // namespace legacy
