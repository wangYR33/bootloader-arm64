import QtQuick 2.12
import QtQuick.Window 2.12
import QtQuick.Controls 1.4
import QtQuick.Controls.Styles 1.4
import QtQuick.VirtualKeyboard 2.4
import QtQuick.VirtualKeyboard.Settings 2.2

Rectangle {
    id:appContainer
    visible: true
    width: 700
    color: "#000000"

    Row {
        width: parent.width
        height: 20
        anchors.top: parent.top
        anchors.left: parent.left

        Rectangle {
            width: parent.width - 20
            height: parent.height
            color: "#655c4c"

            MouseArea {
                id: dragRegion
                anchors.fill: parent
                property point clickPos: "0,0"
                onPressed: {
                    clickPos = Qt.point(mouse.x, mouse.y)
                }
                onPositionChanged: {
                    var delta = Qt.point(mouse.x - clickPos.x, mouse.y - clickPos.y)
                    keyboardObject.setGeometry(keyboardObject.x + delta.x, keyboardObject.y + delta.y, appContainer.width, appContainer.height)
                }

            }
        }

        Button {
            width: 20
            height: parent.height
            text: "<font color='#fefefe'>X</font>"

            style: ButtonStyle {
                background: Rectangle {
                    color: "#655c4c"
                    border.width: 0
                    radius: 0
                }
            }

            onClicked: keyboardObject.hide()
        }
    }

    InputPanel {
        id: inputPanel
        width: parent.width
        anchors.bottom: parent.bottom
        externalLanguageSwitchEnabled: true
        Component.onCompleted:{
            VirtualKeyboardSettings.activeLocales = ["en_US", "tr_TR"]
            VirtualKeyboardSettings.locale = "en_US"
        }
        Connections {
            target: keyboardObject
            onLanguageChanged: { // function onLanguageChanged(langId) {
                if(langId < VirtualKeyboardSettings.activeLocales.length && langId > -1)
                    VirtualKeyboardSettings.locale = VirtualKeyboardSettings.activeLocales[langId]
            }
        }
    }
}
