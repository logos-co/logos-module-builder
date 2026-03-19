#include "ui_example_plugin.h"
#include <QDebug>
#include <QLabel>
#include <QVBoxLayout>

UiExamplePlugin::UiExamplePlugin(QObject* parent)
    : QObject(parent)
{
    qDebug() << "UiExamplePlugin: Constructor called";
}

UiExamplePlugin::~UiExamplePlugin()
{
    qDebug() << "UiExamplePlugin: Destructor called";
}

QWidget* UiExamplePlugin::createWidget(LogosAPI* logosAPI)
{
    Q_UNUSED(logosAPI)
    auto* widget = new QWidget();
    auto* layout = new QVBoxLayout(widget);
    auto* label = new QLabel("Hello from ui_example!", widget);
    layout->addWidget(label);
    return widget;
}

void UiExamplePlugin::destroyWidget(QWidget* widget)
{
    delete widget;
}
