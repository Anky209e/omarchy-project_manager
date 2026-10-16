import QtQuick
import QtTest
import "../.." as Plugin

Item {
  width: 900
  height: 640

  QtObject {
    id: runner
    property string state: "failed"
    property bool busy: false
    property string projectPath: "/tmp/smoke"
    property string projectName: "Smoke project"
    property string label: "Test task"
    property string command: "echo hello"
    property string output: "hello\nfailure\n"
    property bool truncated: false
    property int exitCode: 7
    property double startedAt: 1000
    property double finishedAt: 2000
    function cancel() { state = "cancelled"; busy = false }
    function rerun() { state = "running"; busy = true }
  }
  Plugin.TaskConsole {
    id: taskView
    anchors.fill: parent
    runner: runner
    visible: false
  }
  Plugin.ActionMenu {
    id: menu
    width: 400
    height: 600
    actions: [
      {label: "Open editor", group: "Open", enabled: true, hint: "Enter"},
      {label: "Open remote", group: "Git", enabled: false, disabledReason: "No remote"},
      {label: "Run tests", group: "Tasks", enabled: true, hint: "Ctrl 1"}
    ]
  }

  SignalSpy { id: activated; target: menu; signalName: "actionRequested" }
  SignalSpy { id: copied; target: taskView; signalName: "copyRequested" }

  TestCase {
    name: "OverlayComponents"
    when: windowShown

    function cleanup() {
      runner.state = "failed"
      runner.busy = false
      activated.clear()
      copied.clear()
      menu.visible = true
      taskView.visible = false
    }

    function test_grouped_actions_and_disabled_rows() {
      compare(menu.count, 3)
      tryVerify(function () { return menu.itemAtIndex(1) !== null })
      mouseClick(menu.itemAtIndex(0))
      compare(activated.count, 1)
      compare(activated.signalArguments[0][0], 0)
      mouseClick(menu.itemAtIndex(1))
      compare(activated.count, 1)
      mouseClick(menu.itemAtIndex(2))
      compare(activated.count, 2)
      compare(activated.signalArguments[1][0], 2)
    }

    function test_output_copy_rerun_and_stop_buttons() {
      menu.visible = false
      taskView.visible = true
      var output = findChild(taskView, "taskOutput")
      verify(output !== null)
      verify(output.text.indexOf("failure") >= 0)
      mouseClick(findChild(taskView, "copyOutputButton"))
      compare(copied.count, 1)
      compare(copied.signalArguments[0][0], runner.output)
      mouseClick(findChild(taskView, "retryButton"))
      compare(runner.state, "running")
      mouseClick(findChild(taskView, "cancelButton"))
      compare(runner.state, "cancelled")
    }
  }
}
