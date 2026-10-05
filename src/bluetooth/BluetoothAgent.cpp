#include "BluetoothAgent.h"
#include "BluetoothManager.h"

#include <QDBusConnection>

BluetoothAgent::BluetoothAgent(QObject *exported, BluetoothManager *manager)
    : QDBusAbstractAdaptor(exported), m_manager(manager) {}

void BluetoothAgent::Release() {}

QString BluetoothAgent::RequestPinCode(const QDBusObjectPath &device) {
    return m_manager->agentRequestPinCode(device.path());
}

void BluetoothAgent::DisplayPinCode(const QDBusObjectPath &device, const QString &pincode) {
    m_manager->agentDisplayPinCode(device.path(), pincode);
}

// A code shown on the device, to type here: there is no keypad for it.
// Registered as DisplayYesNo, BlueZ doesn't ask.
uint BluetoothAgent::RequestPasskey(const QDBusObjectPath &, const QDBusMessage &message) {
    message.setDelayedReply(true);
    QDBusConnection::systemBus().send(message.createErrorReply(
        QStringLiteral("org.bluez.Error.Rejected"), QStringLiteral("No keypad to type a passkey on")));
    return 0;
}

void BluetoothAgent::DisplayPasskey(const QDBusObjectPath &device, uint passkey, ushort entered) {
    m_manager->agentDisplayPasskey(device.path(), passkey, entered);
}

void BluetoothAgent::RequestConfirmation(const QDBusObjectPath &device, uint passkey,
                                         const QDBusMessage &message) {
    message.setDelayedReply(true);
    m_manager->agentRequestConfirmation(device.path(), passkey, message);
}

void BluetoothAgent::RequestAuthorization(const QDBusObjectPath &device, const QDBusMessage &message) {
    message.setDelayedReply(true);
    m_manager->agentRequestAuthorization(device.path(), message);
}

void BluetoothAgent::AuthorizeService(const QDBusObjectPath &device, const QString &,
                                      const QDBusMessage &message) {
    message.setDelayedReply(true);
    m_manager->agentAuthorizeService(device.path(), message);
}

void BluetoothAgent::Cancel() {
    m_manager->agentCancel();
}
