pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "ProjectStore.js" as Store

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property string home: Quickshell.env("HOME")
  property bool opened: false
  property var targetScreen: null
  property string filterText: ""
  property int selectedIndex: 0
  property int actionIndex: 0
  property string focusArea: "projects"
  property bool cursorActive: false
  property bool scanning: false
  property bool scannedOnce: false
  property string statusText: ""

  // "list" = normal browse; "prompt" = a single-line text prompt (new project /
  // clone repository).
  property string mode: "list"
  property string promptTitle: ""
  property string promptText: ""
  property string promptKind: ""

  property var config: Store.defaultConfig()
  property var scanned: []
  property var projects: []
  property var displayProjects: []
  property var actions: []
  property var usage: ({})
  property var availableCommands: []
  property var preferences: ({version: 1, projects: {}})
  property bool stateReady: false
  property bool preferencesLoaded: false

  readonly property string scriptPath: {
    var u = Qt.resolvedUrl("project-manager.sh").toString()
    u = u.replace(/^file:\/\//, "")
    try { u = decodeURIComponent(u) } catch (e) {}
    return u
  }
  readonly property string tmuxScriptPath: {
    var u = Qt.resolvedUrl("tmux-session.sh").toString()
    u = u.replace(/^file:\/\//, "")
    try { u = decodeURIComponent(u) } catch (e) {}
    return u
  }
  property string configPath: root.home + "/.config/omarchy/project-manager.json"
  property string stateDir: root.home + "/.local/state/omarchy/project-manager"
  property string usagePath: root.stateDir + "/usage.json"
  property string preferencesPath: root.stateDir + "/preferences.json"

  // Shares the [menu] surface tokens, so themes that style the menu also style
  // this overlay.
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, root.sp(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  property color accent: Color.accent
  property color urgent: Color.urgent
  // Per-monitor scale. The shell's global font tokens are tuned for the bar;
  // on a larger / higher-resolution display the same pixel sizes read much
  // smaller. Scale this overlay by logical screen height (1080p -> 1.0), or by
  // an explicit numeric `scale` in the config file (0 = auto).
  readonly property real uiScale: {
    var s = root.config ? root.config.scale : 0
    if (typeof s === "number" && s > 0) return Math.min(3, s)
    var h = panel.screen ? panel.screen.height : 0
    return h > 0 ? Math.max(1, Math.min(1.6, h / 1080)) : 1
  }
  readonly property int fTitle: Math.max(1, Math.round(Style.font.title * uiScale))
  readonly property int fHeading: Math.max(1, Math.round(Style.font.heading * uiScale))
  readonly property int fBody: Math.max(1, Math.round(Style.font.body * uiScale))
  readonly property int fCaption: Math.max(1, Math.round(Style.font.caption * uiScale))
  readonly property int fDisplay: Math.max(1, Math.round(Style.font.displayLarge * uiScale))
  readonly property int sXs: Math.max(1, Math.round(Style.spacing.xs * uiScale))
  readonly property int sSm: Math.max(1, Math.round(Style.spacing.sm * uiScale))
  readonly property int sMd: Math.max(1, Math.round(Style.spacing.md * uiScale))
  readonly property int sPanelPad: Math.max(1, Math.round(Style.spacing.panelPadding * uiScale))
  readonly property int sControlY: Math.max(1, Math.round(Style.spacing.controlPaddingY * uiScale))

  function sp(px) {
    var v = Number(px) * uiScale * Style.effectiveSpacingScale
    return v <= 0 ? 0 : Math.max(1, Math.round(v))
  }

  property string fontFamily: Style.font.menuFamily
  readonly property int cornerRadius: Math.max(1, Math.round(Style.cornerRadius * uiScale))
  property int contentMargin: root.sPanelPad
  property int headerHeight: Math.max(root.sp(34), root.fTitle + root.sControlY * 2)
  property int contentSpacing: root.sMd
  property int cardWidth: Math.min(root.sp(980), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(root.sp(620), panel.height - Style.gapsOut * 2)
  property int rowHeight: Math.max(root.sp(82), root.fTitle + root.fCaption * 2 + root.sXs * 2 + root.sControlY * 2)
  property int actionRowHeight: Math.max(root.sp(34), root.fBody + root.sControlY * 2)
  property int footerHeight: Math.max(root.sp(18), root.fCaption + root.sp(4))

  readonly property var currentProject: root.projectAt(root.selectedIndex)

  readonly property bool hasLazygitAction: {
    for (var i = 0; i < root.actions.length; i++) {
      if (root.actions[i].id === "git:lazygit") return true
    }
    return false
  }

  function projectAt(index) {
    return (index >= 0 && index < root.displayProjects.length) ? root.displayProjects[index] : null
  }

  function focusedScreen() {
    var screens = Quickshell.screens
    if (!screens || screens.length === 0) return null
    var monitor = Hyprland.focusedMonitor
    var name = monitor ? String(monitor.name || "") : ""
    if (name) {
      for (var i = 0; i < screens.length; i++) {
        if (String(screens[i].name) === name) return screens[i]
      }
    }
    return screens[0]
  }

  function open(payloadJson) {
    root.targetScreen = root.focusedScreen()
    root.opened = true
    root.filterText = ""
    root.selectedIndex = 0
    root.actionIndex = 0
    root.focusArea = "projects"
    root.cursorActive = true
    root.mode = "list"
    root.disarmPointer()

    if (payloadJson) {
      try {
        var payload = JSON.parse(String(payloadJson))
        if (payload && typeof payload.filter === "string") root.filterText = payload.filter
      } catch (e) {}
    }

    root.rebuild(false)
    if (!root.scanning) root.runScan()
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
    root.mode = "list"
    root.promptKind = ""
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open("{}")
  }

  // ------------------------------------------------------------- config/io

  function loadConfig(raw) {
    root.config = Store.normalizeConfig(raw, root.home)
    root.runScan()
  }

  function loadUsage(raw) {
    root.usage = Store.parseUsage(raw)
    root.rebuild()
  }

  function runScan() {
    if (scanProc.running) scanProc.running = false
    scanProc.command = Store.scanArgs(root.config, root.scriptPath, root.home)
    root.scanning = true
    root.statusText = "Scanning projects…"
    scanProc.running = true
  }

  function onScanFinished(raw) {
    var result = Store.parseScan(raw)
    if (!result) {
      root.scanning = false
      root.statusText = "Scan failed"
      return
    }
    root.scanned = result.projects
    root.availableCommands = result.availableCommands
    root.scanning = false
    root.scannedOnce = true
    root.statusText = ""
    root.rebuild()
  }

  // ---------------------------------------------------------------- model

  function rebuild(preserveSelection) {
    var selectedPath = preserveSelection !== false && root.currentProject ? root.currentProject.path : ""
    var merged = Store.mergeProjects(root.scanned, root.config, root.home)
    merged = Store.applyPreferences(merged, root.preferences, root.config, root.availableCommands)
    root.projects = Store.rankProjects(merged, root.usage, Date.now())

    var visible = Store.filterProjects(root.projects, root.filterText)
    root.displayProjects = visible

    displayModel.clear()
    for (var i = 0; i < visible.length; i++) {
      var row = Store.projectRow(visible[i])
      displayModel.append({
        name: row.name,
        path: row.path,
        editorLabel: row.editorLabel,
        icon: row.icon,
        typeLabel: row.typeLabel,
        gitText: row.gitText,
        branch: row.branch,
        dirty: row.dirty,
        hasGit: row.hasGit,
        hasRemote: row.hasRemote,
        pinned: row.pinned,
        projectIndex: i
      })
    }

    if (displayModel.count === 0) {
      root.selectedIndex = 0
    } else if (root.selectedIndex >= displayModel.count) {
      root.selectedIndex = displayModel.count - 1
    } else if (root.selectedIndex < 0) {
      root.selectedIndex = 0
    }

    if (selectedPath) {
      for (var j = 0; j < visible.length; j++) {
        if (visible[j].path === selectedPath) { root.selectedIndex = j; break }
      }
    }
    root.rebuildActions()
    Qt.callLater(function () {
      if (displayModel.count > 0) resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    })
  }

  function rebuildActions() {
    var project = root.currentProject
    if (!project) {
      root.actions = []
      root.actionIndex = 0
      return
    }
    var effective = project.editorId
    root.actions = Store.actionsFor(project, root.config, root.availableCommands, effective)
    if (root.actionIndex >= root.actions.length) root.actionIndex = Math.max(0, root.actions.length - 1)
    if (root.actionIndex < 0) root.actionIndex = 0
  }

  // ------------------------------------------------------------ navigation

  function select(delta) {
    if (displayModel.count === 0) return
    root.disarmPointer()
    root.focusArea = "projects"
    if (!cursorActive) {
      cursorActive = true
      selectedIndex = delta < 0 ? displayModel.count - 1 : 0
    } else {
      selectedIndex = (selectedIndex + delta + displayModel.count) % displayModel.count
    }
    root.rebuildActions()
    resultList.positionViewAtIndex(selectedIndex, ListView.Contain)
  }

  function selectAbsolute(index) {
    if (displayModel.count === 0) return
    root.disarmPointer()
    root.focusArea = "projects"
    root.cursorActive = true
    root.selectedIndex = Math.max(0, Math.min(index, displayModel.count - 1))
    root.rebuildActions()
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function selectAction(delta) {
    if (root.actions.length === 0) return
    root.focusArea = "actions"
    root.actionIndex = (root.actionIndex + delta + root.actions.length) % root.actions.length
    actionList.positionViewAtIndex(root.actionIndex, ListView.Contain)
  }

  function setFilter(nextFilter) {
    root.filterText = nextFilter
    root.selectedIndex = 0
    root.cursorActive = true
    root.disarmPointer()
    root.rebuild(false)
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }

  function disarmPointer() {
    pointerGate.reset()
  }

  function selectFromPointer(index, item, mouse) {
    if (!pointerGate.moved(item, mouse)) return
    root.cursorActive = true
    root.focusArea = "projects"
    root.selectedIndex = index
    root.rebuildActions()
  }

  // --------------------------------------------------------------- actions

  function runAction(action) {
    if (!action || action.enabled === false) return
    var project = root.currentProject
    if (!project) return

    if (action.kind === "pin") { root.togglePin(); return }
    if (action.kind === "cycle-editor") { root.cycleEditor(); return }
    var command = Store.commandFor(action, project, root.config)
    if (!command) return

    if (command.managed) {
      if (taskRunner.busy) {
        root.statusText = "A task is already running · Stop it before starting another"
      } else {
        taskConsole.followOutput = true
        taskRunner.start(command.managed)
        root.recordUsage(project.path)
      }
      root.mode = "output"
      return
    }
    root.recordUsage(project.path)
    root.opened = false
    root.mode = "list"

    if (command.tmux) Quickshell.execDetached(["bash", root.tmuxScriptPath, command.tmux.name, command.tmux.path]
      .concat(command.tmux.command ? [command.tmux.command] : []))
    else if (command.argv) Quickshell.execDetached(command.argv)
    else if (command.shell) Quickshell.execDetached(["bash", "-lc", command.shell])
  }

  // ---------------------------------------------------------------- prompt

  function openPrompt(kind, title) {
    root.mode = "prompt"
    root.promptKind = kind
    root.promptTitle = title
    root.promptText = ""
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }

  function closePrompt() {
    root.mode = "list"
    root.promptKind = ""
    root.promptText = ""
  }

  function acceptPrompt() {
    var kind = root.promptKind
    var value = root.promptText.trim()
    root.closePrompt()
    if (!value) return
    if (projectProc.running) { root.statusText = "A project operation is already running"; return }

    if (kind === "new-project") {
      var created = Store.newProjectCommand(root.config, root.home, value)
      if (!created) { root.statusText = "Invalid project name"; return }
      projectProc.command = created.argv
      root.statusText = "Creating project…"
      projectProc.running = true
    } else if (kind === "clone") {
      var clone = Store.cloneCommand(root.config, root.home, value)
      if (!clone) { root.statusText = "Invalid repository URL"; return }
      projectProc.command = clone.argv
      root.statusText = "Cloning repository…"
      projectProc.running = true
    }
  }

  function runFirstAction() {
    if (root.actions.length > 0) root.runAction(root.actions[0])
  }

  function runActionOfKind(kind) {
    for (var i = 0; i < root.actions.length; i++) {
      if (root.actions[i].kind === kind && root.actions[i].enabled !== false) {
        root.runAction(root.actions[i])
        return
      }
    }
  }

  function runActionById(id) {
    for (var i = 0; i < root.actions.length; i++) {
      if (root.actions[i].id === id && root.actions[i].enabled !== false) {
        root.runAction(root.actions[i])
        return
      }
    }
  }

  function runTaskByIndex(n) {
    var count = 0
    for (var i = 0; i < root.actions.length; i++) {
      if (root.actions[i].kind === "task") {
        if (count === n) { root.runAction(root.actions[i]); return }
        count++
      }
    }
  }

  function activateIndex(index) {
    if (index < 0 || index >= displayModel.count) return
    root.selectedIndex = index
    root.rebuildActions()
    root.runFirstAction()
  }

  function recordUsage(path) {
    root.usage = Store.recordUsage(root.usage, path, Date.now())
    usageFile.setText(JSON.stringify(root.usage, null, 2) + "\n")
  }

  function savePreference(path, field, value) {
    if (!root.stateReady || !root.preferencesLoaded) {
      root.statusText = "Preferences are not ready yet"
      return
    }
    root.preferences = Store.updatePreference(root.preferences, path, field, value)
    preferencesFile.setText(JSON.stringify(root.preferences, null, 2) + "\n")
    root.rebuild()
  }

  function togglePin() {
    var project = root.currentProject
    if (project) root.savePreference(project.path, "pinned", !project.pinned)
  }

  function cycleEditor() {
    var project = root.currentProject
    if (!project) return
    var ids = Store.availableEditors(root.config, root.availableCommands)
    if (ids.length === 0) return
    var index = ids.indexOf(project.editorId)
    root.savePreference(project.path, "editor", ids[(index + 1) % ids.length])
  }

  Component.onCompleted: initProc.running = true

  ListModel { id: displayModel }

  PointerMoveGate {
    id: pointerGate
    referenceItem: card
  }

  // Make sure the state directory exists before the usage file is written.
  Process {
    id: initProc
    command: ["mkdir", "-p", root.stateDir]
    onExited: function (code) {
      root.stateReady = code === 0
      if (code !== 0) root.statusText = "Cannot create preferences directory"
    }
  }

  FileView {
    id: preferencesFile
    path: root.stateReady ? root.preferencesPath : ""
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: {
      root.preferences = Store.parsePreferences(text())
      root.preferencesLoaded = true
      root.rebuild()
    }
    onLoadFailed: {
      if (root.stateReady) {
        root.preferences = Store.parsePreferences("")
        root.preferencesLoaded = true
        root.rebuild()
      }
    }
    onSaveFailed: root.statusText = "Could not save project preferences"
    onFileChanged: reload()
  }

  TaskRunner {
    id: taskRunner
    onFinished: { if (!root.scanning) root.runScan() }
  }

  Process {
    id: copyProc
    stdinEnabled: true
    command: ["wl-copy"]
    onStarted: { copyProc.write(taskRunner.output); copyProc.stdinEnabled = false }
  }

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    printErrors: false
    onLoaded: root.loadConfig(text())
    onLoadFailed: root.loadConfig("")
    onFileChanged: reload()
  }

  FileView {
    id: usageFile
    path: root.usagePath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadUsage(text())
    onLoadFailed: root.loadUsage("{}")
    onFileChanged: reload()
  }

  Process {
    id: scanProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.onScanFinished(text)
    }
    stderr: SplitParser {
      onRead: function (line) { console.log("project-manager: " + line) }
    }
    onExited: root.scanning = false
  }

  Process {
    id: projectProc
    property string errorOutput: ""
    onStarted: errorOutput = ""
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: projectProc.errorOutput = text.trim()
    }
    onExited: function (exitCode, exitStatus) {
      if (exitCode === 0 && exitStatus === 0) root.runScan()
      else root.statusText = projectProc.errorOutput || "Project operation failed"
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    screen: root.targetScreen
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-project-manager"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function (event) {
          var ctrlMod = event.modifiers & Qt.ControlModifier
          var altMod = event.modifiers & Qt.AltModifier
          var metaMod = event.modifiers & Qt.MetaModifier

          if (root.mode === "prompt") {
            if (event.key === Qt.Key_Escape) {
              root.closePrompt()
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.acceptPrompt()
            } else if (event.key === Qt.Key_Backspace) {
              root.promptText = root.promptText.slice(0, -1)
            } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32
                       && event.text.charCodeAt(0) !== 127 && !(ctrlMod || altMod || metaMod)) {
              root.promptText = root.promptText + event.text
            }
            event.accepted = true
            return
          }

          if (root.mode === "output") {
            if (event.key === Qt.Key_Escape || (ctrlMod && event.key === Qt.Key_O)) {
              root.mode = "list"
              keyCatcher.forceActiveFocus()
            } else if (ctrlMod && event.key === Qt.Key_X) taskRunner.cancel()
            else if (ctrlMod && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
              taskConsole.followOutput = true
              taskRunner.rerun()
            } else return
            event.accepted = true
            return
          }
          if (ctrlMod && event.key === Qt.Key_O) {
            if (taskRunner.state !== "idle") root.mode = "output"
            event.accepted = true
            return
          }
          if (ctrlMod && event.key === Qt.Key_P) {
            root.togglePin()
            event.accepted = true
            return
          }

          if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else if (root.focusArea === "actions") { root.focusArea = "projects"; root.actionIndex = 0 }
            else root.close()
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Right) {
            if (root.actions.length > 0) root.focusArea = "actions"
            event.accepted = true
          } else if (event.key === Qt.Key_Backtab || event.key === Qt.Key_Left) {
            root.focusArea = "projects"
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            if (root.focusArea === "actions") root.selectAction(-1)
            else root.select(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            if (root.focusArea === "actions") root.selectAction(1)
            else root.select(1)
            event.accepted = true
          } else if (event.key === Qt.Key_PageUp) {
            if (root.focusArea === "actions") root.selectAction(-3)
            else root.select(-6)
            event.accepted = true
          } else if (event.key === Qt.Key_PageDown) {
            if (root.focusArea === "actions") root.selectAction(3)
            else root.select(6)
            event.accepted = true
          } else if (event.key === Qt.Key_Home) {
            if (root.focusArea === "actions") { root.actionIndex = 0; actionList.positionViewAtIndex(0, ListView.Beginning) }
            else root.selectAbsolute(0)
            event.accepted = true
          } else if (event.key === Qt.Key_End) {
            if (root.focusArea === "actions") { root.actionIndex = root.actions.length - 1; actionList.positionViewAtIndex(root.actionIndex, ListView.End) }
            else root.selectAbsolute(displayModel.count - 1)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            var ctrl = event.modifiers & Qt.ControlModifier
            var shift = event.modifiers & Qt.ShiftModifier
            var alt = event.modifiers & Qt.AltModifier
            if (ctrl) root.runActionOfKind("github")
            else if (shift) root.runActionOfKind("terminal")
            else if (alt) root.runActionOfKind("files")
            else if (root.focusArea === "actions") root.runAction(root.actions[root.actionIndex])
            else root.runFirstAction()
            event.accepted = true
          } else if (event.key === Qt.Key_R && (event.modifiers & Qt.ControlModifier)) {
            root.runScan()
            event.accepted = true
          } else if (event.key === Qt.Key_N && (event.modifiers & Qt.ControlModifier)) {
            root.openPrompt("new-project", "New project name")
            event.accepted = true
          } else if (event.key === Qt.Key_L && (event.modifiers & Qt.ControlModifier)) {
            root.openPrompt("clone", "Clone repository URL")
            event.accepted = true
          } else if (event.key === Qt.Key_G && (event.modifiers & Qt.ControlModifier)
                     && (event.modifiers & Qt.ShiftModifier)) {
            root.runActionById("git:lazygit")
            event.accepted = true
          } else if (event.key === Qt.Key_G && (event.modifiers & Qt.ControlModifier)) {
            root.runActionOfKind("github")
            event.accepted = true
          } else if (event.key === Qt.Key_Y && (event.modifiers & Qt.ControlModifier)) {
            root.runActionOfKind("copy")
            event.accepted = true
          } else if (event.key === Qt.Key_T && (event.modifiers & Qt.ControlModifier)) {
            root.runActionOfKind("terminal-tmux")
            event.accepted = true
          } else if (event.key === Qt.Key_E && (event.modifiers & Qt.ControlModifier)) {
            root.cycleEditor()
            event.accepted = true
          } else if ((event.modifiers & Qt.ControlModifier)
                     && event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
            root.runTaskByIndex(event.key - Qt.Key_1)
            event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32
                     && event.text.charCodeAt(0) !== 127 && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing

        // ------------------------------------------------------------ header
        Rectangle {
          width: parent.width
          height: root.headerHeight
          color: "transparent"

          Text {
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.right: statusLabel.left
            anchors.rightMargin: root.sp(12)
            anchors.verticalCenter: parent.verticalCenter
            text: root.mode === "output" ? "Task output" : (root.filterText || "Search projects…")
            color: root.foreground
            opacity: root.filterText ? 1 : 0.58
            font.family: root.fontFamily
            font.pixelSize: root.fHeading
            elide: Text.ElideRight
          }

          Text {
            id: statusLabel
            textFormat: Text.PlainText
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, parent.width * 0.48)
            elide: Text.ElideRight
            text: taskRunner.busy ? "● Task running · Ctrl O output"
              : (root.statusText.length > 0 ? root.statusText
                : (displayModel.count + " / " + root.projects.length + " projects"))
            color: root.foreground
            opacity: 0.5
            font.family: root.fontFamily
            font.pixelSize: root.fCaption
            MouseArea {
              anchors.fill: parent
              enabled: taskRunner.state !== "idle"
              cursorShape: Qt.PointingHandCursor
              onClicked: root.mode = "output"
            }
          }
        }

        Item {
          width: parent.width
          height: parent.height - root.headerHeight - root.footerHeight - root.contentSpacing * 2

          TaskConsole {
            id: taskConsole
            anchors.fill: parent
            visible: root.mode === "output"
            runner: taskRunner
            canCopy: Store.commandAvailable("wl-copy", root.availableCommands)
            foreground: root.foreground; background: root.background
            accent: root.accent; urgent: root.urgent
            fontFamily: root.fontFamily
            bodySize: root.fBody; captionSize: root.fCaption
            spacing: root.sMd; cornerRadius: root.cornerRadius
            onBackRequested: { root.mode = "list"; keyCatcher.forceActiveFocus() }
            onCopyRequested: function (text) {
              if (!Store.commandAvailable("wl-copy", root.availableCommands)) {
                root.statusText = "Missing: wl-copy"
                return
              }
              if (copyProc.running) return
              copyProc.stdinEnabled = true
              copyProc.running = true
            }
          }

          Row {
            anchors.fill: parent
            visible: root.mode !== "output"
            spacing: 0

            // ------------------------------------------------------- projects
            Item {
              width: parent.width * 0.5
              height: parent.height
              clip: true

              ListView {
                id: resultList
                anchors.fill: parent
                anchors.rightMargin: root.contentMargin
                model: displayModel
                clip: true
                spacing: root.sp(4)
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                  id: row
                  required property int index
                  required property string name
                  required property string path
                  required property string editorLabel
                  required property string icon
                  required property string typeLabel
                  required property string gitText
                  required property bool dirty
                  required property bool hasGit
                  required property bool pinned
                  required property int projectIndex

                  readonly property bool hasCursor: root.cursorActive
                    && root.focusArea === "projects" && index === root.selectedIndex

                  width: ListView.view.width
                  height: root.rowHeight
                  radius: root.cornerRadius
                  color: hasCursor ? root.selectedBackground : "transparent"

                  Row {
                    anchors.fill: parent
                    anchors.margins: root.sp(10)
                    spacing: root.sp(10)
                    Text {
                      id: rowIcon
                      anchors.verticalCenter: parent.verticalCenter
                      text: row.icon || "\uf07b"
                      color: row.hasCursor ? root.selectedText : root.accent
                      font.family: root.fontFamily
                      font.pixelSize: root.fHeading
                    }
                    Column {
                      width: Math.max(0, parent.width - rowIcon.width - pinButton.width - parent.spacing * 2)
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: root.sp(4)
                      Text {
                        width: parent.width
                        textFormat: Text.StyledText
                        text: Store.highlightHtml(row.name, root.filterText)
                        color: row.hasCursor ? root.selectedText : root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: root.fTitle
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                      }
                      Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        text: row.path.indexOf(root.home + "/") === 0 ? "~" + row.path.slice(root.home.length) : row.path
                        color: row.hasCursor ? root.selectedText : root.foreground
                        opacity: 0.55
                        font.family: root.fontFamily
                        font.pixelSize: root.fCaption
                        elide: Text.ElideMiddle
                      }
                      Row {
                        width: parent.width
                        spacing: root.sp(6)
                        Rectangle {
                          visible: row.hasGit
                          width: Math.min(parent.width * 0.64, branchLabel.implicitWidth + root.sp(12))
                          height: root.fCaption + root.sp(5)
                          radius: root.sp(3)
                          color: Util.alpha(row.dirty ? root.urgent : root.accent, 0.12)
                          Text {
                            id: branchLabel
                            anchors.fill: parent
                            anchors.leftMargin: root.sp(6)
                            anchors.rightMargin: root.sp(6)
                            verticalAlignment: Text.AlignVCenter
                            text: "\uf126 " + row.gitText
                            color: row.hasCursor ? root.selectedText : (row.dirty ? root.urgent : root.accent)
                            font.family: root.fontFamily
                            font.pixelSize: root.fCaption
                            elide: Text.ElideRight
                          }
                        }
                        Text {
                          width: Math.max(0, parent.width - (row.hasGit ? parent.children[0].width + parent.spacing : 0))
                          anchors.verticalCenter: parent.verticalCenter
                          text: row.typeLabel || row.editorLabel
                          color: row.hasCursor ? root.selectedText : root.foreground
                          opacity: 0.55
                          font.family: root.fontFamily
                          font.pixelSize: root.fCaption
                          elide: Text.ElideRight
                        }
                      }
                    }
                    Item { width: pinButton.width; height: 1 }
                  }

                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPositionChanged: function (mouse) {
                      root.selectFromPointer(row.index, row, mouse)
                    }
                    onClicked: {
                      root.cursorActive = true
                      root.focusArea = "projects"
                      root.selectedIndex = row.index
                      root.rebuildActions()
                    }
                    onDoubleClicked: root.activateIndex(row.index)
                  }
                  OverlayButton {
                    id: pinButton
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.rightMargin: root.sp(8)
                    text: "\uf08d"
                    foreground: row.hasCursor ? root.selectedText : root.accent
                    accent: root.accent
                    fontFamily: root.fontFamily; pixelSize: root.fCaption
                    padding: root.sp(6); radius: root.sp(4)
                    opacity: row.pinned ? 1 : 0.3
                    Accessible.name: row.pinned ? "Unpin " + row.name : "Pin " + row.name
                    enabled: root.preferencesLoaded
                    onClicked: {
                      root.selectedIndex = row.index
                      root.togglePin()
                    }
                  }

                }
              }

              Column {
                anchors.centerIn: parent
                width: Math.max(0, parent.width - root.contentMargin * 2)
                spacing: root.sp(12)
                visible: displayModel.count === 0

                Text {
                  text: "󰉋"
                  color: root.selectedText
                  opacity: 0.8
                  font.family: root.fontFamily
                  font.pixelSize: root.fDisplay
                  horizontalAlignment: Text.AlignHCenter
                  width: parent.width
                }

                Text {
                  textFormat: Text.PlainText
                  text: root.filterText
                    ? "No matches for “" + root.filterText + "”"
                    : (root.scanning ? "Scanning…" : "No projects found")
                  color: root.foreground
                  opacity: 0.7
                  font.family: root.fontFamily
                  font.pixelSize: root.fTitle
                  horizontalAlignment: Text.AlignHCenter
                  width: parent.width
                }
                Text {
                  width: parent.width
                  text: root.filterText ? "Try another name, path, tag, or branch." : "Clone a repository or create your first project."
                  textFormat: Text.PlainText
                  color: root.foreground
                  opacity: 0.5
                  font.family: root.fontFamily
                  font.pixelSize: root.fCaption
                  wrapMode: Text.Wrap
                  horizontalAlignment: Text.AlignHCenter
                }
                Row {
                  anchors.horizontalCenter: parent.horizontalCenter
                  spacing: root.sp(8)
                  OverlayButton {
                    text: root.filterText ? "Clear search" : "New project"
                    foreground: root.foreground; accent: root.accent
                    fontFamily: root.fontFamily; pixelSize: root.fCaption
                    radius: root.cornerRadius
                    onClicked: {
                      if (root.filterText) root.setFilter("")
                      else root.openPrompt("new-project", "New project name")
                    }
                  }
                  OverlayButton {
                    text: "Rescan"
                    foreground: root.foreground; accent: root.accent
                    fontFamily: root.fontFamily; pixelSize: root.fCaption
                    radius: root.cornerRadius
                    onClicked: root.runScan()
                  }
                }
              }
            }

            // -------------------------------------------------- detail/actions
            Item {
              width: parent.width * 0.5
              height: parent.height
              clip: true

              Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: Style.normalBorderWidth
                color: Util.alpha(root.border, 0.28)
              }

              Column {
                anchors.fill: parent
                anchors.leftMargin: root.contentMargin
                anchors.rightMargin: root.contentMargin
                spacing: root.sSm
                visible: root.currentProject !== null || root.mode === "prompt"

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  text: root.mode === "prompt"
                    ? root.promptTitle
                    : (root.currentProject ? root.currentProject.name : "")
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: root.fHeading
                  elide: Text.ElideRight
                }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  visible: root.mode === "list"
                  text: root.currentProject ? root.currentProject.path : ""
                  color: root.foreground
                  opacity: 0.6
                  font.family: root.fontFamily
                  font.pixelSize: root.fCaption
                  elide: Text.ElideMiddle
                }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  visible: root.mode === "list" && root.currentProject && root.currentProject.git
                  text: root.currentProject && root.currentProject.git
                    ? "\uf126  " + Store.gitSummary(root.currentProject.git)
                    : ""
                  color: root.currentProject && root.currentProject.git && root.currentProject.git.dirty
                    ? root.urgent : root.foreground
                  opacity: 0.85
                  font.family: root.fontFamily
                  font.pixelSize: root.fBody
                  elide: Text.ElideRight
                }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  visible: root.mode === "list" && root.currentProject && root.currentProject.tags.length > 0
                  text: root.currentProject ? root.currentProject.tags.join("  ·  ") : ""
                  color: root.foreground
                  opacity: 0.55
                  font.family: root.fontFamily
                  font.pixelSize: root.fCaption
                  elide: Text.ElideRight
                }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  visible: root.mode === "list" && root.currentProject !== null
                  text: {
                    if (!root.currentProject) return ""
                    var parts = []
                    var tl = Store.typeLabel(root.currentProject.types)
                    if (tl) parts.push(tl)
                    if (root.currentProject.editorLabel) parts.push(root.currentProject.editorLabel)
                    return parts.join("  ·  ")
                  }
                  color: root.foreground
                  opacity: 0.45
                  font.family: root.fontFamily
                  font.pixelSize: root.fCaption
                  elide: Text.ElideRight
                }

                Item { width: 1; height: root.sSm }

                ActionMenu {
                  id: actionList
                  width: parent.width
                  height: Math.max(0, parent.height - y)
                  visible: root.mode === "list"
                  actions: root.actions
                  selectedIndex: root.actionIndex
                  keyboardActive: root.focusArea === "actions"
                  foreground: root.foreground; accent: root.accent
                  selectedBackground: root.selectedBackground; selectedText: root.selectedText
                  fontFamily: root.fontFamily
                  bodySize: root.fBody; captionSize: root.fCaption
                  rowHeight: root.actionRowHeight; padding: root.sp(10)
                  cornerRadius: root.cornerRadius
                  onSelectionRequested: function (index) {
                    root.focusArea = "actions"
                    root.actionIndex = index
                  }
                  onActionRequested: function (index) { root.runAction(root.actions[index]) }
                }

                Item {
                  width: parent.width
                  height: Math.max(0, parent.height - y - root.sp(22))
                  visible: root.mode === "prompt"

                  Rectangle {
                    id: promptBox
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    height: root.actionRowHeight
                    radius: root.cornerRadius
                    color: Util.alpha(root.foreground, 0.08)
                    border.width: Style.normalBorderWidth
                    border.color: Util.alpha(root.border, 0.5)

                    Text {
                      textFormat: Text.PlainText
                      anchors.left: parent.left
                      anchors.leftMargin: root.sp(10)
                      anchors.right: parent.right
                      anchors.rightMargin: root.sp(10)
                      anchors.verticalCenter: parent.verticalCenter
                      text: root.promptText.length > 0 ? root.promptText : "Type and press Enter…"
                      color: root.foreground
                      opacity: root.promptText.length > 0 ? 1 : 0.4
                      font.family: root.fontFamily
                      font.pixelSize: root.fBody
                      elide: Text.ElideRight
                    }
                  }
                }
              }
            }
          }
        }

        // ------------------------------------------------------------ footer
        Text {
          id: footer
          textFormat: Text.PlainText
          width: parent.width
          height: root.footerHeight
          verticalAlignment: Text.AlignVCenter
          text: {
            if (root.mode === "prompt") return "Enter confirm  ·  Esc cancel"
            if (root.mode === "output") return "Ctrl X stop task  ·  Ctrl Enter rerun  ·  Esc back to projects · Tasks keep running when closed"
            if (root.focusArea === "actions") {
              var s = "\u2191\u2193 move  ·  Enter run"
              if (root.hasLazygitAction) s += "  ·  Ctrl \u21e7G lazygit"
              s += "  ·  Ctrl P pin  ·  Ctrl E editor  ·  \u2190 project list  ·  Esc close"
              return s
            }
            return "type to search  ·  \u2191\u2193 move  ·  Enter open  ·  \u21e7Enter terminal  ·  Ctrl T tmux  ·  \u2325Enter files  ·  \u2192 actions  ·  Ctrl P pin  ·  Ctrl E editor  ·  Ctrl O output"
          }
          color: root.foreground
          opacity: 0.45
          font.family: root.fontFamily
          font.pixelSize: root.fCaption
          elide: Text.ElideRight
        }
      }
    }
  }
}
