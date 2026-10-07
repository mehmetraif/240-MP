#pragma once
#include <QPointer>
#include <QQuickItem>

class MpvController;

// The picture of an mpv session played inside OSD/OS's own window (the
// Transparent Background setting, see EmbeddedMpv), drawn as an item so that
// the menus can lie over it. It fills its area, mpv having fitted the picture
// to it (bars, Scaling), and tells the controller how many pixels that is:
// the size mpv draws at.
//
//     VideoSurface { anchors.fill: parent; controller: mpvController }
class VideoSurface : public QQuickItem {
    Q_OBJECT
    Q_PROPERTY(QObject *controller READ controller WRITE setController NOTIFY controllerChanged)
public:
    explicit VideoSurface(QQuickItem *parent = nullptr);

    QObject *controller() const;
    void setController(QObject *controller);

signals:
    void controllerChanged();

protected:
    QSGNode *updatePaintNode(QSGNode *old, UpdatePaintNodeData *) override;
    void geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) override;
    void itemChange(ItemChange change, const ItemChangeData &value) override;

private:
    void reportSize();

    QPointer<MpvController> m_controller;
    qint64 m_shownKey = 0;
};
