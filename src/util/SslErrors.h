#pragma once

#include <QList>
#include <QSet>
#include <QSslError>

// The TLS errors a media server on the LAN typically comes with: a
// self-signed or privately issued certificate, or one made out to another
// name. The backends allow these for their own server's host and no other.
inline QList<QSslError> expectedLanSslErrors(const QList<QSslError> &errors) {
    static const QSet<QSslError::SslError> kExpected = {
        QSslError::SelfSignedCertificate,
        QSslError::HostNameMismatch,
        QSslError::UnableToGetLocalIssuerCertificate,
        QSslError::UnableToVerifyFirstCertificate,
    };
    QList<QSslError> allowed;
    for (const QSslError &e : errors) {
        if (kExpected.contains(e.error()))
            allowed.append(e);
    }
    return allowed;
}
