#pragma once
#include <QObject>
#include <QStringList>
#include <QVariant>
#include <QVariantList>
#include <QVariantMap>
#include <memory>

class AppCore;
class QDirIterator;

class LocalFilesBackend : public QObject {
    Q_OBJECT
public:
    explicit LocalFilesBackend(const QString &appRoot, const QString &dataRoot, AppCore *appCore,
                               QObject *parent = nullptr);
    ~LocalFilesBackend() override;

    Q_INVOKABLE QVariantList getItems(const QString &path);
    // The tree's entries for a folder, as the module's browser shows them:
    // the media folder led by RECENTLY WATCHED, FAVORITES and SEARCH (the
    // tree's own folders, whose paths aren't file paths), those two lists'
    // files that are still there, a search's results (undefined while it
    // runs, searchReady following), and any other folder's files and
    // folders. The Playlists module browses with it too.
    Q_INVOKABLE QVariant     entries(const QString &path);
    Q_INVOKABLE bool         isImage(const QString &path) const;
    Q_INVOKABLE bool         isPlaylist(const QString &path) const;
    Q_INVOKABLE bool         playlistContainsImages(const QString &path) const;
    Q_INVOKABLE QString      mediaRoot() const;
    Q_INVOKABLE void         setMediaRoot(const QString &path);
    // The files and folders under the media folder whose names hold every one
    // of the words, case aside (the first 200 by name), for the tree's folder
    // `path`: what the last search for it found, or null while it runs,
    // searchReady(path) following once it is done. The folder is walked a slice at a time, so a
    // big library never holds the screen still; a search for another path
    // replaces one still running, and `fresh` starts this one over.
    Q_INVOKABLE QVariant     search(const QString &path, const QString &words, bool fresh = false);
    // The entries whose files are still there (a list kept by AppCore can
    // name a file since deleted, or on a drive taken out).
    Q_INVOKABLE QVariantList existing(const QVariantList &entries) const;

    Q_INVOKABLE QVariantMap getSavedPosition(const QString &filePath);
    Q_INVOKABLE void        savePosition(const QString &filePath, int positionMs, int playlistPos);
    Q_INVOKABLE void        clearPosition(const QString &filePath);
    Q_INVOKABLE void        get_resume_playback_options();
    Q_INVOKABLE void        get_shuffle_playback_options();
    Q_INVOKABLE void        get_auto_subtitles_options();
    Q_INVOKABLE void        get_subtitle_languages();
    Q_INVOKABLE void        get_image_duration_options();

signals:
    void dynamicOptionsReady(const QString &key, const QVariant &options);
    void searchReady(const QString &path);

public slots:
    void onSettingChanged(const QString &moduleId, const QString &key, const QVariant &value);

private:
    // The folder when the setting names none: OSDOS_MEDIA_DIR when the system
    // says where films go (OSD/OS image: the card's film partition), else a
    // folder in the data folder.
    QString defaultMediaRoot() const;

    QString m_appRoot;
    QString m_dataRoot;
    AppCore *m_appCore = nullptr;
    QString m_mediaRoot;

    struct SearchRun;
    std::unique_ptr<SearchRun> m_search;
    // The last search to finish.
    QString      m_foundPath;
    QVariantList m_found;
    void         searchSlice();
    QVariantMap  entryFor(const QString &dirPath, const QString &name, bool isDir) const;

    QString      historyFilePath() const;
    QVariantMap  loadHistory() const;
    void         saveHistory(const QVariantMap &history);
};
