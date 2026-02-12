#include "minimal_plugin.h"
#include "logos_api.h"
#include "logos_api_client.h"
#include <QDebug>

MinimalPlugin::MinimalPlugin(QObject* parent)
    : QObject(parent)
{
    qDebug() << "MinimalPlugin: Constructor called";
}

MinimalPlugin::~MinimalPlugin()
{
    qDebug() << "MinimalPlugin: Destructor called";
}

void MinimalPlugin::initLogos(LogosAPI* logosAPIInstance) {
    if (logos) {
        delete logos;
        logos = nullptr;
    }
    if (logosAPI) {
        delete logosAPI;
        logosAPI = nullptr;
    }
    logosAPI = logosAPIInstance;
    if (logosAPI) {
        logos = new LogosModules(logosAPI);
    }
}

QString MinimalPlugin::greet(const QString& name)
{
    qDebug() << "MinimalPlugin: greet called with name:" << name;
    
    QString greeting = QString("Hello, %1! Greetings from the Minimal module.").arg(name);
    
    // Emit an event for the greeting
    emit eventResponse("greeted", QVariantList() << name << greeting);
    
    return greeting;
}

QString MinimalPlugin::getStatus()
{
    qDebug() << "MinimalPlugin: getStatus called";
    
    if (m_initialized) {
        return "Minimal module is running and initialized.";
    } else {
        return "Minimal module is loaded but not yet initialized.";
    }
}
