#include "OsdIconProvider.h"
#include <QColor>
#include <QImageReader>
#include <QUrl>
#include <cmath>

namespace {

// The source rendered at a given size, as straight (not premultiplied) ARGB:
// a vector drawn at that size, a picture of pixels (a skin's icon) scaled, its
// pixels kept square and sharp as it grows.
QImage render(const QString &path, const QSize &size) {
    QImageReader reader(path);
    if (!reader.format().startsWith("svg")) {
        const QImage image = reader.read();
        const bool grows = size.width() >= image.width() && size.height() >= image.height();
        return image.scaled(size, Qt::IgnoreAspectRatio, grows ? Qt::FastTransformation : Qt::SmoothTransformation)
                    .convertToFormat(QImage::Format_ARGB32);
    }
    reader.setScaledSize(size);
    return reader.read().convertToFormat(QImage::Format_ARGB32);
}

} // namespace

QImage OsdIconProvider::requestImage(const QString &id, QSize *size, const QSize &requestedSize) {
    // <rrggbb>/<url>: the url keeps its own slashes.
    const int colorEnd = id.indexOf(QLatin1Char('/'));
    if (colorEnd < 0)
        return {};
    const QColor color(QLatin1Char('#') + id.left(colorEnd));
    const QUrl url(id.mid(colorEnd + 1));
    const QString path = url.isLocalFile() ? url.toLocalFile()
                       : url.scheme() == QLatin1String("qrc") ? QLatin1Char(':') + url.path()
                                                              : url.toString();

    const QSize natural = QImageReader(path).size();
    if (!color.isValid() || natural.isEmpty())
        return {};
    const int height = requestedSize.height() > 0 ? requestedSize.height() : natural.height();

    // Where the drawing is, found on a large rendering so the margin around it
    // is measured to within a fraction of a final pixel.
    const int probeHeight = qMax(height * 8, 64);
    const QImage probe = render(path, QSize(qMax(1, qRound(double(natural.width()) * probeHeight
                                                              / natural.height())), probeHeight));
    int left = probe.width(), right = -1, top = probe.height(), bottom = -1;
    for (int y = 0; y < probe.height(); ++y) {
        const QRgb *line = reinterpret_cast<const QRgb *>(probe.constScanLine(y));
        for (int x = 0; x < probe.width(); ++x) {
            if (qAlpha(line[x]) == 0)
                continue;
            left = qMin(left, x);
            right = qMax(right, x + 1);
            top = qMin(top, y);
            bottom = qMax(bottom, y + 1);
        }
    }
    if (right < 0)
        return {};

    // Drawn again from the original at the scale that makes the drawing itself
    // the height asked for, then cut to it. A width asked for as well
    // stretches it to that width: a screen whose pixels are not square
    // (720×480 on a 4:3 tube) keeps the drawing's shape on the glass.
    const double scale = double(height) / (bottom - top);
    const double scaleX = requestedSize.width() > 0 ? double(requestedSize.width()) / (right - left) : scale;
    const QImage full = render(path, QSize(qMax(1, qRound(probe.width() * scaleX)),
                                           qMax(1, qRound(probe.height() * scale))));
    const int x0 = int(std::floor(left * scaleX));
    const int y0 = int(std::floor(top * scale));
    QImage out = full.copy(x0, y0,
                           qMax(1, int(std::ceil(right * scaleX)) - x0),
                           qMax(1, int(std::ceil(bottom * scale)) - y0));

    // In the colour, with the drawing's own edges.
    const QRgb rgb = color.rgb() & 0x00ffffff;
    for (int y = 0; y < out.height(); ++y) {
        QRgb *line = reinterpret_cast<QRgb *>(out.scanLine(y));
        for (int x = 0; x < out.width(); ++x)
            line[x] = (QRgb(qAlpha(line[x])) << 24) | rgb;
    }
    if (size)
        *size = out.size();
    return out;
}
