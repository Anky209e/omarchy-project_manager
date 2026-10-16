import QtQuick
import Quickshell.Io

Item {
  id: runner
  objectName: "taskRunner"
  property string helperPath: decodeURIComponent(Qt.resolvedUrl("task-runner.sh").toString().replace(/^file:\/\//, ""))
  property string state: "idle"
  readonly property bool busy: state === "running" || state === "cancelling"
  property string output: ""
  property string pendingOutput: ""
  property int outputLimit: 131072
  property bool truncated: false
  property string projectPath: ""
  property string projectName: ""
  property string label: ""
  property string command: ""
  property int exitCode: 0
  property double startedAt: 0
  property double finishedAt: 0
  signal finished()

  function append(text) {
    // Display terminal output as plain text, stripping common ANSI sequences.
    var clean = String(text).replace(/\x1b\[[0-?]*[ -/]*[@-~]/g, "").replace(/\r/g, "")
    var pending = pendingOutput + clean + "\n"
    if (pending.length > outputLimit) truncated = true
    pendingOutput = pending.slice(-outputLimit)
    if (!flushTimer.running) flushTimer.start()
  }

  function flush() {
    var combined = output + pendingOutput
    if (combined.length > outputLimit) truncated = true
    output = combined.slice(-outputLimit)
    pendingOutput = ""
  }

  function start(task) {
    if (busy || !task || !task.command) return false
    projectPath = task.path
    projectName = task.projectName || task.path
    label = task.label
    command = task.command
    output = ""
    pendingOutput = ""
    truncated = false
    exitCode = 0
    startedAt = Date.now()
    finishedAt = 0
    state = "running"
    proc.command = ["bash", helperPath, projectPath, command]
    proc.running = true
    return true
  }

  function cancel() {
    if (state !== "running") return
    state = "cancelling"
    proc.signal(15)
  }

  function rerun() {
    if (busy || !command) return false
    return start({path: projectPath, projectName: projectName, label: label, command: command})
  }

  Timer { id: flushTimer; interval: 80; onTriggered: runner.flush() }

  Process {
    id: proc
    stdout: SplitParser { onRead: function (line) { runner.append(line) } }
    stderr: SplitParser { onRead: function (line) { runner.append(line) } }
    onStarted: { if (runner.state === "cancelling") proc.signal(15) }
    onExited: function (code, status) {
      flushTimer.stop()
      runner.flush()
      runner.exitCode = code
      runner.finishedAt = Date.now()
      runner.state = runner.state === "cancelling" ? "cancelled"
        : (code === 0 && status === 0 ? "succeeded" : "failed")
      runner.finished()
    }
  }
}
