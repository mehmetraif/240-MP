#include "VideoSurface.h"
#include "MpvController.h"
#include <QQuickWindow>
#include <QSGSimpleTextureNode>

VideoSurface::VideoSurface(QQuickItem *parent) : QQuickItem(parent) {
    setFlag(ItemHasContents, true);
}

QObject *VideoSurface::controller() const {
    return m_controller;
}

void VideoSurface::setController(QObject *controller) {
    auto *mpv = qobject_cast<MpvController *>(controller);
    if (mpv == m_controller)
        return;
    if (m_controller)
        disconnect(m_controller, nullptr, this, nullptr);
    m_controller = mpv;
    if (m_controller)
        connect(m_controller, &MpvController::videoFrameReady, this, &QQuickItem::update);
    reportSize();
    update();
    emit controllerChanged();
}

QSGNode *VideoSurface::updatePaintNode(QSGNode *old, UpdatePaintNodeData *) {
    // The GUI thread waits while this runs, so the controller can be asked.
    auto *node = static_cast<QSGSimpleTextureNode *>(old);
    const QImage frame = m_controller ? m_controller->videoFrame() : QImage();
    if (frame.isNull() || width() <= 0 || height() <= 0) {
        delete node;
        m_shownKey = 0;
        return nullptr;
    }
    if (!node) {
        node = new QSGSimpleTextureNode;
        node->setOwnsTexture(true);
        node->setFiltering(QSGTexture::Linear);
    }
    if (frame.cacheKey() != m_shownKey || !node->texture()) {
        node->setTexture(window()->createTextureFromImage(frame, QQuickWindow::TextureIsOpaque));
        m_shownKey = frame.cacheKey();
    }
    node->setRect(boundingRect());
    return node;
}

void VideoSurface::geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) {
    QQuickItem::geometryChange(newGeometry, oldGeometry);
    if (newGeometry.size() != oldGeometry.size())
        reportSize();
}

void VideoSurface::itemChange(ItemChange change, const ItemChangeData &value) {
    QQuickItem::itemChange(change, value);
    if (change == ItemSceneChange || change == ItemDevicePixelRatioHasChanged)
        reportSize();
}

void VideoSurface::reportSize() {
    if (!m_controller || !window() || width() <= 0 || height() <= 0)
        return;
    const qreal dpr = window()->effectiveDevicePixelRatio();
    m_controller->setVideoTargetSize(QSize(qRound(width() * dpr), qRound(height() * dpr)));
}
