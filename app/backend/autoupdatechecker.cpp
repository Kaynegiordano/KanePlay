#include "autoupdatechecker.h"

#include <QNetworkReply>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>
#include <QSettings>
#include <QStandardPaths>
#include <QDir>
#include <QProcess>
#include <QCoreApplication>
#include <QScopeGuard>

#ifdef Q_OS_WIN32
#define WIN32_LEAN_AND_MEAN
#include <Windows.h>
#endif

// Update channel: the manifest attached to the latest GitHub release. It can be
// overridden with the updateChannelUrl setting.
#define DEFAULT_UPDATE_CHANNEL_URL "https://github.com/Kaynegiordano/KanePlay/releases/latest/download/update.json"

AutoUpdateChecker::AutoUpdateChecker(QObject *parent) :
    QObject(parent),
    m_DownloadNam(nullptr),
    m_DownloadReply(nullptr),
    m_InstallerHash(QCryptographicHash::Sha256)
{
    m_Nam = new QNetworkAccessManager(this);

    // Never communicate over HTTP
    m_Nam->setStrictTransportSecurityEnabled(true);

    // Allow HTTP redirects
    m_Nam->setRedirectPolicy(QNetworkRequest::NoLessSafeRedirectPolicy);

    connect(m_Nam, &QNetworkAccessManager::finished,
            this, &AutoUpdateChecker::handleUpdateCheckRequestFinished);

    QString currentVersion(VERSION_STR);
    qDebug() << "Current KanePlay version:" << currentVersion;
    parseStringToVersionQuad(currentVersion, m_CurrentVersionQuad);

    // Should at least have a 1.0-style version number
    Q_ASSERT(m_CurrentVersionQuad.count() > 1);
}

void AutoUpdateChecker::start()
{
    if (!m_Nam) {
        // Checking again, the previous check deleted its network manager
        m_Nam = new QNetworkAccessManager(this);
        m_Nam->setStrictTransportSecurityEnabled(true);
        m_Nam->setRedirectPolicy(QNetworkRequest::NoLessSafeRedirectPolicy);
        connect(m_Nam, &QNetworkAccessManager::finished,
                this, &AutoUpdateChecker::handleUpdateCheckRequestFinished);
    }

#if defined(Q_OS_WIN32) || defined(Q_OS_DARWIN) || defined(STEAM_LINK) || defined(APP_IMAGE) // Only run update checker on platforms without auto-update
#if QT_VERSION >= QT_VERSION_CHECK(5, 14, 0) && QT_VERSION < QT_VERSION_CHECK(5, 15, 1) && !defined(QT_NO_BEARERMANAGEMENT)
    // HACK: Set network accessibility to work around QTBUG-80947 (introduced in Qt 5.14.0 and fixed in Qt 5.15.1)
    QT_WARNING_PUSH
    QT_WARNING_DISABLE_DEPRECATED
    m_Nam->setNetworkAccessible(QNetworkAccessManager::Accessible);
    QT_WARNING_POP
#endif

    // We'll get a callback when this is finished
    m_ChannelUrl = QUrl(QSettings().value("updateChannelUrl", DEFAULT_UPDATE_CHANNEL_URL).toString());
    qInfo() << "Checking for updates on" << m_ChannelUrl.toString();
    QNetworkRequest request(m_ChannelUrl);
#if QT_VERSION >= QT_VERSION_CHECK(5, 15, 0)
    // The host may be off or out of reach
    request.setTransferTimeout(10000);
#endif
#if QT_VERSION >= QT_VERSION_CHECK(5, 15, 0)
    request.setAttribute(QNetworkRequest::Http2AllowedAttribute, true);
#else
    request.setAttribute(QNetworkRequest::HTTP2AllowedAttribute, true);
#endif
    m_Nam->get(request);
#endif
}

void AutoUpdateChecker::parseStringToVersionQuad(QString& string, QVector<int>& version)
{
    QStringList list = string.split('.');
    for (const QString& component : std::as_const(list)) {
        version.append(component.toInt());
    }
}

QString AutoUpdateChecker::getPlatform()
{
#if defined(STEAM_LINK)
    return QStringLiteral("steamlink");
#elif defined(APP_IMAGE)
    return QStringLiteral("appimage");
#elif defined(Q_OS_DARWIN) && QT_VERSION >= QT_VERSION_CHECK(6, 0, 0)
    // Qt 6 changed this from 'osx' to 'macos'. Use the old one
    // to be consistent (and not require another entry in the manifest).
    return QStringLiteral("osx");
#else
    return QSysInfo::productType();
#endif
}

int AutoUpdateChecker::compareVersion(QVector<int>& version1, QVector<int>& version2) {
    for (int i = 0;; i++) {
        int v1Val = 0;
        int v2Val = 0;

        // Treat missing decimal places as 0
        if (i < version1.count()) {
            v1Val = version1[i];
        }
        if (i < version2.count()) {
            v2Val = version2[i];
        }
        if (i >= version1.count() && i >= version2.count()) {
            // Equal versions
            return 0;
        }

        if (v1Val < v2Val) {
            return -1;
        }
        else if (v1Val > v2Val) {
            return 1;
        }
    }
}

void AutoUpdateChecker::handleUpdateCheckRequestFinished(QNetworkReply* reply)
{
    Q_ASSERT(reply->isFinished());

    // Delete the QNetworkAccessManager to free resources and
    // prevent the bearer plugin from polling in the background.
    m_Nam->deleteLater();
    m_Nam = nullptr;

    // Tell the UI how the check went, whichever way we leave
    bool updateAvailable = false;
    bool failed = true;
    auto reportResult = qScopeGuard([&] { emit updateCheckFinished(updateAvailable, failed); });

    if (reply->error() == QNetworkReply::NoError) {
        QTextStream stream(reply);

#if QT_VERSION >= QT_VERSION_CHECK(6, 0, 0)
        stream.setEncoding(QStringConverter::Utf8);
#else
        stream.setCodec("UTF-8");
#endif

        // Read all data and queue the reply for deletion
        QString jsonString = stream.readAll();
        reply->deleteLater();

        QJsonParseError error;
        QJsonDocument jsonDoc = QJsonDocument::fromJson(jsonString.toUtf8(), &error);
        if (jsonDoc.isNull()) {
            qWarning() << "Update manifest malformed:" << error.errorString();
            return;
        }

        QJsonArray array = jsonDoc.array();
        if (array.isEmpty()) {
            qWarning() << "Update manifest doesn't contain an array";
            return;
        }

        failed = false;

        for (const auto& updateEntry : std::as_const(array)) {
            if (updateEntry.isObject()) {
                QJsonObject updateObj = updateEntry.toObject();
                if (!updateObj.contains("platform") ||
                        !updateObj.contains("arch") ||
                        !updateObj.contains("version") ||
                        !updateObj.contains("browser_url")) {
                    qWarning() << "Update manifest entry missing vital field";
                    continue;
                }

                if (!updateObj["platform"].isString() ||
                        !updateObj["arch"].isString() ||
                        !updateObj["version"].isString() ||
                        !updateObj["browser_url"].isString()) {
                    qWarning() << "Update manifest entry has unexpected vital field type";
                    continue;
                }

                if (updateObj["arch"] == QSysInfo::buildCpuArchitecture() &&
                        updateObj["platform"] == getPlatform()) {

                    // Check the kernel version minimum if one exists
                    if (updateObj.contains("kernel_version_at_least") && updateObj["kernel_version_at_least"].isString()) {
                        QVector<int> requiredVersionQuad;
                        QVector<int> actualVersionQuad;

                        QString requiredVersion = updateObj["kernel_version_at_least"].toString();
                        QString actualVersion = QSysInfo::kernelVersion();
                        parseStringToVersionQuad(requiredVersion, requiredVersionQuad);
                        parseStringToVersionQuad(actualVersion, actualVersionQuad);

                        if (compareVersion(actualVersionQuad, requiredVersionQuad) < 0) {
                            qDebug() << "Skipping manifest entry due to kernel version (" << actualVersion << "<" << requiredVersion << ")";
                            continue;
                        }
                    }

                    qDebug() << "Found update manifest match for current platform";

                    QString latestVersion = updateObj["version"].toString();
                    qDebug() << "Latest version of KanePlay for this platform is:" << latestVersion;

                    QVector<int> latestVersionQuad;
                    parseStringToVersionQuad(latestVersion, latestVersionQuad);

                    int res = compareVersion(m_CurrentVersionQuad, latestVersionQuad);
                    if (res < 0) {
                        // m_CurrentVersionQuad < latestVersionQuad
                        qDebug() << "Update available";

                        // URLs of the private channel are relative to the manifest
                        m_UpdateVersion = latestVersion;
                        if (updateObj["installer_url"].isString() && updateObj["sha256"].isString()) {
                            m_InstallerUrl = m_ChannelUrl.resolved(QUrl(updateObj["installer_url"].toString()));
                            m_InstallerSha256 = QByteArray::fromHex(updateObj["sha256"].toString().toLatin1());
                        }
                        if (updateObj["notes"].isString()) {
                            emit updateNotesAvailable(updateObj["notes"].toString());
                        }

                        updateAvailable = true;
                        emit onUpdateAvailable(latestVersion,
                                               m_ChannelUrl.resolved(QUrl(updateObj["browser_url"].toString())).toString());
                        return;
                    }
                    else if (res > 0) {
                        qDebug() << "Update manifest version lower than current version";
                        return;
                    }
                    else {
                        qDebug() << "Update manifest version equal to current version";
                        return;
                    }
                }
            }
            else {
                qWarning() << "Update manifest contained unrecognized entry:" << updateEntry.toString();
            }
        }

        qWarning() << "No entry in update manifest found for current platform:"
                   << QSysInfo::buildCpuArchitecture() << getPlatform() << QSysInfo::kernelVersion();
    }
    else {
        qWarning() << "Update checking failed with error:" << reply->error();
        reply->deleteLater();
    }
}

bool AutoUpdateChecker::canInstallUpdate()
{
#ifdef Q_OS_WIN32
    return m_InstallerUrl.isValid() && m_InstallerSha256.size() == 32;
#else
    return false;
#endif
}

void AutoUpdateChecker::installUpdate()
{
    if (!canInstallUpdate() || m_DownloadReply != nullptr) {
        return;
    }

    QDir dir(QStandardPaths::writableLocation(QStandardPaths::TempLocation));
    dir.mkpath("KanePlay-Update");
    dir.cd("KanePlay-Update");

    m_InstallerFile.setFileName(dir.filePath(QString("KanePlaySetup-%1.exe").arg(m_UpdateVersion)));
    if (!m_InstallerFile.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        emit updateDownloadFailed(m_InstallerFile.errorString());
        return;
    }
    m_InstallerHash.reset();

    if (m_DownloadNam == nullptr) {
        m_DownloadNam = new QNetworkAccessManager(this);
        m_DownloadNam->setStrictTransportSecurityEnabled(true);
        m_DownloadNam->setRedirectPolicy(QNetworkRequest::NoLessSafeRedirectPolicy);
    }

    qInfo() << "Downloading update from" << m_InstallerUrl.toString();
    QNetworkRequest request(m_InstallerUrl);
#if QT_VERSION >= QT_VERSION_CHECK(5, 15, 0)
    // Aborts if no data arrives for this long, not after the whole download
    request.setTransferTimeout(30000);
#endif
    m_DownloadReply = m_DownloadNam->get(request);

    connect(m_DownloadReply, &QNetworkReply::readyRead, this, [this]() {
        QByteArray data = m_DownloadReply->readAll();
        m_InstallerHash.addData(data);
        m_InstallerFile.write(data);
    });
    connect(m_DownloadReply, &QNetworkReply::downloadProgress,
            this, &AutoUpdateChecker::updateDownloadProgress);
    connect(m_DownloadReply, &QNetworkReply::finished,
            this, &AutoUpdateChecker::handleInstallerDownloadFinished);
}

void AutoUpdateChecker::cancelUpdate()
{
    if (m_DownloadReply != nullptr) {
        // finished() will clean up
        m_DownloadReply->abort();
    }
}

void AutoUpdateChecker::handleInstallerDownloadFinished()
{
    QNetworkReply* reply = m_DownloadReply;
    m_DownloadReply = nullptr;
    reply->deleteLater();

    if (reply->error() == QNetworkReply::NoError) {
        QByteArray data = reply->readAll();
        m_InstallerHash.addData(data);
        m_InstallerFile.write(data);
    }
    bool writeOk = m_InstallerFile.error() == QFileDevice::NoError;
    m_InstallerFile.close();

    if (reply->error() == QNetworkReply::OperationCanceledError) {
        m_InstallerFile.remove();
        return;
    }
    else if (reply->error() != QNetworkReply::NoError) {
        qWarning() << "Update download failed:" << reply->errorString();
        m_InstallerFile.remove();
        emit updateDownloadFailed(reply->errorString());
        return;
    }
    else if (!writeOk) {
        m_InstallerFile.remove();
        emit updateDownloadFailed(m_InstallerFile.errorString());
        return;
    }
    else if (m_InstallerHash.result() != m_InstallerSha256) {
        qWarning() << "Update installer hash mismatch:" << m_InstallerHash.result().toHex();
        m_InstallerFile.remove();
        emit updateDownloadFailed(tr("The downloaded file is corrupted (SHA-256 mismatch)."));
        return;
    }

    launchInstaller();
}

void AutoUpdateChecker::launchInstaller()
{
#ifdef Q_OS_WIN32
    QString setupPath = QDir::toNativeSeparators(m_InstallerFile.fileName());
    QString exePath = QDir::toNativeSeparators(QCoreApplication::applicationFilePath());
    QString logPath = QDir::toNativeSeparators(QFileInfo(m_InstallerFile).dir().filePath("install.log"));

    // The installer can only replace KanePlay once it has exited, and the
    // script relaunches it only after a successful installation. Keep the
    // installer and its log when Burn fails so the failure can be diagnosed.
    QFile script(QFileInfo(m_InstallerFile).dir().filePath("installer.cmd"));
    if (!script.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        emit updateDownloadFailed(script.errorString());
        return;
    }
    script.write(QString("@echo off\r\n"
                         "chcp 65001 >nul\r\n"
                         "ping -n 3 127.0.0.1 >nul\r\n"
                         "start \"\" /wait \"%1\" /passive /norestart -l \"%3\"\r\n"
                         "set \"installResult=%errorlevel%\"\r\n"
                         "if \"%installResult%\"==\"0\" goto success\r\n"
                         "if \"%installResult%\"==\"3010\" goto success\r\n"
                         "powershell -NoProfile -WindowStyle Hidden -Command \"Add-Type -AssemblyName PresentationFramework; [System.Windows.MessageBox]::Show('KanePlay installation failed (code %installResult%). Log: %3')\"\r\n"
                         "exit /b %installResult%\r\n"
                         ":success\r\n"
                         "del \"%1\"\r\n"
                         "start \"\" \"%2\"\r\n")
                 .arg(setupPath, exePath, logPath).toUtf8());
    script.close();

    QProcess process;
    process.setProgram("cmd.exe");
    process.setArguments({ "/c", QDir::toNativeSeparators(script.fileName()) });
    process.setCreateProcessArgumentsModifier([](QProcess::CreateProcessArguments* args) {
        args->flags |= CREATE_NO_WINDOW;
    });
    if (!process.startDetached()) {
        emit updateDownloadFailed(process.errorString());
        return;
    }

    qInfo() << "Update installer started, quitting";
    emit updateInstallerStarted();
#endif
}
