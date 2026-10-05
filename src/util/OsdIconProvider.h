#pragma once
#include <QQuickImageProvider>

// An image (a module's logo.svg) drawn the way a deck's on-screen display
// would draw it: in one colour, on the 240-line grid of art pixels.
//
//     image://osdicon/<rrggbb>/<px>/<url>
//
// renders what <url> draws, trimmed of the margin around it, at the requested
// height in art pixels of <px> screen pixels, keeps each art pixel at least
// half covered, in the colour, and scales the result up by <px> without
// smoothing. Unlike a shader effect it draws on every scene graph backend, the
// software one included.
class OsdIconProvider : public QQuickImageProvider {
public:
    OsdIconProvider() : QQuickImageProvider(QQuickImageProvider::Image) {}

    QImage requestImage(const QString &id, QSize *size, const QSize &requestedSize) override;
};
