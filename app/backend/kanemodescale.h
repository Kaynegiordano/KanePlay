#pragma once

// Mise à l'échelle du PC hôte pendant le streaming (réglage KaneMode « Mise à l'échelle sur le PC
// hôte »). Le protocole ne transmet aucune valeur libre à l'hôte : le complément KaneMode installé
// sur l'hôte (setup/hote-echelle) crée pour chaque appli des variantes « Desktop [150 %] » dont la
// commande de préparation règle l'échelle, puis la remet à la fin. Le moteur lance la variante qui
// correspond au réglage et les cache dans la liste des applis.

#include "nvapp.h"

#include <QRegularExpression>
#include <QVector>

namespace KaneModeScale {

// « <nom> [<pourcentage> %] » : nom de l'appli d'origine et pourcentage
inline bool parse(const QString& name, QString* base = nullptr, int* percent = nullptr)
{
    static const QRegularExpression re(QStringLiteral("^(.+) \\[(\\d{3}) %\\]$"));
    const QRegularExpressionMatch m = re.match(name);
    if (!m.hasMatch()) {
        return false;
    }
    if (base) {
        *base = m.captured(1);
    }
    if (percent) {
        *percent = m.captured(2).toInt();
    }
    return true;
}

inline bool isVariant(const NvApp& app)
{
    return parse(app.name);
}

// Appli d'origine d'une variante (sinon l'appli elle-même)
inline int baseId(const QVector<NvApp>& apps, int appId)
{
    for (const NvApp& app : apps) {
        QString base;
        if (app.id != appId || !parse(app.name, &base)) {
            continue;
        }
        for (const NvApp& other : apps) {
            if (other.name == base) {
                return other.id;
            }
        }
        break;
    }
    return appId;
}

// Appli à lancer : la variante au pourcentage voulu si l'hôte l'a, sinon l'appli demandée.
// Une session déjà ouverte est reprise telle quelle (l'appli d'origine ou une de ses variantes).
inline NvApp pick(const QVector<NvApp>& apps, const NvApp& app, int percent, int runningId)
{
    if (isVariant(app) || runningId == app.id) {
        return app;
    }
    if (runningId != 0) {
        for (const NvApp& other : apps) {
            QString base;
            if (other.id == runningId && parse(other.name, &base) && base == app.name) {
                return other;
            }
        }
    }
    if (percent <= 0) {
        return app;
    }
    const QString wanted = QStringLiteral("%1 [%2 %]").arg(app.name).arg(percent);
    for (const NvApp& other : apps) {
        if (other.name == wanted) {
            return other;
        }
    }
    return app;
}

}
