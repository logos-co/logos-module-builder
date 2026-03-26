#ifndef UI_EXAMPLE_INTERFACE_H
#define UI_EXAMPLE_INTERFACE_H

#include <QObject>
#include <QString>
#include "interface.h"

/**
 * @brief Interface for the UI Example module
 *
 * UI modules extend PluginInterface and provide createWidget()/destroyWidget()
 * to supply the host application with a QWidget* for display.
 */
class UiExampleInterface : public PluginInterface
{
public:
    virtual ~UiExampleInterface() = default;
};

#define UiExampleInterface_iid "org.logos.UiExampleInterface"
Q_DECLARE_INTERFACE(UiExampleInterface, UiExampleInterface_iid)

#endif // UI_EXAMPLE_INTERFACE_H
