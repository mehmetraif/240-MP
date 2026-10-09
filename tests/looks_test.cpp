#include "AppCore.h"
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTemporaryDir>
#include <QUrl>
#include <QtTest>

// Themes and skins (AppCore::themes(), theme(), skins(), skin()): read from
// the app's folder (assets) and the data folder's, the data folder's first.
class LooksTest : public QObject {
    Q_OBJECT

    QTemporaryDir m_app;
    QTemporaryDir m_data;

    // A folder of a look with its JSON, under root ("<app>/assets" or the
    // data folder): kind "theme" or "skin".
    static QString writeLook(const QString &root, const QString &kind, const QString &id, const QByteArray &json) {
        const QString dir = root + "/" + kind + "s/" + id;
        if (!QDir().mkpath(dir))
            return {};
        QFile f(dir + "/" + kind + ".json");
        if (!f.open(QIODevice::WriteOnly) || f.write(json) != json.size())
            return {};
        return dir;
    }
    // JSON written with ' for ": moc can't read raw string literals.
    static QByteArray json(const char *text) { return QByteArray(text).replace('\'', '"'); }
    static bool writeFile(const QString &path, const QByteArray &data) {
        QFile f(path);
        return f.open(QIODevice::WriteOnly) && f.write(data) == data.size();
    }
    // A picture a theme can use: a 1×1 PNG.
    static QByteArray png() {
        return QByteArray::fromBase64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg==");
    }
    static QString url(const QString &path) { return QUrl::fromLocalFile(QFileInfo(path).canonicalFilePath()).toString(); }

private slots:
    void initTestCase() {
        QVERIFY(m_app.isValid());
        QVERIFY(m_data.isValid());
        const QString assets = m_app.path() + "/assets";
        // The app's own: a theme, and skins.
        const QString dos = writeLook(assets, "theme", "dos", json("{ 'name': 'DOS', 'window': { 'image': 'window.png', 'border': 4 } }"));
        QVERIFY(!dos.isEmpty());
        QVERIFY(writeFile(dos + "/window.png", png()));
        QVERIFY(!writeLook(assets, "skin", "trinitron", json("{ 'name': 'Trinitron', 'colors': 'Video 1', 'theme': 'dos', 'effect': 'CRT' }")).isEmpty());
        QVERIFY(!writeLook(assets, "skin", "plain", json("{ 'name': 'Plain', 'colors': null, 'effect': 'Off' }")).isEmpty());
        QVERIFY(!writeLook(assets, "skin", "kept", json("{ 'name': 'Kept' }")).isEmpty());

        // The data folder's: one in place of the app's, one not JSON (the
        // app's of its name in its place), one of its own in every way, one
        // wrong in every way.
        QVERIFY(!writeLook(m_data.path(), "skin", "trinitron", json("{ 'name': 'My Trinitron', 'colors': 'Amber' }")).isEmpty());
        QVERIFY(!writeLook(m_data.path(), "skin", "kept", "{ nope").isEmpty());
        const QString mine = writeLook(m_data.path(), "skin", "mine", json("{ "
            "'name': 'Mine', "
            "'colors': { 'primary': '#FFD0A0', 'surface': '#402010', 'accent': '#123456' }, "
            "'theme': { 'window': { 'image': 'frame.png', 'border': [1, 2, 3, 4], 'tile': 'repeat' }, "
                       "'titleBar': '../escape.png', "
                       "'hintBar': 'link.png', "
                       "'selection': { 'image': 'frame.png', 'border': 'wide' } }, "
            "'effect': { 'scanlines': 0.4, 'glow': 7, 'vignette': -1, 'noise': 'lots', "
                        "'animate': true, 'shader': 'crt.frag.qsb' } "
        "}"));
        QVERIFY(!mine.isEmpty());
        QVERIFY(writeFile(mine + "/frame.png", png()));
        QVERIFY(writeFile(mine + "/crt.frag.qsb", "not compiled, but a .qsb in its folder"));
        QVERIFY(writeFile(m_data.path() + "/skins/escape.png", png()));
        QVERIFY(QFile::link(dos + "/window.png", mine + "/link.png"));
        QVERIFY(!writeLook(m_data.path(), "skin", "wrong", json("{ "
            "'colors': { 'primary': 'white', 'surface': '#000' }, "
            "'theme': 42, "
            "'effect': { 'shader': '../mine/crt.frag.qsb' } "
        "}")).isEmpty());
    }

    void themesAsBefore() {
        AppCore core(m_app.path(), m_data.path());
        const QVariantList themes = core.themes();
        QCOMPARE(themes.size(), 1);
        QCOMPARE(themes[0].toMap().value("name").toString(), QString("DOS"));
        const QVariantMap theme = core.theme("dos");
        QCOMPARE(theme.value("name").toString(), QString("DOS"));
        const QVariantMap window = theme.value("window").toMap();
        QCOMPARE(window.value("source").toString(), url(m_app.path() + "/assets/themes/dos/window.png"));
        QCOMPARE(window.value("border").toList(), QVariantList({ 4, 4, 4, 4 }));
        QVERIFY(core.theme("gone").isEmpty());
    }

    // By name, each once, the data folder's in place of the app's; one not
    // JSON left out for the app's of its name. sets: what each sets.
    void skinsListed() {
        AppCore core(m_app.path(), m_data.path());
        QMap<QString, QVariantMap> byId;
        QStringList names;
        for (const QVariant &v : core.skins()) {
            byId.insert(v.toMap().value("id").toString(), v.toMap());
            names.append(v.toMap().value("name").toString());
        }
        QCOMPARE(names, QStringList({ "Kept", "Mine", "My Trinitron", "Plain", "wrong" }));
        QCOMPARE(byId.value("trinitron").value("sets").toStringList(), QStringList({ "colors" }));
        QCOMPARE(byId.value("mine").value("sets").toStringList(), QStringList({ "colors", "theme", "effect" }));
        QCOMPARE(byId.value("plain").value("sets").toStringList(), QStringList({ "effect" }));
        QCOMPARE(byId.value("kept").value("sets").toStringList(), QStringList());
    }

    // Names of a scheme, a theme and a preset: the theme read, the others for
    // Main.qml to look up.
    void skinOfNames() {
        // Without the data folder's in its place.
        AppCore core(m_app.path(), m_app.path() + "/nothing");
        const QVariantMap skin = core.skin("trinitron");
        QCOMPARE(skin.value("name").toString(), QString("Trinitron"));
        QCOMPARE(skin.value("colors").toString(), QString("Video 1"));
        QCOMPARE(skin.value("effect").toString(), QString("CRT"));
        QCOMPARE(skin.value("theme").toMap().value("id").toString(), QString("dos"));
        QVERIFY(skin.value("theme").toMap().contains("window"));
    }

    // Its own colours, theme and effect, from its folder only.
    void skinOfItsOwn() {
        AppCore core(m_app.path(), m_data.path());
        const QVariantMap skin = core.skin("mine");
        const QString dir = m_data.path() + "/skins/mine";
        QCOMPARE(skin.value("colors").toMap(), QVariantMap({ { "primary", "#FFD0A0" }, { "surface", "#402010" } }));

        const QVariantMap theme = skin.value("theme").toMap();
        const QVariantMap window = theme.value("window").toMap();
        QCOMPARE(window.value("source").toString(), url(dir + "/frame.png"));
        QCOMPARE(window.value("border").toList(), QVariantList({ 1, 2, 3, 4 }));
        QCOMPARE(window.value("tile").toString(), QString("repeat"));
        // A border that isn't one: stretched whole.
        QCOMPARE(theme.value("selection").toMap().value("border").toList(), QVariantList({ 0, 0, 0, 0 }));
        // Out of its folder, by a path or a link: refused.
        QVERIFY(!theme.contains("titleBar"));
        QVERIFY(!theme.contains("hintBar"));

        const QVariantMap effect = skin.value("effect").toMap();
        QCOMPARE(effect.value("scanlines").toDouble(), 0.4);
        QCOMPARE(effect.value("glow").toDouble(), 1.0);
        QCOMPARE(effect.value("vignette").toDouble(), 0.0);
        QVERIFY(!effect.contains("noise"));
        QCOMPARE(effect.value("animate").toBool(), true);
        QCOMPARE(effect.value("shader").toString(), url(dir + "/crt.frag.qsb"));
    }

    // What can't be used is there, empty: Video 1's colours, OSD/OS's own
    // window, no effect. Null is as left out.
    void skinWrong() {
        AppCore core(m_app.path(), m_data.path());
        const QVariantMap wrong = core.skin("wrong");
        QCOMPARE(wrong.value("name").toString(), QString("wrong"));
        QVERIFY(wrong.contains("colors"));
        QVERIFY(wrong.value("colors").toMap().isEmpty());
        QVERIFY(wrong.contains("theme"));
        QVERIFY(wrong.value("theme").toMap().isEmpty());
        QVERIFY(wrong.contains("effect"));
        QVERIFY(wrong.value("effect").toMap().isEmpty());

        const QVariantMap plain = core.skin("plain");
        QVERIFY(!plain.contains("colors"));
        QVERIFY(!plain.contains("theme"));
        QCOMPARE(plain.value("effect").toString(), QString("Off"));
    }

    // An id is a folder's name, nothing else.
    void skinIds() {
        AppCore core(m_app.path(), m_data.path());
        for (const QString &id : { QString(), QString("."), QString(".."), QString("../skins/mine"),
                                   QString("mine/"), QString("gone") })
            QVERIFY2(core.skin(id).isEmpty(), qPrintable(id));
        QCOMPARE(core.skin("kept").value("name").toString(), QString("Kept"));
    }
};

QTEST_GUILESS_MAIN(LooksTest)
#include "looks_test.moc"
