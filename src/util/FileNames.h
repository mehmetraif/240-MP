#pragma once

#include <QChar>
#include <QString>

// A file name every filesystem the app writes to takes: exFAT's rules, which
// are Windows' (no \ / : * ? " < > |, no control characters, no trailing dot
// or space), and no leading dot, which would hide the file from a folder
// scan. Each character that can't stay becomes replacement (a control
// character a space), runs of spaces one space; maxLength caps the name (0:
// no cap). An empty result becomes fallback.
inline QString safeFileName(const QString &name, QChar replacement = QLatin1Char(' '),
                            int maxLength = 0, const QString &fallback = QStringLiteral("file")) {
    static const QString kForbidden = QStringLiteral("\\/:*?\"<>|");
    QString out;
    out.reserve(name.size());
    for (const QChar c : name) {
        if (c.unicode() < 32)
            out += QLatin1Char(' ');
        else if (kForbidden.contains(c))
            out += replacement;
        else
            out += c;
    }
    out = out.simplified();
    while (out.startsWith(QLatin1Char('.')))
        out.remove(0, 1);
    if (maxLength > 0 && out.size() > maxLength)
        out = out.left(maxLength);
    while (out.endsWith(QLatin1Char('.')) || out.endsWith(QLatin1Char(' ')))
        out.chop(1);
    return out.isEmpty() ? fallback : out;
}
