import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls
import Logos.Layouts

// The host sizes this view to the app's area, from a phone's width to a
// desktop's. Build it from the design system's layouts and controls and give
// nothing a fixed width; the design system's storybook has a reference app
// with a page of each kind (docs/responsive.md).
Rectangle {
    id: root

    color: Theme.palette.background

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.pageMargin(root.width)
        spacing: Theme.spacing.xlarge

        LogosPageHeader {
            Layout.fillWidth: true
            title: qsTr("QML UI Example")
            subtitle: qsTr("Hello from ui_qml_example!")
        }

        LogosButton {
            text: qsTr("Call Core Module")
            onClicked: {
                // The logos bridge is injected by the host application.
                // Uncomment to call a backend module:
                // var result = logos.callModule("my_module", "myMethod", ["arg"])
                console.log("Button clicked")
            }
        }

        Item { Layout.fillHeight: true }
    }
}
