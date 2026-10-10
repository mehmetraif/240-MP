#pragma once
#include <QQuickImageProvider>

// An image (a module's logo.svg) drawn in one colour, the way a deck's
// on-screen display draws its symbols:
//
//     image://osdicon/<rrggbb>/<url>
//
// renders what <url> draws, trimmed of the margin around it, from the original
// (a vector is drawn at the requested height, not scaled from a bitmap; a
// picture of pixels, a skin's icon, grows with its pixels sharp), and colours
// it, keeping its smooth edges. Unlike a shader effect it draws on every scene
// graph backend, the software one included.
class OsdIconProvider : public QQuickImageProvider {
public:
    OsdIconProvider() : QQuickImageProvider(QQuickImageProvider::Image) {}

    QImage requestImage(const QString &id, QSize *size, const QSize &requestedSize) override;
};
