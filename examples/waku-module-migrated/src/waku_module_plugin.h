#ifndef WAKU_MODULE_PLUGIN_H
#define WAKU_MODULE_PLUGIN_H

#include <QObject>
#include <QString>
#include "waku_module_interface.h"

// Include libwaku C API header
#include "lib/libwaku.h"

class LogosAPI;

/**
 * @brief Waku module plugin implementation
 * 
 * Wraps the libwaku C library to provide Waku protocol access.
 */
class WakuModulePlugin : public QObject, public WakuModuleInterface
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID WakuModuleInterface_iid FILE "metadata.json")
    Q_INTERFACES(WakuModuleInterface PluginInterface)

public:
    explicit WakuModulePlugin(QObject* parent = nullptr);
    ~WakuModulePlugin() override;

    // PluginInterface implementation
    QString name() const override { return "waku_module"; }
    QString version() const override { return "1.0.0"; }
    void initLogos(LogosAPI* api) override;

    // WakuModuleInterface implementation
    Q_INVOKABLE int initWaku(const QString& configJson) override;
    Q_INVOKABLE int startWaku() override;
    Q_INVOKABLE void setEventCallback() override;
    Q_INVOKABLE int relaySubscribe(const QString& pubsubTopic) override;
    Q_INVOKABLE int relayPublish(const QString& pubsubTopic,
                                  const QString& message,
                                  const QString& contentTopic) override;
    Q_INVOKABLE int filterSubscribe(const QString& pubsubTopic,
                                     const QString& contentTopic) override;
    Q_INVOKABLE int storeQuery(const QString& pubsubTopic,
                                const QString& contentTopic,
                                const QString& startTime,
                                const QString& endTime) override;

signals:
    void eventResponse(const QString& eventName, const QVariantList& args);

private:
    // Callback handlers
    static void init_callback(int ret_code, const char* msg, void* user_data);
    static void start_callback(int ret_code, const char* msg, void* user_data);
    static void event_callback(int ret_code, const char* msg, void* user_data);
    
    LogosAPI* m_logosAPI = nullptr;
    void* wakuCtx = nullptr;
};

#endif // WAKU_MODULE_PLUGIN_H
