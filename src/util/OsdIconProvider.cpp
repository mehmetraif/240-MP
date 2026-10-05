#include "OsdIconProvider.h"
#include <QColor>
#include <QImageReader>
#include <QUrl>

QImage OsdIconProvider::requestImage(const QString &id, QSize *size, const QSize &requestedSize) {
    // <rrggbb>/<px>/<url>: the url keeps its own slashes.
    const int colorEnd = id.indexOf(QLatin1Char('/'));
    const int pxEnd = colorEnd < 0 ? -1 : id.indexOf(QLatin1Char('/'), colorEnd + 1);
    if (pxEnd < 0)
        return {};
    const QColor color(QLatin1Char('#') + id.left(colorEnd));
    const int px = qMax(1, id.mid(colorEnd + 1, pxEnd - colorEnd - 1).toInt());
    const QUrl url(id.mid(pxEnd + 1));
    const QString path = url.isLocalFile() ? url.toLocalFile()
                       : url.scheme() == QLatin1String("qrc") ? QLatin1Char(':') + url.path()
                                                              : url.toString();

    const QSize natural = QImageReader(path).size();
    if (!color.isValid() || natural.isEmpty())
        return {};
    const int height = requestedSize.height() > 0 ? requestedSize.height() : natural.height();
    const int artHeight = qMax(1, height / px);

    // Rendered large and trimmed to what is drawn, so the shape itself is the
    // height asked for, whatever margin its file leaves around it.
    const int bigHeight = artHeight * 8;
    QImageReader reader(path);
    reader.setScaledSize(QSize(qMax(1, qRound(double(natural.width()) * bigHeight / natural.height())),
                               bigHeight));
    const QImage big = reader.read().convertToFormat(QImage::Format_ARGB32);
    int left = big.width(), right = -1, top = big.height(), bottom = -1;
    for (int y = 0; y < big.height(); ++y) {
        const QRgb *line = reinterpret_cast<const QRgb *>(big.constScanLine(y));
        for (int x = 0; x < big.width(); ++x) {
            if (qAlpha(line[x]) < 128)
                continue;
            left = qMin(left, x);
            right = qMax(right, x);
            top = qMin(top, y);
            bottom = qMax(bottom, y);
        }
    }
    if (right < 0)
        return {};
    const QImage shape = big.copy(left, top, right - left + 1, bottom - top + 1);
    const int artWidth = qMax(1, qRound(double(shape.width()) * artHeight / shape.height()));
    QImage art = shape.scaled(artWidth, artHeight, Qt::IgnoreAspectRatio, Qt::SmoothTransformation)
                     .convertToFormat(QImage::Format_ARGB32);

    // Two colours only: an art pixel is the colour or it isn't there.
    const QRgb on = color.rgb();
    for (int y = 0; y < art.height(); ++y) {
        QRgb *line = reinterpret_cast<QRgb *>(art.scanLine(y));
        for (int x = 0; x < art.width(); ++x)
            line[x] = qAlpha(line[x]) >= 128 ? on : 0;
    }
    const QImage out = art.scaled(art.width() * px, art.height() * px,
                                  Qt::IgnoreAspectRatio, Qt::FastTransformation);
    if (size)
        *size = out.size();
    return out;
}
