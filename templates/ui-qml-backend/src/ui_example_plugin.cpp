#include "ui_example_plugin.h"
#include "logos_api.h"
#include <QDebug>

UiExamplePlugin::UiExamplePlugin(QObject* parent)
    : UiExampleSimpleSource(parent)
{
    setStatus("Ready");
}

UiExamplePlugin::~UiExamplePlugin() = default;

void UiExamplePlugin::initLogos(LogosAPI* api)
{
    // Assign to the inherited `logosAPI` member from PluginInterface — the host
    // reads it directly to dispatch calls; a separate member won't be seen.
    logosAPI = api;
    setBackend(this);
    qDebug() << "UiExamplePlugin: initialized";
}

int UiExamplePlugin::add(int a, int b)
{
    int result = a + b;
    setStatus(QStringLiteral("%1 + %2 = %3").arg(a).arg(b).arg(result));
    return result;
}
