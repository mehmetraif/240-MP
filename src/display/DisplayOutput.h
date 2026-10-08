#pragma once
#include <QObject>
#include <QString>
#include <QVariantList>

// Settings → Display Output on the OSD/OS image: where the picture goes, among
// the outputs the board has (util/Board): HDMI, composite (the Pi 4's AV jack,
// the Pi 5's TV pads, a Pi 5's GPIO pins), RGB on the GPIO pins for SCART.
//
// The Pi's firmware reads it only at power-on, from osdos-display.txt on the
// boot partition, a copy of one of the presets beside it
// (os/stage-osdos/03-boot). Choosing one, the app exits with that preset's
// code, and osdos-stop (scripts/install.sh), as root, copies it over, keeping
// the one before, and reboots. On the new output the app asks to keep it
// (Main.qml, DisplayKeep): without an answer, revert() brings the old one back
// the same way.
class DisplayOutput : public QObject {
    Q_OBJECT
    // The setting is offered: the image's presets are there, the app is run by
    // its service, whose stop helper writes them (launcher API 3), and the
    // board has more than one output to choose from.
    Q_PROPERTY(bool available READ available CONSTANT)
    Q_PROPERTY(QString boardModel READ boardModel CONSTANT)
    // [{ id, label }]: the outputs this board has, in the menu's order.
    Q_PROPERTY(QVariantList options READ options CONSTANT)
    // The preset in force, "" when osdos-display.txt is none of them.
    Q_PROPERTY(QString current READ current CONSTANT)
    Q_PROPERTY(QString currentLabel READ currentLabel CONSTANT)
    // A change of output waiting to be kept, and the one it came from.
    Q_PROPERTY(bool confirmPending READ confirmPending NOTIFY changed)
    Q_PROPERTY(QString previousLabel READ previousLabel NOTIFY changed)
    // What became of the last change, when it didn't stay ("" otherwise), and
    // a line more on it.
    Q_PROPERTY(QString notice READ notice NOTIFY changed)
    Q_PROPERTY(QString noticeDetail READ noticeDetail NOTIFY changed)

public:
    explicit DisplayOutput(const QString &dataRoot, QObject *parent = nullptr);

    bool available() const { return m_available; }
    QString boardModel() const;
    QVariantList options() const { return m_options; }
    QString current() const { return m_current; }
    QString currentLabel() const;
    bool confirmPending() const { return m_confirmPending; }
    QString previousLabel() const { return m_previousLabel; }
    QString notice() const { return m_notice; }
    QString noticeDetail() const { return m_noticeDetail; }

    // The output with this id: noted, then the app exits for the stop helper
    // to write it and reboot. False when it can't be chosen.
    Q_INVOKABLE bool apply(const QString &id);
    // The new output stays.
    Q_INVOKABLE void keep();
    // The output before it, back: the app exits as for apply().
    Q_INVOKABLE void revert();
    Q_INVOKABLE void dismissNotice();

signals:
    void changed();

private:
    QString presetPath(const QString &id) const;
    QString statePath() const;
    bool writeState(const QVariantMap &state) const;

    QString m_dataRoot;
    QString m_bootDir;
    bool m_available = false;
    QVariantList m_options;
    QString m_current;
    bool m_confirmPending = false;
    QString m_previousLabel;
    QString m_notice;
    QString m_noticeDetail;
};
