#ifndef WAKU_MODULE_INTERFACE_H
#define WAKU_MODULE_INTERFACE_H

#include <QObject>
#include <QString>
#include <QVariantList>
#include "interface.h"

/**
 * @brief Interface for the Waku module
 * 
 * Provides access to the Waku network protocol for decentralized
 * peer-to-peer messaging.
 */
class WakuModuleInterface : public PluginInterface
{
public:
    virtual ~WakuModuleInterface() = default;

    // Waku lifecycle
    Q_INVOKABLE virtual int initWaku(const QString& configJson) = 0;
    Q_INVOKABLE virtual int startWaku() = 0;
    Q_INVOKABLE virtual void setEventCallback() = 0;
    
    // Relay protocol
    Q_INVOKABLE virtual int relaySubscribe(const QString& pubsubTopic) = 0;
    Q_INVOKABLE virtual int relayPublish(const QString& pubsubTopic, 
                                          const QString& message, 
                                          const QString& contentTopic) = 0;
    
    // Filter protocol
    Q_INVOKABLE virtual int filterSubscribe(const QString& pubsubTopic,
                                             const QString& contentTopic) = 0;
    
    // Store protocol
    Q_INVOKABLE virtual int storeQuery(const QString& pubsubTopic,
                                        const QString& contentTopic,
                                        const QString& startTime,
                                        const QString& endTime) = 0;
};

#define WakuModuleInterface_iid "org.logos.WakuModuleInterface"
Q_DECLARE_INTERFACE(WakuModuleInterface, WakuModuleInterface_iid)

#endif // WAKU_MODULE_INTERFACE_H
