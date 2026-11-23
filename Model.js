.pragma library

// Display helpers for the widget. The status file written by `bin/ai-usage` already holds each
// account's headline and bar text; this only turns numbers into what the panel shows. Pure
// functions, so tests can run them in Node.

// Below 75% a meter is normal, from 75% a warning, and from 90% critical.
function level(percent) {
  var value = Number(percent)
  if (!isFinite(value)) return "normal"
  if (value >= 90) return "critical"
  if (value >= 75) return "warning"
  return "normal"
}

function clampPercent(value) {
  var number = Number(value)
  if (!isFinite(number)) return 0
  return Math.max(0, Math.min(100, number))
}

// Rounds half up, like the CLI, so "42%" reads the same in the bar, the panel, and the terminal.
function percentText(value) {
  return Math.floor(clampPercent(value) + 0.5) + "%"
}

// Whole days, hours, and minutes until `resetsAtSec` (epoch seconds), never negative.
function untilParts(resetsAtSec, nowMs) {
  var seconds = Math.max(0, Math.floor(Number(resetsAtSec) - nowMs / 1000))
  if (!isFinite(seconds)) seconds = 0
  return {
    days: Math.floor(seconds / 86400),
    hours: Math.floor(seconds % 86400 / 3600),
    minutes: Math.floor(seconds % 3600 / 60)
  }
}

// "2d 3h", "4h 12m", or "12m".
function untilText(resetsAtSec, nowMs) {
  var parts = untilParts(resetsAtSec, nowMs)
  if (parts.days > 0) return parts.days + "d " + parts.hours + "h"
  if (parts.hours > 0) return parts.hours + "h " + parts.minutes + "m"
  return parts.minutes + "m"
}

// How long ago `atSec` was, coarsely: { unit: "now" | "m" | "h" | "d", value }.
function age(atSec, nowMs) {
  var seconds = Math.max(0, Math.floor(nowMs / 1000 - Number(atSec)))
  if (!isFinite(seconds) || seconds < 60) return { unit: "now", value: 0 }
  if (seconds < 3600) return { unit: "m", value: Math.floor(seconds / 60) }
  if (seconds < 86400) return { unit: "h", value: Math.floor(seconds / 3600) }
  return { unit: "d", value: Math.floor(seconds / 86400) }
}

// "you@example.com · Max", leaving out what isn't known.
function metaLine(snapshot) {
  if (!snapshot) return ""
  var parts = []
  if (snapshot.identity) parts.push(String(snapshot.identity))
  if (snapshot.plan) parts.push(String(snapshot.plan))
  return parts.join(" · ")
}

// The bar's content in config order: one segment per account and a separator between groups.
function segments(accounts) {
  var out = []
  var list = Array.isArray(accounts) ? accounts : []
  for (var i = 0; i < list.length; i++) {
    var entry = list[i] || {}
    if (i > 0 && (entry.group || null) !== ((list[i - 1] || {}).group || null)) out.push({ kind: "separator", key: "sep-" + i })
    out.push({
      kind: "account",
      key: String(entry.id || i),
      index: i,
      provider: entry.provider === "codex" ? "codex" : "claude",
      text: String(entry.menuText || "–"),
      level: entry.headline ? level(entry.headline.usedPercent) : "normal"
    })
  }
  return out
}

// Indexes (into `segments`) of Claude accounts whose bar text changed to a real value, so their
// mascots can celebrate. Only meaningful while the account list keeps its shape.
function changedClaudeSegments(previous, next) {
  var out = []
  if (!Array.isArray(previous) || !Array.isArray(next) || previous.length !== next.length) return out
  for (var i = 0; i < next.length; i++) {
    var a = previous[i], b = next[i]
    if (!a || !b || a.kind !== "account" || b.kind !== "account") continue
    if (a.provider !== "claude" || b.provider !== "claude" || a.key !== b.key) continue
    if (a.text !== b.text && b.text !== "–") out.push(i)
  }
  return out
}

// Whether the group header goes above account `index`.
function startsGroup(accounts, index) {
  var entry = accounts[index] || {}
  if (!entry.group) return false
  return index === 0 || ((accounts[index - 1] || {}).group || null) !== entry.group
}

// Pulls named colors out of an Omarchy theme's colors.toml (`green = "#608f76"`).
function themeColors(text) {
  var out = {}
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var match = lines[i].match(/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"(#[0-9A-Fa-f]{6}(?:[0-9A-Fa-f]{2})?)"\s*(?:#.*)?$/)
    if (match) out[match[1]] = match[2]
  }
  return out
}

// The status file, checked enough that a hand-edited or truncated one can't break the panel.
function parseStatus(text) {
  var data
  try {
    data = JSON.parse(String(text || ""))
  } catch (error) {
    return null
  }
  if (!data || typeof data !== "object" || data.version !== 1) return null
  if (!Array.isArray(data.accounts)) data.accounts = []
  data.accounts = data.accounts.filter(function(entry) { return entry && typeof entry === "object" })
  return data
}
