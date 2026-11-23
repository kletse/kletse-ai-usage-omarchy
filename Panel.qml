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
Panel {
  id: root
  moduleName: "ward.ai-usage"
  ipcTarget: "ward.ai-usage"
  manageIpc: false

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

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
  readonly property var accounts: status && status.accounts instanceof Array ? status.accounts : []
  readonly property string configError: status && status.configError ? String(status.configError) : ""
  readonly property var barItems: Model.segments(accounts)
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
  readonly property var restingPose: Clawd.restingPose()

  // MARK: Colors

  readonly property color barForeground: bar ? bar.barForeground : Commons.Color.foreground
  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool vertical: bar ? bar.vertical : false
  readonly property color claudeOrange: "#d97757"
  property var theme: ({})
  readonly property color okColor: theme.green || foreground
  readonly property color warningColor: theme.yellow || theme.orange || Qt.tint(foreground, Qt.rgba(urgent.r, urgent.g, urgent.b, 0.5))
  readonly property color criticalColor: theme.red || urgent

  function levelColor(percent) {
    var level = Model.level(percent)
    return level === "critical" ? criticalColor : (level === "warning" ? warningColor : okColor)
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

  function poseFor(key, at) {
    var entry = playing[key]
    if (!entry) return restingPose
    var t = (at - entry.start) / 1000
    if (t < 0 || t >= Clawd.duration(entry.id)) return restingPose
    return Clawd.pose(entry.id, t)
  }

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

  // MARK: Text

  function updatedText() {
    if (refreshing) return strings.t("refreshing", "Refreshing…")
    if (!status || !status.lastRefresh) return strings.t("neverUpdated", "Not updated yet")
    var time = Qt.locale(Commons.I18n.formatLocale).toString(new Date(status.lastRefresh * 1000), "HH:mm")
    return strings.t("updated", "Updated %1").arg(time)
  }

  function ageText(atSec) {
    var age = Model.age(atSec, nowMs)
    if (age.unit === "now") return strings.t("cachedJustNow", "Cached data from just now")
    return strings.t("cachedAgo", "Cached data from %1 ago").arg(age.value + age.unit)
  }

  function resetText(window) {
    if (!window || !window.resetsAt) return ""
    if (window.resetIsEstimate) {
      var date = Qt.locale(Commons.I18n.formatLocale).toString(new Date(window.resetsAt * 1000), "d MMM")
      return strings.t("resetEstimate", "↻ ~%1").arg(date)
    }
    return strings.t("resetIn", "↻ %1").arg(Model.untilText(window.resetsAt, nowMs))
  }

  function resetTooltip(window) {
    if (!window || !window.resetsAt) return ""
    var when = Qt.locale(Commons.I18n.formatLocale).toString(new Date(window.resetsAt * 1000), "dddd d MMMM, HH:mm")
    return window.resetIsEstimate
      ? strings.t("resetEstimateTooltip", "Resets around %1. The API doesn't say when, so the 1st is assumed.").arg(when)
      : strings.t("resetTooltip", "Resets %1").arg(when)
  }

  function barTooltip() {
    if (configError !== "") return strings.t("tooltipConfigError", "AI Usage: can't read the accounts file")
    if (accounts.length === 0) return strings.t("tooltipNoAccounts", "AI Usage: no accounts configured")
    var lines = []
    for (var i = 0; i < accounts.length; i++) {
      var entry = accounts[i]
      var name = String(entry.name || "") + (entry.group ? " (" + entry.group + ")" : "")
      var what = entry.headline ? " · " + String(entry.headline.label || "") : ""
      lines.push(name + ": " + String(entry.menuText || "–") + what)
    }
    return lines.join("\n")
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

  component PlainText: Text {
    textFormat: Text.PlainText
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
    color: root.foreground
  }

  // Both marks are as tall as the text's figures (`figureHeight`), and the mascot's width is
  // the slot width for every provider, so names and numbers line up.
  component ProviderIcon: Item {
    id: icon
    property string provider: "claude"
    property int figureHeight: 10
    property var pose: root.restingPose
    property color color: root.barForeground
    property bool colorful: root.colorMascot
    implicitWidth: mascot.implicitWidth
    implicitHeight: figureHeight

    Mascot {
      id: mascot
      visible: icon.provider === "claude"
      anchors.centerIn: parent
      width: implicitWidth
      height: implicitHeight
      figureHeight: icon.figureHeight
      pose: icon.pose
      bodyColor: icon.colorful ? root.claudeOrange : icon.color
      fillEyes: icon.colorful
    }

    CodexIcon {
      visible: icon.provider === "codex"
      anchors.centerIn: parent
      // The knot fills about 82 of its 100-point view box, so draw the box larger.
      size: Math.round(icon.figureHeight * 100 / 82)
      color: icon.color
    }
  }

  // Figure metrics for lining marks up with text. A Text centered in its line box sits high,
  // because the box keeps room for descenders; `offset` moves it so its figures are centered.
  // `figureHeight` names the font and size so it is measured again when they arrive or change:
  // tightBoundingRect() is a call, which a binding can't track by itself.
  component FigureMetrics: FontMetrics {
    readonly property int figureHeight: font.pixelSize > 0 && font.family !== undefined
      ? Math.max(5, Math.round(tightBoundingRect("0").height)) : 5
    readonly property real offset: Math.round((descent - ascent + figureHeight) / 2)
  }

  FigureMetrics {
    id: barMetrics
    font.family: root.fontFamily
    font.pixelSize: root.vertical ? Style.font.caption : Style.font.body
  }

  FigureMetrics {
    id: panelMetrics
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // Drawn by barContent below; a label of one space keeps the button clickable.
    text: " "
    labelVisible: false
    active: root.opened
    fixedWidth: root.vertical ? -1 : Math.ceil(barContent.implicitWidth) + Style.space(8) * 2
    fixedHeight: root.vertical ? Math.ceil(barContent.implicitHeight) + Style.space(6) * 2 : -1
    tooltipText: root.opened ? "" : root.barTooltip()
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
      else root.refresh(true)
    }

    Grid {
      id: barContent
      anchors.centerIn: parent
      scale: button.pressScale
      columns: root.vertical ? 1 : Math.max(1, barRepeater.count + (fallback.visible ? 1 : 0))
      rowSpacing: Style.space(6)
      columnSpacing: Style.space(6)
      horizontalItemAlignment: Grid.AlignHCenter
      verticalItemAlignment: Grid.AlignVCenter

      // Shown before the first status arrives, with no accounts, or when the config is broken.
      Item {
        id: fallback
        visible: root.barItems.length === 0
        implicitWidth: fallbackText.implicitWidth
        implicitHeight: fallbackText.implicitHeight

        PlainText {
          id: fallbackText
          anchors.centerIn: parent
          anchors.verticalCenterOffset: barMetrics.offset
          text: root.configError !== "" ? "AI ⚠" : "AI …"
          color: root.configError !== "" ? root.urgent : root.barForeground
          font.pixelSize: barMetrics.font.pixelSize
          renderType: Text.NativeRendering
        }
      }

      Repeater {
        id: barRepeater
        model: root.barItems

        // An icon and its number, each centered on the bar's middle line: the icon by its own
        // middle, the number by the middle of its figures. A vertical bar stacks them.
        Item {
          id: segment
          required property var modelData
          readonly property bool separator: modelData.kind === "separator"
          readonly property int gap: Style.space(4)
          implicitWidth: separator ? dot.width
            : (root.vertical ? Math.max(segmentIcon.implicitWidth, segmentText.implicitWidth)
                             : segmentIcon.implicitWidth + gap + segmentText.implicitWidth)
          implicitHeight: separator ? dot.height
            : (root.vertical ? segmentIcon.implicitHeight + gap + barMetrics.figureHeight
                             : Math.max(segmentIcon.implicitHeight, segmentText.implicitHeight))

          Rectangle {
            id: dot
            visible: segment.separator
            anchors.centerIn: parent
            width: Math.max(3, Style.space(3))
            height: width
            radius: width / 2
            color: root.barForeground
          }

          // Rendered figures end one pixel above the (rounded down) baseline.
          readonly property int figuresTop: segmentText.y + Math.floor(segmentText.baselineOffset) - barMetrics.figureHeight

          ProviderIcon {
            id: segmentIcon
            visible: !segment.separator
            x: root.vertical ? Math.round((segment.width - width) / 2) : 0
            y: root.vertical ? 0 : segment.figuresTop
            width: implicitWidth
            height: implicitHeight
            provider: segment.separator ? "claude" : segment.modelData.provider
            figureHeight: barMetrics.figureHeight
            pose: segment.separator ? root.restingPose : root.poseFor(segment.modelData.key, root.frameMs)
          }

          PlainText {
            id: segmentText
            visible: !segment.separator
            anchors.right: root.vertical ? undefined : parent.right
            anchors.horizontalCenter: root.vertical ? parent.horizontalCenter : undefined
            // Centered by its figures, on a whole pixel; stacked, the figures start one gap
            // below the icon.
            y: root.vertical
              ? segmentIcon.height + segment.gap - (Math.floor(baselineOffset) - barMetrics.figureHeight)
              : Math.round((segment.height - implicitHeight) / 2 + barMetrics.offset)
            text: segment.separator ? "" : segment.modelData.text
            color: root.barForeground
            font.pixelSize: barMetrics.font.pixelSize
            renderType: Text.NativeRendering
          }
        }
      }
    }
  }

  // MARK: Panel

  component Meter: Item {
    id: meter
    property real percent: 0
    implicitHeight: Math.max(4, Style.space(6))

    Rectangle {
      id: track
      anchors.fill: parent
      radius: height / 2
      color: Style.selectedFillFor(root.foreground, Commons.Color.accent)
    }

    Rectangle {
      anchors.left: track.left
      anchors.verticalCenter: track.verticalCenter
      height: track.height
      radius: track.radius
      width: track.width * Model.clampPercent(meter.percent) / 100
      color: root.levelColor(meter.percent)
      Behavior on width { NumberAnimation { duration: Style.duration(160); easing.type: Easing.OutCubic } }
    }
  }

  component WindowRow: Column {
    id: row
    property var window: ({})
    spacing: Style.space(4)

    Item {
      width: parent.width
      implicitHeight: Math.max(windowLabel.implicitHeight, windowPercent.implicitHeight)

      PlainText {
        id: windowLabel
        anchors.left: parent.left
        anchors.right: windowReset.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        text: String(row.window.label || "")
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
      }

      PlainText {
        id: windowReset
        anchors.right: windowPercent.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        text: root.resetText(row.window)
        color: root.dim
        font.pixelSize: Style.font.bodySmall

        HoverHandler { id: resetHover }
        PanelToolTip {
          visible: resetHover.hovered && windowReset.text !== ""
          text: root.resetTooltip(row.window)
          fontFamily: root.fontFamily
        }
      }

      TextMetrics {
        id: percentMetrics
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
        text: "100%"
      }

      PlainText {
        id: windowPercent
        width: Math.ceil(percentMetrics.advanceWidth)
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignRight
        text: Model.percentText(row.window.usedPercent)
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }
    }

    Meter {
      width: parent.width
      percent: Number(row.window.usedPercent) || 0
    }

    PlainText {
      visible: !!row.window.detail
      width: parent.width
      text: String(row.window.detail || "")
      color: root.dim
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }

  // Which allowance a Claude account shows in the bar, Session or Week. Click to switch.
  component UsageTypeChip: BorderSurface {
    id: chip
    property int index: 0
    property string usageType: "session"
    readonly property bool hot: chipMouse.containsMouse
    implicitWidth: chipText.implicitWidth + Style.space(10)
    implicitHeight: chipText.implicitHeight + Style.space(4)
    radius: Style.cornerRadius
    color: hot ? Style.hoverFillFor(root.foreground, Commons.Color.accent) : "transparent"
    borderSpec: Border.controlSpec(hot ? "hover-cursor" : "normal", root.foreground, Commons.Color.accent)

    PlainText {
      id: chipText
      anchors.centerIn: parent
      text: (chip.usageType === "week" ? strings.t("usageTypeWeek", "Week") : strings.t("usageTypeSession", "Session")).toUpperCase()
      color: chip.hot ? root.foreground : root.dim
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 0.8
    }

    MouseArea {
      id: chipMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.setUsageType(chip.index, chip.usageType === "week" ? "session" : "week")
    }

    PanelToolTip {
      visible: chipMouse.containsMouse
      implicitWidth: Math.min(implicitContentWidth + leftPadding + rightPadding, Style.space(300))
      text: chip.usageType === "week"
        ? strings.t("usageTypeWeekTooltip", "The bar shows this account's overall weekly usage. Click to show the 5-hour session instead.")
        : strings.t("usageTypeSessionTooltip", "The bar shows this account's 5-hour session. Click to show the overall weekly usage instead.")
      fontFamily: root.fontFamily
    }
  }

  component AccountCard: Rectangle {
    id: card
    property var entry: ({})
    property int index: 0
    readonly property var snapshot: entry.snapshot || null
    readonly property var windows: snapshot && snapshot.windows instanceof Array ? snapshot.windows : []
    readonly property bool claude: entry.provider !== "codex"

    implicitHeight: cardColumn.implicitHeight + Style.space(12) * 2
    radius: Style.cornerRadius
    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.055)
    border.width: Style.spacing.hairline
    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)

    Column {
      id: cardColumn
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Style.space(12)
      spacing: Style.space(8)

      Item {
        width: parent.width
        implicitHeight: Math.max(cardName.implicitHeight, headlineRow.implicitHeight)

        ProviderIcon {
          id: cardIcon
          anchors.left: parent.left
          y: cardName.y + Math.floor(cardName.baselineOffset) - panelMetrics.figureHeight
          provider: card.claude ? "claude" : "codex"
          figureHeight: panelMetrics.figureHeight
          color: root.foreground
        }

        PlainText {
          id: cardName
          anchors.left: cardIcon.right
          anchors.leftMargin: Style.space(8)
          anchors.right: headlineRow.left
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          anchors.verticalCenterOffset: panelMetrics.offset
          text: String(card.entry.name || "")
          font.bold: true
          elide: Text.ElideRight
        }

        Row {
          id: headlineRow
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(8)

          UsageTypeChip {
            visible: card.claude
            anchors.verticalCenter: parent.verticalCenter
            index: card.index
            usageType: String(card.entry.usageType || "session")
          }

          PlainText {
            id: headlineText
            visible: !!card.snapshot
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: panelMetrics.offset
            text: card.entry.headline ? Model.percentText(card.entry.headline.usedPercent) : "–"
            color: card.entry.headline ? root.levelColor(card.entry.headline.usedPercent) : root.dim
            font.bold: true

            HoverHandler { id: headlineHover }
            PanelToolTip {
              visible: headlineHover.hovered && !card.entry.headline
              text: strings.t("headlineMissing", "The usage shown in the bar is not reported for this account.")
              fontFamily: root.fontFamily
            }
          }
        }
      }

      PlainText {
        visible: text !== ""
        width: parent.width
        text: Model.metaLine(card.snapshot)
        color: root.dim
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideMiddle
      }

      Repeater {
        model: card.windows

        WindowRow {
          required property var modelData
          width: cardColumn.width
          window: modelData
        }
      }

      PlainText {
        visible: !!card.snapshot && card.windows.length === 0
        text: strings.t("noLimits", "No limits reported")
        color: root.dim
        font.pixelSize: Style.font.bodySmall
      }

      // A cached copy says so, and so does usage that hasn't been refreshed for a while (after
      // sleep, or while the endpoint keeps failing).
      PlainText {
        visible: !!card.snapshot && (!!card.snapshot.staleReason
          || root.nowMs / 1000 - Number(card.snapshot.fetchedAt) > Math.max(2 * root.refreshIntervalSec, 900))
        text: card.snapshot ? root.ageText(card.snapshot.fetchedAt) : ""
        color: root.warningColor
        font.pixelSize: Style.font.caption
      }

      PlainText {
        visible: !card.snapshot && !card.entry.error
        text: strings.t("loading", "Loading…")
        color: root.dim
        font.pixelSize: Style.font.bodySmall
      }

      PlainText {
        visible: !!card.entry.error
        width: parent.width
        text: String(card.entry.error || "")
        color: root.warningColor
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }
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

        Column {
          id: contentColumn
          width: scroll.width
          spacing: Style.space(10)

          PanelHero {
            width: parent.width
            title: strings.t("title", "AI Usage")
            meta: root.updatedText()
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Mascot {
                width: implicitWidth
                height: implicitHeight
                figureHeight: Style.space(20)
                bodyColor: root.colorMascot ? root.claudeOrange : root.foreground
                fillEyes: root.colorMascot
                pose: root.poseFor("hero", root.frameMs)

                TapHandler { onTapped: root.play("", ["hero"]) }
              }
            }
            trailingControl: Component {
              Row {
                spacing: Style.space(4)

                PanelActionButton {
                  iconText: "󰑐"
                  tooltipText: strings.t("actionRefresh", "Refresh now (R)")
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  enabled: !root.refreshing
                  onClicked: root.refresh(true)
                }

                PanelActionButton {
                  iconText: "󰏫"
                  tooltipText: strings.t("actionEdit", "Edit accounts (E)")
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: root.editAccounts()
                }
              }
            }
          }

          PlainText {
            visible: root.configError !== ""
            width: parent.width
            text: root.configError
            color: root.urgent
            wrapMode: Text.WordWrap
          }

          PlainText {
            visible: root.refreshFailed
            width: parent.width
            text: strings.t("refreshFailed", "Couldn't refresh. Run ai-usage refresh in a terminal to see why.")
            color: root.urgent
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          PlainText {
            visible: !!root.status && root.configError === "" && root.accounts.length === 0
            width: parent.width
            text: strings.t("empty", "No accounts yet. Add a Claude Code or Codex login with ai-usage add, or edit %1.")
              .arg(root.status ? String(root.status.configPath || "") : "")
            color: root.dim
            wrapMode: Text.WordWrap
          }

          Repeater {
            model: root.accounts

            Column {
              id: accountBlock
              required property var modelData
              required property int index
              readonly property bool header: Model.startsGroup(root.accounts, index)
              width: contentColumn.width
              spacing: Style.space(6)
              topPadding: header && index > 0 ? Style.space(6) : 0

              PanelSectionHeader {
                visible: accountBlock.header
                text: String(accountBlock.modelData.group || "").toUpperCase()
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              AccountCard {
                width: parent.width
                entry: accountBlock.modelData
                index: accountBlock.index
              }
            }
          }
        }
      }
    }
  }
}
