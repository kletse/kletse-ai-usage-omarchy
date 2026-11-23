import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons as Commons
import qs.Commons
import "widget" as Widget
import "widget/Model.js" as Model
import "widget/Mascot.js" as Clawd

// Renders the README images from made-up accounts (`ai-usage sample`), offscreen, with the
// widget's own UsageView, UsageBar, UsageContent and Mascot. Run by scripts/render-docs, which
// sets up this folder, a throwaway HOME with a stock theme, and the environment read below.
FloatingWindow {
  id: window

  readonly property string outDir: Quickshell.env("AI_USAGE_RENDER_DIR")
  readonly property string wallpaper: Quickshell.env("AI_USAGE_RENDER_WALLPAPER")
  readonly property string font: "JetBrainsMono Nerd Font"
  property var sample: null
  property double clock: Date.now()

  implicitWidth: 1100
  implicitHeight: 1000
  color: "transparent"

  FileView {
    path: Quickshell.env("AI_USAGE_SAMPLE")
    onLoaded: window.sample = Model.parseStatus(text())
  }

  FileView {
    path: Commons.Color.currentThemePath + "/colors.toml"
    onLoaded: usageView.theme = Model.themeColors(text())
  }

  Commons.Translations { id: catalog; directory: Qt.resolvedUrl("widget/i18n") }

  Widget.UsageView {
    id: usageView
    status: window.sample
    strings: catalog
    nowMs: window.clock
    frameMs: window.clock
    fontFamily: window.font
    foreground: Commons.Color.popups.text
    barForeground: Commons.Color.bar.text
    urgent: Commons.Color.bar.active
  }

  // A stretch of the bar: the widget, then a few of the usual status icons.
  component BarStrip: Rectangle {
    id: strip
    readonly property real widgetCenter: stripRow.x + stripBar.x + stripBar.width / 2
    property bool indicator: false
    property bool extras: true
    implicitWidth: stripRow.implicitWidth + Style.space(14) * 2
    implicitHeight: Style.bar.sizeHorizontal
    color: Commons.Color.bar.background

    Row {
      id: stripRow
      anchors.right: parent.right
      anchors.rightMargin: Style.space(14)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(16)

      Widget.UsageBar {
        id: stripBar
        anchors.verticalCenter: parent.verticalCenter
        view: usageView
      }

      Repeater {
        model: strip.extras ? ["󰕾", "󰖩", "󰂯", "󰁹"] : []

        Text {
          required property string modelData
          anchors.verticalCenter: parent.verticalCenter
          text: modelData
          color: Commons.Color.bar.text
          font.family: window.font
          font.pixelSize: Style.bar.iconFont
        }
      }
    }

    // The mark under a widget whose panel is open.
    Rectangle {
      visible: strip.indicator
      x: stripRow.x + stripBar.x - Style.space(4)
      width: stripBar.width + Style.space(8)
      height: Style.space(2)
      y: parent.height - height - Style.space(2)
      radius: height / 2
      color: Commons.Color.accent
      opacity: 0.9
    }
  }

  // The panel open below its widget, over the theme's wallpaper.
  Item {
    id: panelShot
    readonly property int padding: Style.spacing.popupPadding
    readonly property int border: Math.max(1, Style.space(2))
    width: card.width + Style.space(160)
    height: strip.height + Style.gapsOut + card.height + Style.space(40)
    clip: true

    Image {
      anchors.fill: parent
      source: window.wallpaper ? "file://" + window.wallpaper : ""
      fillMode: Image.PreserveAspectCrop
      horizontalAlignment: Image.AlignRight
      verticalAlignment: Image.AlignTop
      asynchronous: false
    }

    BarStrip {
      id: strip
      width: parent.width
      indicator: true
    }

    Rectangle {
      id: card
      width: Style.space(400) + (panelShot.padding + panelShot.border) * 2
      height: content.implicitHeight + (panelShot.padding + panelShot.border) * 2
      x: Math.min(parent.width - width - Style.gapsOut, strip.widgetCenter - width / 2)
      y: strip.height + Style.gapsOut
      color: Commons.Color.popups.background
      border.width: panelShot.border
      border.color: Commons.Color.popups.border
      radius: Style.cornerRadius

      Widget.UsageContent {
        id: content
        x: panelShot.padding + panelShot.border
        y: x
        width: Style.space(400)
        view: usageView
      }
    }
  }

  // The bar on its own, for the animation of the mascots.
  BarStrip {
    id: barShot
    y: panelShot.height + 20
    extras: false
  }

  // Every animation in a grid, each looping on its own.
  Rectangle {
    id: gridShot
    readonly property int columns: 7
    readonly property int cell: Style.space(96)
    readonly property double loop: 2.4
    property double t: 0
    y: barShot.y + barShot.height + 20
    width: columns * cell + Style.space(24)
    height: Math.ceil(Clawd.animations.length / columns) * Style.space(76) + Style.space(24)
    color: Commons.Color.popups.background

    Grid {
      anchors.centerIn: parent
      columns: gridShot.columns

      Repeater {
        model: Clawd.animations

        Item {
          required property var modelData
          width: gridShot.cell
          height: Style.space(76)

          Widget.Mascot {
            anchors.horizontalCenter: parent.horizontalCenter
            y: Style.space(18)
            width: implicitWidth
            height: implicitHeight
            figureHeight: Style.space(25)
            pose: gridShot.t < modelData.duration ? Clawd.pose(modelData.id, gridShot.t) : Clawd.restingPose()
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Style.space(4)
            text: modelData.name
            color: Qt.darker(Commons.Color.popups.text, 1.4)
            font.family: window.font
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }

  function pad(n) {
    return ("000" + n).slice(-3)
  }

  // Grabs `item` once per frame, `setup(i)` moving the clock first, then calls `done`.
  function frames(item, prefix, count, setup, done) {
    var i = 0
    function next() {
      if (i >= count) {
        done()
        return
      }
      setup(i)
      item.grabToImage(function(result) {
        result.saveToFile(window.outDir + "/" + prefix + "-" + window.pad(i) + ".png")
        i++
        next()
      })
    }
    next()
  }

  function render() {
    panelShot.grabToImage(function(result) {
      result.saveToFile(window.outDir + "/panel.png")
      // The bar: two mascots play as usage changes, the second a moment later.
      var keys = usageView.barItems.filter(function(s) { return s.kind === "account" && s.provider === "claude" })
        .map(function(s) { return s.key })
      var start = Date.now() + 400
      var playing = {}
      playing[keys[0]] = { id: "backflip", start: start }
      if (keys.length > 1) playing[keys[1]] = { id: "dance", start: start + 700 }
      usageView.playing = playing
      window.frames(barShot, "bar", 84, function(i) { window.clock = start - 400 + i * 1000 / 30 }, function() {
        window.frames(gridShot, "grid", 72, function(i) { gridShot.t = i / 30 }, function() {
          gridShot.grabToImage(function(last) {
            last.saveToFile(window.outDir + "/done.png")
            Qt.quit()
          })
        })
      })
    })
  }

  // Waits for the sample, the theme and the fonts to settle before the first grab.
  Timer {
    interval: 1500
    running: true
    onTriggered: window.render()
  }
}
