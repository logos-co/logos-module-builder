#ifndef UI_EXAMPLE_PLUGIN_H
#define UI_EXAMPLE_PLUGIN_H

#include <QString>
#include <QVariantList>
#include "ui_example_interface.h"
#include "LogosViewPluginBase.h"
#include "rep_ui_example_source.h"

class LogosAPI;

// Inherits UiExampleSimpleSource (generated from ui_example.rep) so typed
// remoting works and QML replicas get auto-synced properties + callable slots.
class UiExamplePlugin : public UiExampleSimpleSource,
                        public UiExampleInterface,
                        public UiExampleViewPluginBase
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID UiExampleInterface_iid FILE "metadata.json")
    Q_INTERFACES(UiExampleInterface)

public:
    explicit UiExamplePlugin(QObject* parent = nullptr);
    ~UiExamplePlugin() override;

    QString name()    const override { return "ui_example"; }
    QString version() const override { return "1.0.0"; }

    Q_INVOKABLE void initLogos(LogosAPI* api);

    // Slots from ui_example.rep
    int add(int a, int b) override;

signals:
    void eventResponse(const QString& eventName, const QVariantList& args);

private:
    LogosAPI* m_logosAPI = nullptr;
};

#endif // UI_EXAMPLE_PLUGIN_H
