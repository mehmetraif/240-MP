#include "OsdSkinProvider.h"
#include <QColor>
#include <QImageReader>
#include <QUrl>

QImage OsdSkinProvider::requestImage(const QString &id, QSize *size, const QSize &requestedSize) {
    Q_UNUSED(requestedSize)  // drawn at its own size: QML scales it, on art pixels
    // <rrggbb>/<rrggbb>/<url>: the url keeps its own slashes.
    const int inkEnd = id.indexOf(QLatin1Char('/'));
    const int paperEnd = inkEnd < 0 ? -1 : id.indexOf(QLatin1Char('/'), inkEnd + 1);
    if (paperEnd < 0)
        return {};
    const QColor ink(QLatin1Char('#') + id.left(inkEnd));
    const QColor paper(QLatin1Char('#') + id.mid(inkEnd + 1, paperEnd - inkEnd - 1));
    // A theme's own file, nothing else.
    const QUrl url(id.mid(paperEnd + 1));
    if (!ink.isValid() || !paper.isValid() || !url.isLocalFile())
        return {};

    QImage out = QImageReader(url.toLocalFile()).read().convertToFormat(QImage::Format_ARGB32);
    if (out.isNull())
        return {};
    const QRgb inkRgb = ink.rgb() | 0xff000000;
    const QRgb paperRgb = paper.rgb() | 0xff000000;
    for (int y = 0; y < out.height(); ++y) {
        QRgb *line = reinterpret_cast<QRgb *>(out.scanLine(y));
        for (int x = 0; x < out.width(); ++x) {
            const QRgb p = line[x];
            if (qAlpha(p) < 128)
                line[x] = 0;
            else
                line[x] = qGray(p) >= 128 ? inkRgb : paperRgb;
        }
    }
    if (size)
        *size = out.size();
    return out;
}
