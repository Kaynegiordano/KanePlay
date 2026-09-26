#pragma once

#include <QObject>
#include <QNetworkAccessManager>
#include <QFile>
#include <QCryptographicHash>

class AutoUpdateChecker : public QObject
{
    Q_OBJECT
public:
    explicit AutoUpdateChecker(QObject *parent = nullptr);

    Q_INVOKABLE void start();

    // Downloads the installer of the update found by start(), checks its
    // SHA-256, then runs it and relaunches KanePlay once it's done
    Q_INVOKABLE void installUpdate();

    Q_INVOKABLE void cancelUpdate();

    Q_INVOKABLE bool canInstallUpdate();

signals:
    void onUpdateAvailable(QString newVersion, QString url);

    // Every check ends with this, after onUpdateAvailable when there is one
    void updateCheckFinished(bool updateAvailable, bool failed);

    void updateNotesAvailable(QString notes);

    void updateDownloadProgress(qint64 received, qint64 total);

    void updateDownloadFailed(QString error);

    // The installer is running and KanePlay must quit so it can be replaced
    void updateInstallerStarted();

private slots:
    void handleUpdateCheckRequestFinished(QNetworkReply* reply);

private:
    void parseStringToVersionQuad(QString& string, QVector<int>& version);

    int compareVersion(QVector<int>& version1, QVector<int>& version2);

    QString getPlatform();

    void handleInstallerDownloadFinished();

    void launchInstaller();

    QVector<int> m_CurrentVersionQuad;
    QNetworkAccessManager* m_Nam;

    QUrl m_ChannelUrl;
    QString m_UpdateVersion;
    QUrl m_InstallerUrl;
    QByteArray m_InstallerSha256;

    QNetworkAccessManager* m_DownloadNam;
    QNetworkReply* m_DownloadReply;
    QFile m_InstallerFile;
    QCryptographicHash m_InstallerHash;
};
