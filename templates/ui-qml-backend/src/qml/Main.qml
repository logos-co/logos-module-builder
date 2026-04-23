import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root

    // Typed replica — auto-synced properties and callable slots.
    readonly property var backend: logos.module("ui_example")
    readonly property bool ready: backend !== null && logos.isViewModuleReady("ui_example")

    // "status" property from the .rep file, auto-updated via QTRO.
    readonly property string status: backend ? backend.status : ""

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 16

        Text {
            text: "UI Example (C++ backend)"
            font.pixelSize: 20
            color: "#ffffff"
            Layout.alignment: Qt.AlignHCenter
        }

        // Connection status
        Text {
            text: root.ready ? "Connected" : "Connecting to backend..."
            color: root.ready ? "#56d364" : "#f0883e"
            font.pixelSize: 12
        }

        RowLayout {
            spacing: 12
            Layout.fillWidth: true

            TextField {
                id: inputA
                placeholderText: "a"
                Layout.preferredWidth: 80
                validator: IntValidator {}
            }

            TextField {
                id: inputB
                placeholderText: "b"
                Layout.preferredWidth: 80
                validator: IntValidator {}
            }

            Button {
                text: "Add"
                enabled: root.ready
                onClicked: {
                    // logos.watch() delivers the pending reply via callbacks
                    logos.watch(backend.add(parseInt(inputA.text) || 0, parseInt(inputB.text) || 0), function (value) {
                        resultText.text = "Result: " + value;
                    }, function (error) {
                        resultText.text = "Error: " + error;
                    });
                }
            }
        }

        // Shows the return value from the slot call
        Text {
            id: resultText
            text: "Press Add to call the backend"
            color: "#56d364"
            font.pixelSize: 15
        }

        // Shows the auto-synced "status" property from the backend
        Text {
            text: "Backend status: " + root.status
            color: "#8b949e"
            font.pixelSize: 13
        }

        Item {
            Layout.fillHeight: true
        }
    }
}
