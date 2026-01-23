#include "waku_module_plugin.h"
#include "logos_api.h"
#include <QDebug>

// Static callback implementations
void WakuModulePlugin::init_callback(int ret_code, const char* msg, void* user_data)
{
    auto* plugin = static_cast<WakuModulePlugin*>(user_data);
    qDebug() << "Waku init callback:" << ret_code << msg;
    
    emit plugin->eventResponse("waku_init", 
        QVariantList() << ret_code << QString::fromUtf8(msg));
}

void WakuModulePlugin::start_callback(int ret_code, const char* msg, void* user_data)
{
    auto* plugin = static_cast<WakuModulePlugin*>(user_data);
    qDebug() << "Waku start callback:" << ret_code << msg;
    
    emit plugin->eventResponse("waku_started",
        QVariantList() << ret_code << QString::fromUtf8(msg));
}

void WakuModulePlugin::event_callback(int ret_code, const char* msg, void* user_data)
{
    auto* plugin = static_cast<WakuModulePlugin*>(user_data);
    qDebug() << "Waku event callback:" << ret_code << msg;
    
    // Forward event to LogosAPI for distribution
    if (plugin->m_logosAPI) {
        plugin->m_logosAPI->getClient("core_manager")->onEventResponse(
            "waku_event", QVariantList() << ret_code << QString::fromUtf8(msg));
    }
    
    emit plugin->eventResponse("waku_event",
        QVariantList() << ret_code << QString::fromUtf8(msg));
}

WakuModulePlugin::WakuModulePlugin(QObject* parent)
    : QObject(parent)
{
    qDebug() << "WakuModulePlugin: Constructor called";
}

WakuModulePlugin::~WakuModulePlugin()
{
    qDebug() << "WakuModulePlugin: Destructor called";
    // Note: libwaku cleanup would happen here
}

void WakuModulePlugin::initLogos(LogosAPI* api)
{
    qDebug() << "WakuModulePlugin: initLogos called";
    m_logosAPI = api;
    
    emit eventResponse("initialized", QVariantList() << "waku_module" << "1.0.0");
}

int WakuModulePlugin::initWaku(const QString& configJson)
{
    qDebug() << "WakuModulePlugin: initWaku called";
    
    // Call libwaku waku_new()
    wakuCtx = waku_new(configJson.toUtf8().constData(), init_callback, this);
    
    if (!wakuCtx) {
        qWarning() << "Failed to create Waku context";
        return -1;
    }
    
    return 0;
}

int WakuModulePlugin::startWaku()
{
    qDebug() << "WakuModulePlugin: startWaku called";
    
    if (!wakuCtx) {
        qWarning() << "Waku context not initialized";
        return -1;
    }
    
    return waku_start(wakuCtx, start_callback, this);
}

void WakuModulePlugin::setEventCallback()
{
    qDebug() << "WakuModulePlugin: setEventCallback called";
    
    if (!wakuCtx) {
        qWarning() << "Waku context not initialized";
        return;
    }
    
    waku_set_event_callback(wakuCtx, event_callback, this);
}

int WakuModulePlugin::relaySubscribe(const QString& pubsubTopic)
{
    qDebug() << "WakuModulePlugin: relaySubscribe called for" << pubsubTopic;
    
    if (!wakuCtx) return -1;
    
    return waku_relay_subscribe(wakuCtx, pubsubTopic.toUtf8().constData(),
                                 event_callback, this);
}

int WakuModulePlugin::relayPublish(const QString& pubsubTopic,
                                    const QString& message,
                                    const QString& contentTopic)
{
    qDebug() << "WakuModulePlugin: relayPublish called";
    
    if (!wakuCtx) return -1;
    
    return waku_relay_publish(wakuCtx, 
                               pubsubTopic.toUtf8().constData(),
                               message.toUtf8().constData(),
                               contentTopic.toUtf8().constData(),
                               0,  // timeout
                               event_callback, this);
}

int WakuModulePlugin::filterSubscribe(const QString& pubsubTopic,
                                       const QString& contentTopic)
{
    qDebug() << "WakuModulePlugin: filterSubscribe called";
    
    if (!wakuCtx) return -1;
    
    // Build content topics array (single item)
    QString contentTopics = QString("[\"") + contentTopic + "\"]";
    
    return waku_filter_subscribe(wakuCtx,
                                  pubsubTopic.toUtf8().constData(),
                                  contentTopics.toUtf8().constData(),
                                  event_callback, this);
}

int WakuModulePlugin::storeQuery(const QString& pubsubTopic,
                                  const QString& contentTopic,
                                  const QString& startTime,
                                  const QString& endTime)
{
    qDebug() << "WakuModulePlugin: storeQuery called";
    
    if (!wakuCtx) return -1;
    
    // Build query JSON
    QString queryJson = QString(R"({
        "pubsubTopic": "%1",
        "contentTopics": ["%2"],
        "startTime": %3,
        "endTime": %4
    })").arg(pubsubTopic, contentTopic, startTime, endTime);
    
    return waku_store_query(wakuCtx,
                             queryJson.toUtf8().constData(),
                             event_callback, this);
}
