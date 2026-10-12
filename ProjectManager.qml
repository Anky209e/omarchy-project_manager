import Quickshell
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
  property string filterText: ""
  property int selectedIndex: 0
  property int actionIndex: 0
  property string focusArea: "projects"
  property bool cursorActive: false
  property bool scanning: false
  property bool scannedOnce: false
  property string statusText: ""

  property var config: Store.defaultConfig()
  property var scanned: []
  property var projects: []
  property var displayProjects: []
  property var actions: []
  property var usage: ({})
  property var availableCommands: []
  property var editorOverrides: ({})

  readonly property string scriptPath: {
    var u = Qt.resolvedUrl("project-manager.sh").toString()
    u = u.replace(/^file:\/\//, "")
    try { u = decodeURIComponent(u) } catch (e) {}
    return u
  }
  property string configPath: root.home + "/.config/omarchy/project-manager.json"
  property string stateDir: root.home + "/.local/state/omarchy/project-manager"
  property string usagePath: root.stateDir + "/usage.json"

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
  property int rowHeight: Math.max(root.sp(56), root.fTitle + root.fCaption + root.sXs + root.sControlY * 2)
  property int actionRowHeight: Math.max(root.sp(34), root.fBody + root.sControlY * 2)

  readonly property var currentProject: root.projectAt(root.selectedIndex)

  function projectAt(index) {
    return (index >= 0 && index < root.displayProjects.length) ? root.displayProjects[index] : null
  }

  function open(payloadJson) {
    root.opened = true
    root.filterText = ""
    root.selectedIndex = 0
    root.actionIndex = 0
    root.focusArea = "projects"
    root.cursorActive = true
    root.disarmPointer()

    if (payloadJson) {
      try {
        var payload = JSON.parse(String(payloadJson))
        if (payload && typeof payload.filter === "string") root.filterText = payload.filter
      } catch (e) {}
    }

    root.rebuild()
    if (!root.scannedOnce && !root.scanning) root.runScan()
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
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

  function rebuild() {
    var merged = Store.mergeProjects(root.scanned, root.config, root.home)
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
    var effective = root.editorOverrides[project.path] || project.editor
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
    root.rebuild()
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

    var command = Store.commandFor(action, project, root.config)
    if (!command) return

    root.recordUsage(project.path)
    root.opened = false

    if (command.argv) Quickshell.execDetached(command.argv)
    else if (command.shell) Quickshell.execDetached(["bash", "-lc", command.shell])
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

  function cycleEditor() {
    var project = root.currentProject
    if (!project) return
    var ids = Store.availableEditors(root.config, root.availableCommands)
    if (ids.length === 0) return
    var current = root.editorOverrides[project.path] || project.editor
    var index = ids.indexOf(current)
    var next = ids[(index + 1) % ids.length]

    var overrides = {}
    for (var k in root.editorOverrides) overrides[k] = root.editorOverrides[k]
    overrides[project.path] = next
    root.editorOverrides = overrides
    root.rebuildActions()
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

  PanelWindow {
    id: panel
    visible: root.opened
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
          } else if (event.key === Qt.Key_G && (event.modifiers & Qt.ControlModifier)) {
            root.runActionOfKind("github")
            event.accepted = true
          } else if (event.key === Qt.Key_Y && (event.modifiers & Qt.ControlModifier)) {
            root.runActionOfKind("copy")
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
            text: root.filterText || "Search projects…"
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
            text: root.statusText.length > 0
              ? root.statusText
              : (displayModel.count + (displayModel.count === 1 ? " project" : " projects"))
            color: root.foreground
            opacity: 0.5
            font.family: root.fontFamily
            font.pixelSize: root.fCaption
          }
        }

        Item {
          width: parent.width
          height: parent.height - root.headerHeight - root.contentSpacing

          Row {
            anchors.fill: parent
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
                    anchors.leftMargin: root.sp(12)
                    anchors.rightMargin: root.sp(12)
                    anchors.topMargin: root.sp(8)
                    anchors.bottomMargin: root.sp(8)
                    spacing: root.sp(10)

                    Text {
                      id: rowIcon
                      textFormat: Text.PlainText
                      anchors.verticalCenter: parent.verticalCenter
                      text: row.pinned ? "\uf08d" : "\uf07b"
                      color: row.hasCursor ? root.selectedText : root.accent
                      opacity: row.hasCursor ? 1 : 0.7
                      font.family: root.fontFamily
                      font.pixelSize: root.fTitle
                    }

                    Column {
                      width: parent.width - rowIcon.width - parent.spacing * 2 - gitInfo.width
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: root.sp(1)

                      Text {
                        textFormat: Text.PlainText
                        width: parent.width
                        text: row.name
                        color: row.hasCursor ? root.selectedText : root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: root.fTitle
                        elide: Text.ElideRight
                      }

                      Text {
                        textFormat: Text.PlainText
                        width: parent.width
                        text: row.path
                        color: root.foreground
                        opacity: 0.55
                        font.family: root.fontFamily
                        font.pixelSize: root.fCaption
                        elide: Text.ElideMiddle
                      }
                    }

                    Column {
                      id: gitInfo
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: root.sp(1)

                      Text {
                        textFormat: Text.PlainText
                        anchors.right: parent.right
                        text: row.gitText
                        color: row.dirty ? root.urgent : root.foreground
                        opacity: row.dirty ? 0.95 : 0.7
                        font.family: root.fontFamily
                        font.pixelSize: root.fCaption
                      }

                      Text {
                        textFormat: Text.PlainText
                        anchors.right: parent.right
                        text: row.editorLabel
                        color: root.foreground
                        opacity: 0.45
                        font.family: root.fontFamily
                        font.pixelSize: root.fCaption
                      }
                    }
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
                }
              }

              Column {
                anchors.centerIn: parent
                spacing: root.sp(8)
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
                visible: root.currentProject !== null

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  text: root.currentProject ? root.currentProject.name : ""
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: root.fHeading
                  elide: Text.ElideRight
                }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
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
                  visible: root.currentProject && root.currentProject.git
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
                  visible: root.currentProject && root.currentProject.tags.length > 0
                  text: root.currentProject ? root.currentProject.tags.join("  ·  ") : ""
                  color: root.foreground
                  opacity: 0.55
                  font.family: root.fontFamily
                  font.pixelSize: root.fCaption
                  elide: Text.ElideRight
                }

                Item { width: 1; height: root.sSm }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  text: "Actions"
                  color: root.foreground
                  opacity: 0.5
                  font.family: root.fontFamily
                  font.pixelSize: root.fCaption
                }

                ListView {
                  id: actionList
                  width: parent.width
                  height: Math.max(0, parent.height - y - root.sp(22))
                  model: root.actions
                  clip: true
                  spacing: root.sp(3)
                  boundsBehavior: Flickable.StopAtBounds

                  delegate: Rectangle {
                    id: actionRow
                    required property int index
                    required property var modelData

                    readonly property bool hasCursor: root.focusArea === "actions" && index === root.actionIndex
                    readonly property bool enabled: modelData.enabled !== false

                    width: ListView.view.width
                    height: root.actionRowHeight
                    radius: root.cornerRadius
                    color: hasCursor ? root.selectedBackground : "transparent"

                    Row {
                      anchors.fill: parent
                      anchors.leftMargin: root.sp(10)
                      anchors.rightMargin: root.sp(10)
                      spacing: root.sp(8)

                      Text {
                        textFormat: Text.PlainText
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - hintText.width - parent.spacing
                        text: actionRow.modelData.label
                        color: actionRow.enabled
                          ? (actionRow.hasCursor ? root.selectedText : root.foreground)
                          : root.foreground
                        opacity: actionRow.enabled ? 1 : 0.35
                        font.family: root.fontFamily
                        font.pixelSize: root.fBody
                        elide: Text.ElideRight
                      }

                      Text {
                        id: hintText
                        textFormat: Text.PlainText
                        anchors.verticalCenter: parent.verticalCenter
                        text: actionRow.modelData.hint || ""
                        color: root.foreground
                        opacity: actionRow.enabled ? 0.45 : 0.2
                        font.family: root.fontFamily
                        font.pixelSize: root.fCaption
                      }
                    }

                    MouseArea {
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: actionRow.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                      onEntered: {
                        root.focusArea = "actions"
                        root.actionIndex = actionRow.index
                      }
                      onClicked: {
                        root.focusArea = "actions"
                        root.actionIndex = actionRow.index
                        root.runAction(actionRow.modelData)
                      }
                    }
                  }
                }
              }

              // Footer shortcuts
              Text {
                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.leftMargin: root.contentMargin
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                text: "Enter open  ·  \u21e7Enter terminal  ·  \u2325Enter files  ·  Ctrl E editor  ·  Ctrl G GitHub  ·  Ctrl Y copy  ·  Ctrl R rescan"
                color: root.foreground
                opacity: 0.4
                font.family: root.fontFamily
                font.pixelSize: root.fCaption
                elide: Text.ElideRight
              }
            }
          }
        }
      }
    }
  }
}
