import QtQuick
import QtQuick.Window
import Quickshell
import "plugin" as Plugin

ShellRoot {
  id: harness
  property int stage: 0
  property int ticks: 0
  property string chosenEditor: ""
  property var restored: null
  property var runner: null
  property bool waitingForCapture: false

  function require(condition, message) {
    if (!condition) throw new Error(message)
  }
  function find(object, name) {
    if (object.objectName === name) return object
    var children = object.children || []
    for (var i = 0; i < children.length; i++) {
      var result = find(children[i], name)
      if (result) return result
    }
    return null
  }
  function capture(name) {
    waitingForCapture = true
    window.contentItem.grabToImage(function(result) {
      result.saveToFile(Qt.resolvedUrl(name + ".png").toString().replace(/^file:\/\//, ""))
      waitingForCapture = false
    })
  }

  Window {
    id: window
    width: 1200
    height: 800
    visible: true
    color: "#101315"
    Plugin.ProjectManager { id: overlay; anchors.fill: parent }
  }
  Component { id: instance; Plugin.ProjectManager { anchors.fill: parent } }
  Timer {
    interval: 80
    repeat: true
    running: true
    onTriggered: {
      try {
        if (harness.waitingForCapture) return
        if (++harness.ticks > 150) throw new Error("Smoke test timed out at stage " + harness.stage)
        switch (harness.stage) {
        case 0:
          if (!overlay.preferencesLoaded || !overlay.scannedOnce) return
          overlay.open("{}")
          harness.require(overlay.currentProject !== null, "No project discovered")
          overlay.togglePin()
          overlay.cycleEditor()
          harness.chosenEditor = overlay.currentProject.editorId
          harness.require(overlay.currentProject.pinned, "Pin did not update")
          harness.stage = 1
          return
        case 1:
          // Allow the atomic preference write to finish before creating a new instance.
          harness.restored = instance.createObject(window.contentItem)
          overlay.close()
          harness.stage = 2
          return
        case 2:
          if (!harness.restored.preferencesLoaded || !harness.restored.scannedOnce) return
          harness.restored.open("{}")
          harness.require(harness.restored.currentProject.pinned, "Pin did not persist")
          harness.require(harness.restored.currentProject.editorId === harness.chosenEditor, "Editor did not persist")
          harness.runner = harness.find(harness.restored, "taskRunner")
          harness.require(harness.runner !== null, "Task runner missing")
          harness.capture("projects")
          harness.stage = 3
          return
        case 3:
          harness.restored.runAction({kind: "task", label: "Smoke task", command: "echo hello; echo stderr >&2; exit 7", enabled: true})
          harness.require(harness.restored.mode === "output", "Task console did not open")
          harness.stage = 4
          return
        case 4:
          if (harness.runner.busy) return
          harness.require(harness.runner.state === "failed" && harness.runner.exitCode === 7, "Exit code not captured")
          harness.require(harness.runner.output.indexOf("hello") >= 0 && harness.runner.output.indexOf("stderr") >= 0, "Task output missing")
          harness.capture("task-output")
          harness.stage = 5
          return
        case 5:
          harness.runner.rerun()
          harness.stage = 6
          return
        case 6:
          if (harness.runner.busy) return
          harness.require(harness.runner.exitCode === 7, "Rerun failed")
          harness.restored.runAction({kind: "task", label: "Long task", command: "sleep 30 & echo ready; wait", enabled: true})
          harness.stage = 7
          return
        case 7:
          if (harness.runner.output.indexOf("ready") < 0) return
          var runningCommand = harness.runner.command
          harness.restored.close()
          harness.require(harness.runner.busy, "Closing the overlay stopped the task")
          harness.restored.open("{}")
          harness.restored.runAction({kind: "task", label: "Other", command: "echo should-not-run", enabled: true})
          harness.require(harness.runner.command === runningCommand, "A second task replaced the running task")
          harness.runner.cancel()
          harness.stage = 8
          return
        case 8:
          if (harness.runner.busy) return
          harness.require(harness.runner.state === "cancelled", "Task cancellation failed")
          harness.runner.output = ""
          harness.runner.pendingOutput = ""
          harness.runner.outputLimit = 100
          harness.runner.append("\x1b[31mred\x1b[0m")
          harness.runner.flush()
          harness.require(harness.runner.output === "red\n", "ANSI cleanup failed")
          harness.runner.append(new Array(200).join("x"))
          harness.runner.flush()
          harness.require(harness.runner.output.length <= 100 && harness.runner.truncated, "Output cap failed")
          harness.runner.outputLimit = 131072
          harness.restored.mode = "list"
          harness.restored.setFilter("no-matching-project")
          harness.require(harness.restored.displayProjects.length === 0, "Empty search failed")
          harness.restored.openPrompt("new-project", "New project name")
          harness.capture("empty-prompt")
          harness.stage = 9
          return
        case 9:
          console.log("SMOKE PASS: overlay creation, preferences restart, output, rerun, cancellation, empty prompt")
          Qt.quit()
        }
      } catch (error) {
        console.log("SMOKE FAIL: " + error)
        Qt.quit()
      }
    }
  }
}
