#pragma once
#include <QString>

// The board OSD/OS runs on, as its device tree names it
// (/proc/device-tree/model, e.g. "Raspberry Pi 4 Model B Rev 1.5"); empty off
// a Raspberry Pi. OSDOS_BOARD_MODEL stands in for it, for tests. Read once.
namespace board {

enum class Family { Other, Pi3, Pi4, Pi5 };

QString model();
// The Raspberry Pi generation: the Pi 400 is a Pi 4, the Pi 500 a Pi 5.
Family family();
// A keyboard model (Pi 400, Pi 500): no composite output of its own.
bool isKeyboard();

} // namespace board
