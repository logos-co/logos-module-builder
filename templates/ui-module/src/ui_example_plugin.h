#ifndef UI_EXAMPLE_PLUGIN_H
#define UI_EXAMPLE_PLUGIN_H

#include <QObject>
#include <QWidget>
#include <IComponent.h>

class LogosAPI;

class UiExamplePlugin : public QObject, public IComponent
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID IComponent_iid FILE "metadata.json")
    Q_INTERFACES(IComponent)

public:
    explicit UiExamplePlugin(QObject* parent = nullptr);
    ~UiExamplePlugin() override;

    Q_INVOKABLE QWidget* createWidget(LogosAPI* logosAPI = nullptr) override;
    void destroyWidget(QWidget* widget) override;
};

#endif // UI_EXAMPLE_PLUGIN_H
