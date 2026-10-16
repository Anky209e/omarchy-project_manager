pragma ComponentBehavior: Bound
import QtQuick

ListView {
  id: menu
  property var actions: []
  property int selectedIndex: 0
  property bool keyboardActive: false
  property color foreground: "#eeeeee"
  property color selectedBackground: "#334455"
  property color selectedText: "#ffffff"
  property color accent: "#88aaff"
  property string fontFamily: "sans-serif"
  property int bodySize: 14
  property int captionSize: 12
  property int rowHeight: 36
  property int padding: 10
  property int cornerRadius: 6
  signal selectionRequested(int index)
  signal actionRequested(int index)
  clip: true
  spacing: 3
  boundsBehavior: Flickable.StopAtBounds
  model: entries
  section.property: "groupName"
  section.criteria: ViewSection.FullString
  section.delegate: Text {
    required property string section
    width: menu.width
    height: menu.captionSize + menu.padding * 2
    verticalAlignment: Text.AlignVCenter
    text: section.toUpperCase()
    color: menu.accent
    font.family: menu.fontFamily
    font.pixelSize: menu.captionSize
    font.letterSpacing: 1
  }

  function populate() {
    entries.clear()
    for (var i = 0; i < actions.length; i++) {
      var a = actions[i]
      entries.append({title: a.label, shortcut: a.hint || "", groupName: a.group || "Open",
        actionable: a.enabled !== false, reason: a.disabledReason || ""})
    }
  }
  onActionsChanged: populate()
  Component.onCompleted: populate()
  ListModel { id: entries }

  delegate: Rectangle {
    id: row
    required property int index
    required property string title
    required property string shortcut
    required property bool actionable
    required property string reason
    readonly property bool highlighted: menu.keyboardActive && index === menu.selectedIndex
    width: menu.width
    height: menu.rowHeight + (reason ? menu.captionSize + 4 : 0)
    radius: menu.cornerRadius
    color: highlighted ? menu.selectedBackground : (pointer.containsMouse ? Qt.rgba(menu.foreground.r, menu.foreground.g, menu.foreground.b, 0.06) : "transparent")
    Accessible.role: Accessible.Button
    Accessible.name: title + (reason ? ". " + reason : "")
    Accessible.onPressAction: { if (actionable) menu.actionRequested(index) }

    Column {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: menu.padding
      anchors.rightMargin: menu.padding
      anchors.verticalCenter: parent.verticalCenter
      spacing: 3
      Row {
        width: parent.width
        spacing: menu.padding
        Text {
          width: Math.max(0, parent.width - hint.implicitWidth - parent.spacing)
          text: row.title
          textFormat: Text.PlainText
          color: row.highlighted ? menu.selectedText : menu.foreground
          opacity: row.actionable ? 1 : 0.55
          font.family: menu.fontFamily
          font.pixelSize: menu.bodySize
          elide: Text.ElideRight
        }
        Text {
          id: hint
          text: row.shortcut
          color: row.highlighted ? menu.selectedText : menu.foreground
          opacity: 0.55
          font.family: menu.fontFamily
          font.pixelSize: menu.captionSize
        }
      }
      Text {
        width: parent.width
        visible: row.reason.length > 0
        text: row.reason
        textFormat: Text.PlainText
        color: row.highlighted ? menu.selectedText : menu.foreground
        opacity: 0.65
        font.family: menu.fontFamily
        font.pixelSize: menu.captionSize
        elide: Text.ElideRight
      }
    }
    MouseArea {
      id: pointer
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: row.actionable ? Qt.PointingHandCursor : Qt.ArrowCursor
      onPositionChanged: menu.selectionRequested(row.index)
      onClicked: {
        menu.selectionRequested(row.index)
        if (row.actionable) menu.actionRequested(row.index)
      }
    }
  }
}
