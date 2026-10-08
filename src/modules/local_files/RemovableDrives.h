#pragma once
#include <QList>
#include <QObject>
#include <QStringList>

class QFileSystemWatcher;
class QSocketNotifier;
class QTimer;

// The drives plugged in to be taken out again (USB sticks and disks, a card in
// a reader), where the system mounts them as they come: the OSD/OS image under
// /media/usb (read-only, see os/stage-osdos/07-usb), udisks under
// /media/<user> or /run/media/<user>, macOS under /Volumes. Not one the
// system mounts from /etc/fstab (the image's own OSD-OS partition), nor one
// holding the media folder or held in it: Local Files shows those already.
//
// Read from the mount table, and again whenever it changes: on Linux
// /proc/self/mountinfo (OSDOS_MOUNTINFO names another file, for tests), which
// the kernel flags at every mount and unmount; on macOS as /Volumes changes.
class RemovableDrives : public QObject {
    Q_OBJECT
public:
    struct Drive {
        QString name;   // its mount point's name, which is its label
        QString path;   // its mount point
        bool operator==(const Drive &other) const { return name == other.name && path == other.path; }
    };

    explicit RemovableDrives(QObject *parent = nullptr);
    ~RemovableDrives() override;

    QList<Drive> drives() const { return m_drives; }
    // `path` is one of them, or in one.
    bool holds(const QString &path) const;
    // The media folder, which none of them is, holds or is held in.
    void setMediaRoot(const QString &path);

signals:
    // They changed; `gone` are the mount points of those taken out.
    void changed(const QStringList &gone);

private:
    void rescan();
    QList<Drive> scan() const;

    QList<Drive> m_drives;
    QString m_mediaRoot;
    int m_fd = -1;
    QSocketNotifier *m_notifier = nullptr;
    QFileSystemWatcher *m_watcher = nullptr;
    QTimer *m_settle = nullptr;
};
