#pragma once

#include <QDBusAbstractAdaptor>
#include <QDBusMessage>
#include <QDBusObjectPath>

class BluetoothManager;

// org.bluez.Agent1, which BluetoothManager exports on the system bus and
// registers with BlueZ as its default agent: how BlueZ asks this app for what
// pairing a device needs. Registered as "DisplayYesNo", it shows codes and
// takes a yes or a no, which covers a keyboard (a code to type on it), a
// phone (the same code on both) and anything with no buttons to speak of (no
// question at all). Each call is handed to the manager, which shows it.
class BluetoothAgent : public QDBusAbstractAdaptor {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.bluez.Agent1")
public:
    BluetoothAgent(QObject *exported, BluetoothManager *manager);

public slots:
    void Release();
    QString RequestPinCode(const QDBusObjectPath &device);
    void DisplayPinCode(const QDBusObjectPath &device, const QString &pincode);
    uint RequestPasskey(const QDBusObjectPath &device, const QDBusMessage &message);
    void DisplayPasskey(const QDBusObjectPath &device, uint passkey, ushort entered);
    void RequestConfirmation(const QDBusObjectPath &device, uint passkey, const QDBusMessage &message);
    void RequestAuthorization(const QDBusObjectPath &device, const QDBusMessage &message);
    void AuthorizeService(const QDBusObjectPath &device, const QString &uuid, const QDBusMessage &message);
    void Cancel();

private:
    BluetoothManager *m_manager;
};
