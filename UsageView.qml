import QtQuick
import qs.Commons
import qs.Commons as Commons
import "Model.js" as Model
import "Mascot.js" as Clawd

// What the bar (UsageBar.qml) and the panel (UsageContent.qml) show and how it reads. The
// widget (Panel.qml) feeds it the live status; the screenshot renderer feeds it sample data.
QtObject {
  id: view

  // The status file written by `bin/ai-usage`, parsed by Model.parseStatus.
  property var status: null
  // A Commons.Translations for the plugin's i18n catalog.
  property var strings: null
  property double nowMs: Date.now()
  // Mascot animations: segment key -> { id, start (ms) }, and the clock they are drawn at.
  property var playing: ({})
  property double frameMs: Date.now()
  property bool refreshing: false
  property bool refreshFailed: false
  property int refreshIntervalSec: 300
  property bool colorMascot: true
  property bool vertical: false
  property color foreground: Commons.Color.foreground
  property color barForeground: Commons.Color.foreground
  property color urgent: Commons.Color.urgent
  property string fontFamily: Style.font.family
  // Named colors from the theme's colors.toml (Model.themeColors).
  property var theme: ({})

  readonly property var accounts: status ? Model.toList(status.accounts) : []
  readonly property string configError: status && status.configError ? String(status.configError) : ""
  readonly property var barItems: Model.segments(accounts)
  readonly property var restingPose: Clawd.restingPose()
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color claudeOrange: "#d97757"
  // The theme's own green, yellow and red color the meters.
  readonly property color okColor: theme.green || foreground
  readonly property color warningColor: theme.yellow || theme.orange || Qt.tint(foreground, Qt.rgba(urgent.r, urgent.g, urgent.b, 0.5))
  readonly property color criticalColor: theme.red || urgent

  function t(key, fallback) {
    return strings ? strings.t(key, fallback) : fallback
  }

  function levelColor(percent) {
    var level = Model.level(percent)
    return level === "critical" ? criticalColor : (level === "warning" ? warningColor : okColor)
  }

  function poseFor(key, at) {
    var entry = playing[key]
    if (!entry) return restingPose
    var seconds = (at - entry.start) / 1000
    if (seconds < 0 || seconds >= Clawd.duration(entry.id)) return restingPose
    return Clawd.pose(entry.id, seconds)
  }

  function formatDate(seconds, format) {
    return Qt.locale(Commons.I18n.formatLocale).toString(new Date(seconds * 1000), format)
  }

  function updatedText() {
    if (refreshing) return t("refreshing", "Refreshing…")
    if (!status || !status.lastRefresh) return t("neverUpdated", "Not updated yet")
    return t("updated", "Updated %1").arg(formatDate(status.lastRefresh, "HH:mm"))
  }

  function ageText(atSec) {
    var age = Model.age(atSec, nowMs)
    if (age.unit === "now") return t("cachedJustNow", "Cached data from just now")
    return t("cachedAgo", "Cached data from %1 ago").arg(age.value + age.unit)
  }

  // A cached copy says so, and so does usage that hasn't been refreshed for a while (after
  // sleep, or while the endpoint keeps failing).
  function isStale(snapshot) {
    return !!snapshot && (!!snapshot.staleReason
      || nowMs / 1000 - Number(snapshot.fetchedAt) > Math.max(2 * refreshIntervalSec, 900))
  }

  function resetText(window) {
    if (!window || !window.resetsAt) return ""
    if (window.resetIsEstimate) return t("resetEstimate", "↻ ~%1").arg(formatDate(window.resetsAt, "d MMM"))
    return t("resetIn", "↻ %1").arg(Model.untilText(window.resetsAt, nowMs))
  }

  function resetTooltip(window) {
    if (!window || !window.resetsAt) return ""
    var when = formatDate(window.resetsAt, "dddd d MMMM, HH:mm")
    return window.resetIsEstimate
      ? t("resetEstimateTooltip", "Resets around %1. The API doesn't say when, so the 1st is assumed.").arg(when)
      : t("resetTooltip", "Resets %1").arg(when)
  }

  function barTooltip() {
    if (configError !== "") return t("tooltipConfigError", "AI Usage: can't read the accounts file")
    if (accounts.length === 0) return t("tooltipNoAccounts", "AI Usage: no accounts configured")
    var lines = []
    for (var i = 0; i < accounts.length; i++) {
      var entry = accounts[i]
      var name = String(entry.name || "") + (entry.group ? " (" + entry.group + ")" : "")
      var what = entry.headline ? " · " + String(entry.headline.label || "") : ""
      lines.push(name + ": " + String(entry.menuText || "–") + what)
    }
    return lines.join("\n")
  }
}
