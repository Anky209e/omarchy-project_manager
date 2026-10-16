import QtQuick

Rectangle {
  id: button
  property string text: ""
  property color foreground: "#eeeeee"
  property color accent: "#88aaff"
  property string fontFamily: "sans-serif"
  property int pixelSize: 13
  property int padding: 10
  signal clicked()
  implicitWidth: label.implicitWidth + padding * 2
  implicitHeight: pixelSize + padding * 2
  color: Qt.rgba(accent.r, accent.g, accent.b, pointer.containsMouse ? 0.22 : 0.10)
  border.width: activeFocus ? 1 : 0
  border.color: accent
  opacity: enabled ? 1 : 0.4
  Accessible.role: Accessible.Button
  Accessible.name: text
  Accessible.onPressAction: clicked()
  activeFocusOnTab: true
  Keys.onReturnPressed: clicked()
  Keys.onSpacePressed: clicked()
  Text {
    id: label
    anchors.centerIn: parent
    text: button.text
    textFormat: Text.PlainText
    color: button.foreground
    font.family: button.fontFamily
    font.pixelSize: button.pixelSize
  }
  MouseArea {
    id: pointer
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: button.clicked()
  }
}
