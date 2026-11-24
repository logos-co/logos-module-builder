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

    // Typed replica — auto-synced properties and callable slots.
    readonly property var backend: logos.module("ui_example")
    property bool ready: false

    // "status" property from the .rep file, auto-updated via QTRO.
    readonly property string status: backend ? backend.status : ""

    color: Theme.palette.background

    Connections {
        target: logos
        function onViewModuleReadyChanged(moduleName, isReady) {
            if (moduleName === "ui_example")
                root.ready = isReady && root.backend !== null;
        }
    }
    Component.onCompleted: {
        root.ready = root.backend !== null && logos.isViewModuleReady("ui_example");
    }

    LogosScrollView {
        id: scroll
        anchors.fill: parent
        anchors.margins: Theme.pageMargin(root.width)
        contentWidth: availableWidth

        ColumnLayout {
            width: scroll.availableWidth
            spacing: Theme.spacing.xlarge

            LogosPageHeader {
                Layout.fillWidth: true
                title: qsTr("UI Example (C++ backend)")
                // Connection status
                subtitle: root.ready ? qsTr("Connected") : qsTr("Connecting to backend...")
            }

            // The fields share the width; nothing is fixed, so it fits a phone.
            RowLayout {
                Layout.fillWidth: true
                Layout.maximumWidth: Theme.layouts.form.maximumWidth
                spacing: Theme.spacing.medium

                LogosTextField {
                    id: inputA
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    placeholderText: "a"
                    validator: IntValidator {}
                }
                LogosTextField {
                    id: inputB
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    placeholderText: "b"
                    validator: IntValidator {}
                }
                LogosButton {
                    text: qsTr("Add")
                    variant: LogosButton.Variant.Primary
                    enabled: root.ready
                    onClicked: {
                        // logos.watch() delivers the pending reply via callbacks
                        logos.watch(backend.add(parseInt(inputA.text) || 0, parseInt(inputB.text) || 0), function (value) {
                            resultText.text = qsTr("Result: %1").arg(value);
                        }, function (error) {
                            resultText.text = qsTr("Error: %1").arg(error);
                        });
                    }
                }
            }

            // Shows the return value from the slot call
            LogosText {
                id: resultText
                Layout.fillWidth: true
                text: qsTr("Press Add to call the backend")
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
            }

            // Shows the auto-synced "status" property from the backend
            LogosText {
                Layout.fillWidth: true
                text: qsTr("Backend status: %1").arg(root.status)
                textFormat: Text.PlainText
                color: Theme.palette.textSecondary
                wrapMode: Text.Wrap
            }
        }
    }
}
