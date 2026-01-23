#ifndef MINIMAL_PLUGIN_H
#define MINIMAL_PLUGIN_H

#include <QObject>
#include <QString>
#include "minimal_interface.h"

// Forward declarations
class LogosAPI;

/**
 * @brief Minimal module plugin implementation
 * 
 * This is a minimal example of a Logos module plugin.
 * It demonstrates the basic structure without any external dependencies.
 */
class MinimalPlugin : public QObject, public MinimalInterface
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID MinimalInterface_iid FILE "metadata.json")
    Q_INTERFACES(MinimalInterface PluginInterface)

public:
    explicit MinimalPlugin(QObject* parent = nullptr);
    ~MinimalPlugin() override;

    // PluginInterface implementation
    QString name() const override { return "minimal"; }
    QString version() const override { return "1.0.0"; }
    void initLogos(LogosAPI* api) override;

    // MinimalInterface implementation
    Q_INVOKABLE QString greet(const QString& name) override;
    Q_INVOKABLE QString getStatus() override;

signals:
    void eventResponse(const QString& eventName, const QVariantList& args);

private:
    LogosAPI* m_logosAPI = nullptr;
    bool m_initialized = false;
};

#endif // MINIMAL_PLUGIN_H
