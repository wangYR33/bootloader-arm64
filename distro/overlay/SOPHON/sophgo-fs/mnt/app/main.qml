import QtQuick 2.0
import QtQuick.Window 2.15
import QtQuick.VirtualKeyboard 2.15
import QtQuick.Controls 2.5
import Qt.labs.platform 1.1
Window {
    id: window
    width: 640
    height: 480
    visible: true
    title: qsTr("Hello World")

    function log(...msg) {
            let msgs = "";
            msg.forEach((item) => {
                            if (msgs.length != 0) {
                                msgs += " ";
                            }
                            msgs += item;
                        });
            console.log(msgs);
        }
    Rectangle {
                x: 0;
                y: 0;
                width: 640;
                height: 480;
                rotation: 0;
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#A4A050"; }
                    GradientStop { position: 1.0; color: "#4090A0"; }
                }
            }

    Button {
            id: selectFileButton
            x: 268
            y: 124
            width: 105
            height: 54
            text: qsTr("选择")
            font.pointSize: 10

            onClicked: {
                log(text, "clicked");
            }
    }
    TextField {
            id: selectedFileTextArea
            x: 70
            y: 70
            width: 500
            objectName: "selectedFileTextArea"
            text: fileDialog.file.toString().slice(8)
            font.pointSize: 12
            placeholderText: qsTr("选择文件")
        }
    InputPanel {
        id: inputPanel
        z: 99
        x: 0
        y: window.height
        width: window.width

        states: State {
            name: "visible"
            when: inputPanel.active
            PropertyChanges {
                target: inputPanel
                y: window.height - inputPanel.height
            }
        }
        transitions: Transition {
            from: ""
            to: "visible"
            reversible: true
            ParallelAnimation {
                NumberAnimation {
                    properties: "y"
                    duration: 250
                    easing.type: Easing.InOutQuad
                }
            }
        }
    }
}
