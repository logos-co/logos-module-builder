#ifndef MINIMAL_INTERFACE_H
#define MINIMAL_INTERFACE_H

#include <QObject>
#include <QString>
#include "interface.h"

/**
 * @brief Interface for the Minimal module
 * 
 * This interface defines the public API that this module exposes
 * to other modules and applications.
 */
class MinimalInterface : public PluginInterface
{
public:
    virtual ~MinimalInterface() = default;
    
    /**
     * @brief Example method that returns a greeting
     * @param name The name to greet
     * @return A greeting string
     */
    Q_INVOKABLE virtual QString greet(const QString& name) = 0;
    
    /**
     * @brief Example method that returns the module status
     * @return Status string
     */
    Q_INVOKABLE virtual QString getStatus() = 0;
};

#define MinimalInterface_iid "org.logos.MinimalInterface"
Q_DECLARE_INTERFACE(MinimalInterface, MinimalInterface_iid)

#endif // MINIMAL_INTERFACE_H
