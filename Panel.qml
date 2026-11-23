import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model
import "Mascot.js" as Clawd

// AI Usage: one number per Claude Code or Codex account in the bar, and every limit in the
// panel. `bin/ai-usage refresh` does the fetching and writes a status file; every instance of
// this widget (one per monitor) watches that file, and only the first one drives the refreshes.
// This file is the behaviour: refreshing, timers, animations and IPC. What is drawn lives in
// UsageView, UsageBar and UsageContent, which the screenshot renderer shares.
Panel {
  id: root
  moduleName: "ward.ai-usage"
  ipcTarget: "ward.ai-usage"
  manageIpc: false

  Commons.Translations { id: catalog; directory: Qt.resolvedUrl("i18n") }

  // MARK: Settings

  readonly property int refreshIntervalSec: Math.max(60, Number(setting("refreshIntervalSec", 300)) || 300)
  readonly property bool colorMascot: setting("colorMascot", true) !== false
  readonly property bool animationsEnabled: setting("animations", true) !== false
  readonly property bool renewClaude: setting("renewClaude", true) !== false
  // `omarchy toggle animations` turns every shell animation off; the mascots follow it.
  readonly property bool motionAllowed: Style.duration(1000) > 0

  // MARK: Paths

  readonly property string script: filePathFromUrl(Qt.resolvedUrl("bin/ai-usage"))
  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string statusPath: (Quickshell.env("AI_USAGE_STATE_DIR")
    ? expandTilde(Quickshell.env("AI_USAGE_STATE_DIR"))
    : (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/ai-usage") + "/status.json"
  readonly property string configPath: Quickshell.env("AI_USAGE_CONFIG")
    ? expandTilde(Quickshell.env("AI_USAGE_CONFIG"))
    : (Quickshell.env("XDG_CONFIG_HOME") || home + "/.config") + "/ai-usage/accounts.json"

  function filePathFromUrl(url) {
    var value = String(url || "")
    if (value.indexOf("file://") === 0) value = value.slice(7)
    try { value = decodeURIComponent(value) } catch (error) {}
    return value
  }

  function expandTilde(path) {
    var value = String(path || "")
    return value === "~" || value.indexOf("~/") === 0 ? home + value.slice(1) : value
  }

  // MARK: State

  property var status: null
  readonly property var barItems: usageView.barItems
  property var previousBarItems: []
  property bool refreshing: false
  property bool refreshQueued: false
  property bool queuedForce: false
  property bool refreshFailed: false
  property double nowMs: Date.now()
  property double lastTickMs: Date.now()

  // Mascot animations: segment key -> { id, start (ms) }, and the clock they are drawn at.
  property var playing: ({})
  property double frameMs: Date.now()
  property var theme: ({})

  UsageView {
    id: usageView
    status: root.status
    strings: catalog
    nowMs: root.nowMs
    playing: root.playing
    frameMs: root.frameMs
    refreshing: root.refreshing
    refreshFailed: root.refreshFailed
    refreshIntervalSec: root.refreshIntervalSec
    colorMascot: root.colorMascot
    vertical: root.bar ? root.bar.vertical : false
    foreground: root.bar ? root.bar.foreground : Commons.Color.foreground
    barForeground: root.bar ? root.bar.barForeground : Commons.Color.foreground
    urgent: root.bar ? root.bar.urgent : Commons.Color.urgent
    fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
    theme: root.theme
  }

  // MARK: Refreshing

  function isLeader() {
    var items = bar && typeof bar.moduleWidgets === "function" ? bar.moduleWidgets(moduleName) : []
    return items.length === 0 || items[0] === root
  }

  function refresh(force) {
    if (refreshProc.running) {
      refreshQueued = true
      queuedForce = queuedForce || !!force
      return
    }
    var command = ["python3", script, "refresh"]
    if (force) command.push("--force")
    if (!renewClaude) command.push("--no-renew")
    refreshProc.command = command
    refreshing = true
    refreshProc.running = true
  }

  function refreshIfLeader(force) {
    if (isLeader()) refresh(force)
  }

  function loadStatus(text) {
    var parsed = Model.parseStatus(text)
    if (parsed) status = parsed
  }

  function setUsageType(index, type) {
    if (editProc.running) return
    editProc.command = ["python3", script, "usage-type", String(index + 1), type]
    editProc.running = true
  }

  function editAccounts() {
    // Creates the file with discovered defaults first, so there is always something to open.
    Quickshell.execDetached(["sh", "-c", 'python3 "$1" accounts >/dev/null 2>&1; exec omarchy-launch-editor "$2"',
                             "ai-usage", script, configPath])
    close()
  }

  // MARK: Animations

  function claudeKeys() {
    var keys = []
    for (var i = 0; i < barItems.length; i++) {
      if (barItems[i].kind === "account" && barItems[i].provider === "claude") keys.push(barItems[i].key)
    }
    return keys
  }

  // `name` plays that animation on every Claude mascot; empty picks a different one for each.
  function play(name, keys) {
    keys = keys || claudeKeys()
    if (keys.length === 0) return
    var ids = name ? keys.map(function() { return name }) : Clawd.assign(keys.length)
    var next = Object.assign({}, playing)
    var start = Date.now()
    for (var i = 0; i < keys.length; i++) next[keys[i]] = { id: ids[i], start: start }
    frameMs = start
    playing = next
  }

  function playFromIpc(name) {
    var items = bar && typeof bar.moduleWidgets === "function" ? bar.moduleWidgets(moduleName) : [root]
    for (var i = 0; i < items.length; i++) {
      if (items[i] && typeof items[i].play === "function") items[i].play(name)
    }
  }

  function advanceFrame() {
    frameMs = Date.now()
    var next = {}
    var any = false
    for (var key in playing) {
      var entry = playing[key]
      if ((frameMs - entry.start) / 1000 < Clawd.duration(entry.id)) {
        next[key] = entry
        any = true
      }
    }
    if (Object.keys(next).length !== Object.keys(playing).length) playing = next
    if (!any) frameTimer.stop()
  }

  onPlayingChanged: if (Object.keys(playing).length > 0 && !frameTimer.running) frameTimer.start()

  onBarItemsChanged: {
    var changed = Model.changedClaudeSegments(previousBarItems, barItems)
    previousBarItems = barItems
    if (changed.length === 0 || !animationsEnabled || !motionAllowed) return
    play("", changed.map(function(index) { return barItems[index].key }))
  }

  // MARK: Wiring

  Process {
    id: refreshProc
    stderr: StdioCollector {
      id: refreshErrors
      waitForEnd: true
    }
    onExited: function(exitCode) {
      root.refreshing = false
      root.refreshFailed = exitCode !== 0
      if (exitCode !== 0) console.warn("ward.ai-usage: ai-usage refresh exited with " + exitCode + ": " + String(refreshErrors.text || "").slice(-2000))
      statusFile.reload()
      if (root.refreshQueued) {
        var force = root.queuedForce
        root.refreshQueued = false
        root.queuedForce = false
        Qt.callLater(function() { root.refresh(force) })
      }
    }
  }

  Process {
    id: editProc
    onExited: statusFile.reload()
  }

  FileView {
    id: statusFile
    path: root.statusPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.loadStatus(text())
  }

  // A hand edit of accounts.json applies at once; a new account is fetched straight away.
  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    printErrors: false
    onFileChanged: configSettle.restart()
  }

  Timer {
    id: configSettle
    interval: 600
    onTriggered: root.refreshIfLeader(false)
  }

  // The theme's own green, yellow and red color the meters.
  FileView {
    id: themeFile
    path: Commons.Color.currentThemePath + "/colors.toml"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.theme = Model.themeColors(text())
  }

  Connections {
    target: Commons.Color
    function onForegroundChanged() { themeFile.reload() }
    function onUrgentChanged() { themeFile.reload() }
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshIfLeader(false)
  }

  // Keeps countdowns current and notices a resume from sleep: a tick that arrives long after
  // the last one means the machine was asleep, so refresh.
  Timer {
    interval: root.opened ? 5000 : 30000
    running: true
    repeat: true
    onTriggered: {
      var now = Date.now()
      var slept = now - root.lastTickMs > interval + 90000
      root.lastTickMs = now
      root.nowMs = now
      if (slept) root.refreshIfLeader(false)
    }
  }

  // Wakes the refresh that renews a Claude login a few minutes before its token expires.
  Timer {
    id: renewalTimer
    readonly property double due: root.status && root.status.nextCheck ? root.status.nextCheck * 1000 : 0

    function schedule() {
      if (due <= 0) {
        stop()
        return
      }
      // Capped, so a long wait (or a clock change) is checked again rather than trusted.
      interval = Math.max(1000, Math.min(due - Date.now(), 6 * 3600 * 1000))
      restart()
    }

    onDueChanged: schedule()
    onTriggered: {
      if (due <= Date.now() + 1000) root.refreshIfLeader(false)
      else schedule()
    }
  }

  Timer {
    id: frameTimer
    interval: 33
    repeat: true
    onTriggered: root.advanceFrame()
  }

  // About every ten minutes, one mascot picked at random plays an animation for no reason.
  Timer {
    id: fidgetTimer
    interval: (7 + Math.random() * 6) * 60000
    running: true
    repeat: false
    onTriggered: {
      var keys = root.claudeKeys()
      if (root.animationsEnabled && root.motionAllowed && keys.length > 0 && Object.keys(root.playing).length === 0) {
        var animation = Clawd.animations[Math.floor(Math.random() * Clawd.animations.length)].id
        root.play(animation, [keys[Math.floor(Math.random() * keys.length)]])
      }
      interval = (7 + Math.random() * 6) * 60000
      restart()
    }
  }

  onOpenedChanged: if (opened) nowMs = Date.now()

  ShellIpc {
    target: root.ipcTarget

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refresh(true); return "ok" }
    // Plays a mascot animation in the bar, even with animations off: `play hop`, or `play ""`
    // for a different random one on each mascot.
    function play(name: string): string {
      if (name !== "" && !Clawd.animation(name)) return "unknown animation; try: " + root.animationIds()
      root.playFromIpc(name)
      return "ok"
    }
    function animations(): string { return root.animationIds() }
  }

  function animationIds() {
    return Clawd.animations.map(function(item) { return item.id }).join(" ")
  }

  // MARK: Bar

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // Drawn by barContent below; a label of one space keeps the button clickable.
    text: " "
    labelVisible: false
    active: root.opened
    fixedWidth: usageView.vertical ? -1 : Math.ceil(barContent.implicitWidth) + Style.space(8) * 2
    fixedHeight: usageView.vertical ? Math.ceil(barContent.implicitHeight) + Style.space(6) * 2 : -1
    tooltipText: root.opened ? "" : usageView.barTooltip()
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
      else root.refresh(true)
    }

    UsageBar {
      id: barContent
      anchors.centerIn: parent
      scale: button.pressScale
      view: usageView
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(680))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onActivateRequested: root.refresh(true)
      onMoveRequested: function(dx, dy) {
        var limit = Math.max(0, scroll.contentHeight - scroll.height)
        scroll.contentY = Math.max(0, Math.min(limit, scroll.contentY + dy * Style.space(48)))
      }
      onTextKey: function(text) {
        if (text === "r" || text === "R") root.refresh(true)
        else if (text === "e" || text === "E") root.editAccounts()
      }

      Flickable {
        id: scroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        UsageContent {
          id: contentColumn
          width: scroll.width
          view: usageView
          onRefreshRequested: root.refresh(true)
          onEditRequested: root.editAccounts()
          onUsageTypeRequested: function(index, usageType) { root.setUsageType(index, usageType) }
          onMascotTapped: root.play("", ["hero"])
        }
      }
    }
  }
}
