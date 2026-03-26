#ifndef UI_EXAMPLE_PLUGIN_H
#define UI_EXAMPLE_PLUGIN_H

#include <QObject>
#include <QWidget>
#include <QVariantList>
#include <IComponent.h>
#include "ui_example_interface.h"

class UiExamplePlugin : public QObject, public UiExampleInterface, public IComponent
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID IComponent_iid FILE "metadata.json")
    Q_INTERFACES(UiExampleInterface PluginInterface IComponent)

public:
    explicit UiExamplePlugin(QObject* parent = nullptr);
    ~UiExamplePlugin() override;

    // PluginInterface implementation
    QString name()    const override { return "ui_example"; }
    QString version() const override { return "1.0.0"; }

    // LogosAPI initialization
    Q_INVOKABLE void initLogos(LogosAPI* api);

    // UI module entry points — called by the host application
    Q_INVOKABLE QWidget* createWidget(LogosAPI* logosAPI = nullptr);
    Q_INVOKABLE void destroyWidget(QWidget* widget);

signals:
    void eventResponse(const QString& eventName, const QVariantList& args);

private:
    LogosAPI* m_logosAPI = nullptr;
};

#endif // UI_EXAMPLE_PLUGIN_H
