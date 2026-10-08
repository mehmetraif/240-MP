#include "Board.h"
#include "LegacyNames.h"

#include <QFile>

namespace board {

QString model() {
    static const QString cached = [] {
        QString m = legacy::env("BOARD_MODEL");
        if (m.isEmpty()) {
            // NUL-terminated, as device tree strings are.
            QFile f(QStringLiteral("/proc/device-tree/model"));
            if (f.open(QIODevice::ReadOnly))
                m = QString::fromLatin1(f.readAll()).remove(QChar('\0')).trimmed();
        }
        return m;
    }();
    return cached;
}

Family family() {
    const QString m = model();
    if (m.startsWith(QLatin1String("Raspberry Pi 5")))
        return Family::Pi5;
    if (m.startsWith(QLatin1String("Raspberry Pi 4")))
        return Family::Pi4;
    if (m.startsWith(QLatin1String("Raspberry Pi 3")))
        return Family::Pi3;
    return Family::Other;
}

bool isKeyboard() {
    const QString m = model();
    return m.startsWith(QLatin1String("Raspberry Pi 400"))
        || m.startsWith(QLatin1String("Raspberry Pi 500"));
}

} // namespace board
