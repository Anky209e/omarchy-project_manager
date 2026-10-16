import QtQuick
import QtQuick.Controls

Item {
  id: taskView
  required property var runner
  property color foreground: "#eeeeee"
  property color background: "#161b22"
  property color accent: "#88aaff"
  property color urgent: "#ff7777"
  property string fontFamily: "sans-serif"
  property int bodySize: 14
  property int captionSize: 12
  property int spacing: 12
  property int cornerRadius: 6
  property bool followOutput: true
  property bool canCopy: true
  readonly property var flickable: scroll.contentItem
  signal backRequested()
  signal copyRequested(string text)

  Column {
    anchors.fill: parent
    spacing: taskView.spacing
    Row {
      width: parent.width
      spacing: taskView.spacing
      Column {
        width: Math.max(0, parent.width - backButton.width - parent.spacing)
        spacing: 4
        Text {
          width: parent.width
          text: taskView.runner.label || "Task output"
          textFormat: Text.PlainText
          color: taskView.foreground
          font.family: taskView.fontFamily
          font.pixelSize: taskView.bodySize + 3
          font.bold: true
          elide: Text.ElideRight
        }
        Text {
          width: parent.width
          text: taskView.runner.projectName + "  ·  " + taskView.runner.projectPath
          textFormat: Text.PlainText
          color: taskView.foreground
          opacity: 0.6
          font.family: taskView.fontFamily
          font.pixelSize: taskView.captionSize
          elide: Text.ElideMiddle
        }
      }
      OverlayButton {
        id: backButton
        objectName: "backButton"
        text: "Back · Esc"
        foreground: taskView.foreground; accent: taskView.accent
        fontFamily: taskView.fontFamily; pixelSize: taskView.captionSize
        radius: taskView.cornerRadius
        onClicked: taskView.backRequested()
      }
    }
    Text {
      width: parent.width
      text: "$ " + taskView.runner.command
      textFormat: Text.PlainText
      color: taskView.foreground
      opacity: 0.7
      font.family: "monospace"
      font.pixelSize: taskView.captionSize
      elide: Text.ElideRight
    }
    Row {
      width: parent.width
      spacing: taskView.spacing
      Text {
        width: Math.max(0, parent.width - cancelButton.width - retryButton.width - copyButton.width - parent.spacing * 3)
        anchors.verticalCenter: parent.verticalCenter
        text: {
          var state = taskView.runner.state
          if (state === "running") return "● Running"
          if (state === "cancelling") return "Stopping task…"
          if (state === "cancelled") return "Cancelled"
          if (state === "idle") return "No task yet"
          var seconds = Math.max(0, (taskView.runner.finishedAt - taskView.runner.startedAt) / 1000).toFixed(1)
          return (state === "succeeded" ? "Completed" : "Failed") + " · exit " + taskView.runner.exitCode + " · " + seconds + "s"
        }
        color: taskView.runner.state === "failed" ? taskView.urgent : taskView.accent
        font.family: taskView.fontFamily
        font.pixelSize: taskView.captionSize
        elide: Text.ElideRight
      }
      OverlayButton {
        id: cancelButton
        objectName: "cancelButton"
        text: "Stop · Ctrl X"
        enabled: taskView.runner.state === "running"
        foreground: taskView.foreground; accent: taskView.urgent
        fontFamily: taskView.fontFamily; pixelSize: taskView.captionSize
        radius: taskView.cornerRadius
        onClicked: taskView.runner.cancel()
      }
      OverlayButton {
        id: retryButton
        objectName: "retryButton"
        text: "Rerun · Ctrl Enter"
        enabled: !taskView.runner.busy && taskView.runner.command.length > 0
        foreground: taskView.foreground; accent: taskView.accent
        fontFamily: taskView.fontFamily; pixelSize: taskView.captionSize
        radius: taskView.cornerRadius
        onClicked: { taskView.followOutput = true; taskView.runner.rerun() }
      }
      OverlayButton {
        id: copyButton
        objectName: "copyOutputButton"
        text: "Copy output"
        enabled: taskView.canCopy && taskView.runner.output.length > 0
        foreground: taskView.foreground; accent: taskView.accent
        fontFamily: taskView.fontFamily; pixelSize: taskView.captionSize
        radius: taskView.cornerRadius
        onClicked: taskView.copyRequested(taskView.runner.output)
      }
    }
    Rectangle {
      width: parent.width
      height: Math.max(0, parent.height - y)
      radius: taskView.cornerRadius
      color: Qt.rgba(taskView.background.r, taskView.background.g, taskView.background.b, 0.85)
      border.color: Qt.rgba(taskView.foreground.r, taskView.foreground.g, taskView.foreground.b, 0.15)
      border.width: 1
      ScrollView {
        id: scroll
        anchors.fill: parent
        anchors.margins: taskView.spacing
        clip: true
        contentWidth: availableWidth
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical: ScrollBar {
          onPressedChanged: { if (pressed) taskView.followOutput = false }
        }
        TextArea {
          id: outputText
          objectName: "taskOutput"
          width: scroll.availableWidth
          text: (taskView.runner.truncated ? "[Earlier output trimmed]\n" : "") + taskView.runner.output
          textFormat: TextEdit.PlainText
          readOnly: true
          selectByMouse: true
          wrapMode: TextEdit.WrapAnywhere
          color: taskView.foreground
          selectionColor: taskView.accent
          selectedTextColor: taskView.background
          font.family: "monospace"
          font.pixelSize: taskView.bodySize
          padding: 0
          background: null
          onSelectedTextChanged: { if (selectedText.length > 0) taskView.followOutput = false }
          onTextChanged: Qt.callLater(function () {
            if (taskView.followOutput) taskView.flickable.contentY = Math.max(0, scroll.contentHeight - scroll.availableHeight)
          })
        }
      }
      // Reading old output disables follow mode; the button restores it.
      Connections {
        target: taskView.flickable
        function onContentYChanged() {
          if (taskView.flickable.moving) taskView.followOutput = taskView.flickable.contentY >= scroll.contentHeight - scroll.availableHeight - 20
        }
      }
      OverlayButton {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: taskView.spacing
        visible: !taskView.followOutput
        text: "Follow output ↓"
        foreground: taskView.foreground; accent: taskView.accent
        fontFamily: taskView.fontFamily; pixelSize: taskView.captionSize
        radius: taskView.cornerRadius
        onClicked: {
          taskView.followOutput = true
          taskView.flickable.contentY = Math.max(0, scroll.contentHeight - scroll.availableHeight)
        }
      }
    }
  }
}
