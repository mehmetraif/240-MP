#include "DisplayOutput.h"
#include "../util/Board.h"
#include "../util/LegacyNames.h"

#include <QCoreApplication>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>

namespace {

// The presets, in the menu's order, with the exit code osdos-stop
// (scripts/install.sh, STOP_HELPER) writes each on: keep the two in step.
struct Preset {
    const char *id;     // osdos-display-<id>.txt
    const char *label;
    int exitCode;
};
const Preset kPresets[] = {
    { "hdmi",           "HDMI",                20 },
    { "crt-ntsc",       "Composite NTSC",      21 },
    { "crt-pal",        "Composite PAL",       22 },
    { "crt-gpio-ntsc",  "GPIO Composite NTSC", 23 },
    { "crt-gpio-pal",   "GPIO Composite PAL",  24 },
    { "scart-rgb-ntsc", "SCART RGB NTSC",      25 },
    { "scart-rgb-pal",  "SCART RGB PAL",       26 },
    { "scart-rgb-240p", "SCART RGB 240p",      27 },
    { "scart-rgb-288p", "SCART RGB 288p",      28 },
};
// osdos-stop's for the output before the last one chosen.
constexpr int kRevertExitCode = 29;

const Preset *presetById(const QString &id) {
    for (const Preset &p : kPresets) {
        if (id == QLatin1String(p.id))
            return &p;
    }
    return nullptr;
}

QString labelOf(const QString &id) {
    const Preset *p = presetById(id);
    return p ? QString::fromLatin1(p->label) : QStringLiteral("Custom");
}

// Whether the board has that output.
bool boardHas(const QString &id) {
    const board::Family family = board::family();
    const bool pi3 = family == board::Family::Pi3;
    const bool pi4 = family == board::Family::Pi4;
    const bool pi5 = family == board::Family::Pi5;
    if (id == QLatin1String("hdmi"))
        return pi3 || pi4 || pi5;
    // A Pi 5's composite on GPIO 4-11 (vec-gpio-pi5).
    if (id.startsWith(QLatin1String("crt-gpio-")))
        return pi5;
    // The AV jack (Pi 3, Pi 4), the TV pads (Pi 5); none on a keyboard model.
    if (id.startsWith(QLatin1String("crt-")))
        return (pi3 || pi4 || pi5) && !board::isKeyboard();
    // RGB on the GPIO pins (DPI): 480i and 576i on both, and on the Pi 4,
    // whose interlace is the firmware's, 240p and 288p should it not hold.
    if (id == QLatin1String("scart-rgb-ntsc") || id == QLatin1String("scart-rgb-pal"))
        return pi4 || pi5;
    if (id.startsWith(QLatin1String("scart-rgb-")))
        return pi4;
    return false;
}

QByteArray readFile(const QString &path) {
    QFile f(path);
    return f.open(QIODevice::ReadOnly) ? f.readAll() : QByteArray();
}

} // namespace

DisplayOutput::DisplayOutput(const QString &dataRoot, QObject *parent)
    : QObject(parent),
      m_dataRoot(dataRoot),
      m_bootDir(legacy::env("BOOT_DIR", QStringLiteral("/boot/firmware"))) {
    // Not the OSD/OS image: nothing to offer.
    const QByteArray inForce = readFile(m_bootDir + QStringLiteral("/osdos-display.txt"));
    if (inForce.isEmpty())
        return;
    for (const Preset &p : kPresets) {
        const QString id = QString::fromLatin1(p.id);
        const QByteArray preset = readFile(presetPath(id));
        if (preset.isEmpty())
            continue;
        if (preset == inForce)
            m_current = id;
        if (boardHas(id))
            m_options.append(QVariantMap{ { QStringLiteral("id"), id },
                                          { QStringLiteral("label"), labelOf(id) } });
    }
    m_available = legacy::envIsSet("AUTOSTART") && legacy::envInt("LAUNCHER_API") >= 3
                  && m_options.size() > 1;

    // What became of the last change.
    const QJsonObject state = QJsonDocument::fromJson(readFile(statePath())).object();
    if (state.isEmpty())
        return;
    const QString to = state.value(QStringLiteral("to")).toString();
    const QString reverted = state.value(QStringLiteral("reverted")).toString();
    if (!to.isEmpty() && to == m_current && m_available) {
        // On the new output: it stays only when said so (keep(), revert()).
        m_confirmPending = true;
        m_previousLabel = state.value(QStringLiteral("from")).toString();
        return;
    }
    if (!to.isEmpty() && to != m_current) {
        m_notice = QStringLiteral("Still on %1").arg(currentLabel());
        m_noticeDetail = QStringLiteral("The display output couldn't be switched to %1").arg(labelOf(to));
    } else if (!reverted.isEmpty()) {
        m_notice = QStringLiteral("Back to %1").arg(currentLabel());
        m_noticeDetail = QStringLiteral("%1 was not kept").arg(reverted);
    }
    QFile::remove(statePath());
}

QString DisplayOutput::boardModel() const {
    return board::model();
}

QString DisplayOutput::currentLabel() const {
    return labelOf(m_current);
}

bool DisplayOutput::apply(const QString &id) {
    const Preset *p = presetById(id);
    if (!m_available || !p || id == m_current || !boardHas(id))
        return false;
    if (!writeState({ { QStringLiteral("from"), currentLabel() }, { QStringLiteral("to"), id } }))
        return false;
    qInfo("[DisplayOutput] %s -> %s: exit %d for osdos-stop", qPrintable(m_current), qPrintable(id),
          p->exitCode);
    QCoreApplication::exit(p->exitCode);
    return true;
}

void DisplayOutput::keep() {
    if (!m_confirmPending)
        return;
    QFile::remove(statePath());
    m_confirmPending = false;
    emit changed();
}

void DisplayOutput::revert() {
    if (!m_confirmPending)
        return;
    writeState({ { QStringLiteral("reverted"), currentLabel() } });
    qInfo("[DisplayOutput] %s not kept: exit %d for osdos-stop", qPrintable(m_current), kRevertExitCode);
    QCoreApplication::exit(kRevertExitCode);
}

void DisplayOutput::dismissNotice() {
    if (m_notice.isEmpty())
        return;
    m_notice.clear();
    m_noticeDetail.clear();
    emit changed();
}

QString DisplayOutput::presetPath(const QString &id) const {
    return m_bootDir + QStringLiteral("/osdos-display-") + id + QStringLiteral(".txt");
}

QString DisplayOutput::statePath() const {
    return m_dataRoot + QStringLiteral("/display-output.json");
}

bool DisplayOutput::writeState(const QVariantMap &state) const {
    QSaveFile f(statePath());
    if (!f.open(QIODevice::WriteOnly))
        return false;
    f.write(QJsonDocument(QJsonObject::fromVariantMap(state)).toJson(QJsonDocument::Compact));
    return f.commit();
}
