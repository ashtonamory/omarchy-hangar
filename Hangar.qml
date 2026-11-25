import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "HangarFilter.js" as HangarFilter

// Hangar: a keyboard-first picker of project folders. Enter opens the
// default coding agent (`omarchy agent`) in the folder; Ctrl+Enter opens a
// plain terminal there. Summon with: omarchy-shell shell toggle ashton.hangar
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null
  readonly property string pluginId: (root.manifest && root.manifest.id) || "ashton.hangar"
  readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/+$/, "")

  property bool opened: false
  property string filterText: ""
  property int selectedIndex: 0
  property var projects: []
  property var filtered: []
  property bool scanning: false
  property bool scannedOnce: false
  property string agentName: ""

  readonly property var current: (selectedIndex >= 0 && selectedIndex < filtered.length) ? filtered[selectedIndex] : null

  // The [menu] surface tokens, as the built-in pickers use: a theme that
  // styles the Omarchy menu styles this panel too.
  property color background: Commons.Color.menu.background
  property color foreground: Commons.Color.menu.text
  property color border: Commons.Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Commons.Color.menu.scrim
  property color selectedBackground: Commons.Color.menu.selectedBackground
  property color accent: Commons.Color.menu.selectedText
  property color muted: Commons.Color.muted
  property color warning: Commons.Color.warning
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily

  property int pad: Style.spacing.panelPadding
  property int gap: Style.spacing.panelGap
  property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int rowHeight: Math.max(Style.space(30), Style.font.subtitle + Style.spacing.md * 2)
  property int cardWidth: Math.min(Style.space(980), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(580), panel.height - Style.gapsOut * 2)

  Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  // ── open / close ────────────────────────────────────────────────
  function open(payloadJson) {
    root.opened = true
    root.filterText = ""
    root.selectedIndex = 0
    root.rebuild()
    root.rescan()
    if (!agentProcess.running) agentProcess.running = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() { root.opened = false }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  // ── data ────────────────────────────────────────────────────────
  function rescan() {
    if (scanProcess.running) return
    root.scanning = true
    scanProcess.running = true
  }

  function loadScan(text) {
    var list = []
    try { list = JSON.parse(text) } catch (e) { list = [] }
    if (!Array.isArray(list)) list = []
    var keepPath = root.current ? root.current.path : ""
    root.projects = list.slice(0, 500)
    root.scannedOnce = true
    root.rebuild(keepPath)
  }

  function rebuild(keepPath) {
    var out = HangarFilter.filter(root.projects, root.filterText)
    root.filtered = out
    var idx = 0
    if (keepPath && !root.filterText) {
      for (var i = 0; i < out.length; i++) if (out[i].path === keepPath) { idx = i; break }
    }
    root.selectedIndex = out.length ? Math.min(idx, out.length - 1) : -1
    Qt.callLater(function() { if (root.selectedIndex >= 0) list.positionViewAtIndex(root.selectedIndex, ListView.Contain) })
  }

  function setFilter(text) {
    root.filterText = text
    root.rebuild()
  }

  function move(delta) {
    var n = root.filtered.length
    if (!n) return
    root.selectedIndex = Math.max(0, Math.min(n - 1, root.selectedIndex + delta))
    list.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function pageSize() { return Math.max(1, Math.floor(list.height / root.rowHeight) - 1) }

  // ── launch ──────────────────────────────────────────────────────
  function launch(project, terminalOnly) {
    if (!project || !project.path) return
    root.dismiss()
    // The shell starts it, so it outlives this panel; omarchy-agent and the
    // terminal launcher each hand the window to its own systemd scope.
    // A login shell gives it the session PATH, as Util.execArgv does; the path
    // and argv only ever land in positional parameters, so a folder name is
    // never read as shell code.
    var argv = terminalOnly
      ? ["uwsm-app", "--", "xdg-terminal-exec", "--dir=" + project.path]
      : ["omarchy-agent", "--pick"]
    Quickshell.execDetached(["bash", "-lc", 'cd -- "$1" || exit 1; shift; exec "$@"', "bash", project.path].concat(argv))
  }

  function displayAgent(name) {
    return name ? name.charAt(0).toUpperCase() + name.slice(1) : ""
  }

  // Scriptable: omarchy-shell ashton.hangar toggle | open <name> | terminal <name> | search <text>
  ShellIpc {
    target: "ashton.hangar"
    function toggle(): void { root.toggle() }
    function open(name: string): void { root.launchByName(name, false) }
    function terminal(name: string): void { root.launchByName(name, true) }
    function search(text: string): void {
      if (!root.opened) root.open("{}")
      root.setFilter(String(text || "").slice(0, 64))
    }
  }

  function launchByName(name, terminalOnly) {
    var wanted = String(name || "")
    root.pendingLaunch = { name: wanted, terminal: terminalOnly }
    // Always against a fresh scan, so a just-created folder is found.
    root.rescan()
  }

  property var pendingLaunch: null

  Process {
    id: scanProcess
    running: false
    command: [root.pluginDir + "/hangar-scan"]
    stdout: StdioCollector { id: scanOut; waitForEnd: true }
    onExited: function(exitCode) {
      root.scanning = false
      if (exitCode === 0) root.loadScan(scanOut.text)
      else root.scannedOnce = true
      if (root.pendingLaunch) {
        var want = root.pendingLaunch
        root.pendingLaunch = null
        for (var i = 0; i < root.projects.length; i++) {
          if (root.projects[i].name === want.name) { root.launch(root.projects[i], want.terminal); return }
        }
      }
    }
  }

  Process {
    id: agentProcess
    running: false
    command: [root.omarchyPath + "/bin/omarchy-default-agent"]
    stdout: StdioCollector { id: agentOut; waitForEnd: true }
    onExited: function(exitCode) {
      var name = exitCode === 0 ? agentOut.text.trim() : ""
      root.agentName = /^[A-Za-z0-9._-]{1,32}$/.test(name) ? name : ""
    }
  }

  // ── window ──────────────────────────────────────────────────────
  OverlayWindow {
    id: panel
    shown: root.opened
    WlrLayershell.namespace: "omarchy-hangar"

    Rectangle { anchors.fill: parent; color: root.scrim }
    MouseArea { anchors.fill: parent; onClicked: root.dismiss() }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.pad

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
          if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else root.dismiss()
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.launch(root.current, ctrl)
          } else if (event.key === Qt.Key_Up || (ctrl && event.key === Qt.Key_P)) {
            root.move(-1)
          } else if (event.key === Qt.Key_Down || (ctrl && event.key === Qt.Key_N)) {
            root.move(1)
          } else if (event.key === Qt.Key_PageUp) {
            root.move(-root.pageSize())
          } else if (event.key === Qt.Key_PageDown) {
            root.move(root.pageSize())
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
          } else if (!ctrl && event.text && event.text.length === 1
                     && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.setFilter(root.filterText + event.text)
          } else {
            return
          }
          event.accepted = true
        }
      }

      Item {
        id: content
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset

        // ── left: filter + list ──
        Item {
          id: leftPane
          anchors.left: parent.left
          anchors.top: parent.top
          anchors.bottom: footer.top
          anchors.bottomMargin: Style.spacing.md
          width: Math.round(parent.width * 0.42)

          Item {
            id: header
            width: parent.width
            height: root.headerHeight

            Text {
              id: searchIcon
              textFormat: Text.PlainText
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "󰍉"
              color: root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
            }
            Text {
              textFormat: Text.PlainText
              anchors.left: searchIcon.right
              anchors.leftMargin: Style.spacing.lg
              anchors.right: countLabel.left
              anchors.rightMargin: Style.spacing.lg
              anchors.verticalCenter: parent.verticalCenter
              text: root.filterText || strings.t("search")
              color: root.foreground
              opacity: root.filterText ? 1 : 0.5
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              elide: Text.ElideRight
            }
            Text {
              id: countLabel
              textFormat: Text.PlainText
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: strings.t("count").arg(Commons.I18n.formatNumber(root.filtered.length)).arg(Commons.I18n.formatNumber(root.projects.length))
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              visible: root.projects.length > 0
            }
          }

          Rectangle {
            id: headerRule
            anchors.top: header.bottom
            anchors.topMargin: Style.spacing.md
            width: parent.width
            height: 1
            color: root.border
            opacity: 0.25
          }

          ListView {
            id: list
            anchors.top: headerRule.bottom
            anchors.topMargin: Style.spacing.md
            anchors.bottom: parent.bottom
            width: parent.width
            clip: true
            model: root.filtered
            boundsBehavior: Flickable.StopAtBounds
            currentIndex: root.selectedIndex
            highlightMoveDuration: 0

            delegate: Rectangle {
              required property int index
              required property var modelData
              readonly property bool selected: index === root.selectedIndex

              width: ListView.view.width
              height: root.rowHeight
              radius: root.cornerRadius
              color: selected ? root.selectedBackground : "transparent"

              Rectangle {
                visible: parent.selected
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(2, Style.space(3))
                height: parent.height - Style.spacing.md * 2
                radius: width / 2
                color: root.accent
              }

              Text {
                id: folderIcon
                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.leftMargin: Style.spacing.xxl
                anchors.verticalCenter: parent.verticalCenter
                text: parent.modelData.git ? "󰊢" : "󰉋"
                color: parent.selected ? root.accent : root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
              }
              Text {
                textFormat: Text.PlainText
                anchors.left: folderIcon.right
                anchors.leftMargin: Style.spacing.lg
                anchors.right: branchLabel.left
                anchors.rightMargin: Style.spacing.lg
                anchors.verticalCenter: parent.verticalCenter
                text: parent.modelData.name
                color: parent.selected ? root.accent : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.subtitle
                font.bold: parent.selected
                elide: Text.ElideRight
              }
              Row {
                id: branchLabel
                anchors.right: parent.right
                anchors.rightMargin: Style.spacing.lg
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.spacing.md
                width: Math.min(implicitWidth, parent.width * 0.45)

                Text {
                  textFormat: Text.PlainText
                  anchors.verticalCenter: parent.verticalCenter
                  visible: (parent.parent.modelData.changed || 0) > 0
                  text: "●"
                  color: root.warning
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                Text {
                  textFormat: Text.PlainText
                  anchors.verticalCenter: parent.verticalCenter
                  width: Math.min(implicitWidth, branchLabel.parent.width * 0.4)
                  text: parent.parent.modelData.branch || ""
                  color: root.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideMiddle
                }
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { root.selectedIndex = parent.index; root.launch(parent.modelData, false) }
                onPositionChanged: root.selectedIndex = parent.index
              }
            }
          }

          Text {
            anchors.centerIn: list
            width: list.width - root.pad * 2
            visible: root.filtered.length === 0
            textFormat: Text.PlainText
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: !root.scannedOnce ? strings.t("loading")
                 : root.projects.length === 0 ? strings.t("noProjects")
                 : strings.t("noMatches").arg(root.filterText)
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
          }
        }

        // ── divider ──
        Rectangle {
          id: divider
          anchors.left: leftPane.right
          anchors.leftMargin: root.gap
          anchors.top: parent.top
          anchors.bottom: footer.top
          anchors.bottomMargin: Style.spacing.md
          width: 1
          color: root.border
          opacity: 0.25
        }

        // ── right: details ──
        Item {
          id: details
          anchors.left: divider.right
          anchors.leftMargin: root.gap
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.bottom: footer.top
          anchors.bottomMargin: Style.spacing.md
          clip: true
          visible: root.current !== null

          readonly property var p: root.current || ({})

          Column {
            width: parent.width
            spacing: Style.spacing.xxl

            Column {
              width: parent.width
              spacing: Style.spacing.xs
              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: details.p.name || ""
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
                font.bold: true
                elide: Text.ElideRight
              }
              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: (details.p.root || "") + "/" + (details.p.name || "")
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideMiddle
              }
            }

            // status chips
            Flow {
              width: parent.width
              spacing: Style.spacing.xxl
              visible: !!details.p.git

              Text {
                textFormat: Text.PlainText
                text: "󰘬 " + (details.p.branch || "")
                color: root.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
              Text {
                textFormat: Text.PlainText
                text: (details.p.changed || 0) > 0
                      ? "● " + strings.tn("changed", details.p.changed).arg(Commons.I18n.formatNumber(details.p.changed))
                      : "✓ " + strings.t("clean")
                color: (details.p.changed || 0) > 0 ? root.warning : root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
              Text {
                textFormat: Text.PlainText
                visible: !!(details.p.commits && details.p.commits.length)
                text: "󰥔 " + ((details.p.commits && details.p.commits.length) ? details.p.commits[0].when : "")
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
            }
            Text {
              visible: !details.p.git
              textFormat: Text.PlainText
              text: strings.t("notGit")
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            // recent commits
            Column {
              width: parent.width
              spacing: Style.spacing.sm
              visible: !!details.p.git

              Text {
                textFormat: Text.PlainText
                text: strings.t("recentCommits")
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1
                opacity: 0.7
              }
              Text {
                visible: !(details.p.commits && details.p.commits.length)
                textFormat: Text.PlainText
                text: strings.t("noCommits")
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
              Repeater {
                model: details.p.commits || []
                delegate: Item {
                  required property var modelData
                  width: details.width
                  height: subject.implicitHeight
                  Text {
                    id: when
                    textFormat: Text.PlainText
                    width: Style.space(104)
                    text: parent.modelData.when || ""
                    color: root.muted
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    elide: Text.ElideRight
                    anchors.verticalCenter: subject.verticalCenter
                  }
                  Text {
                    id: subject
                    textFormat: Text.PlainText
                    anchors.left: when.right
                    anchors.right: parent.right
                    text: parent.modelData.subject || ""
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                  }
                }
              }
            }

            // readme
            Column {
              width: parent.width
              spacing: Style.spacing.sm
              visible: !!(details.p.readme && details.p.readme.length)

              Text {
                textFormat: Text.PlainText
                text: strings.t("readme")
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1
                opacity: 0.7
              }
              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: (details.p.readme || []).join("\n")
                color: root.foreground
                opacity: 0.75
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                wrapMode: Text.Wrap
                maximumLineCount: 6
                elide: Text.ElideRight
                lineHeight: 1.15
              }
            }
          }
        }

        // ── footer: key hints ──
        Row {
          id: footer
          anchors.left: parent.left
          anchors.bottom: parent.bottom
          spacing: Style.spacing.huge

          Repeater {
            model: [
              { key: "↵", label: root.agentName ? strings.t("openAgent").arg(root.displayAgent(root.agentName)) : strings.t("openAgentDefault") },
              { key: "Ctrl ↵", label: strings.t("openTerminal") },
              { key: "Esc", label: strings.t("close") }
            ]
            delegate: Row {
              required property var modelData
              spacing: Style.spacing.md
              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: keyText.implicitWidth + Style.spacing.lg * 2
                height: keyText.implicitHeight + Style.spacing.xs * 2
                radius: Math.max(2, root.cornerRadius / 2)
                color: root.selectedBackground
                Text {
                  id: keyText
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: parent.parent.modelData.key
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: parent.modelData.label
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }
          }
        }
      }
    }
  }
}
