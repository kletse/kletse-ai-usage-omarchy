import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// The panel's content: the hero with refresh and edit, any problem with the config, and a card
// per account with every limit. Actions are signals, so the widget decides what they do.
Column {
  id: root

  property var view: null

  signal refreshRequested()
  signal editRequested()
  signal usageTypeRequested(int index, string usageType)
  signal mascotTapped()

  readonly property color foreground: view ? view.foreground : "white"
  readonly property color dim: view ? view.dim : "gray"
  readonly property string fontFamily: view ? view.fontFamily : Style.font.family

  function t(key, fallback) {
    return view ? view.t(key, fallback) : fallback
  }

  spacing: Style.space(10)

  FigureMetrics {
    id: metrics
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
  }

  // Everything the panel shows is plain text, never markup.
  component PlainText: Text {
    textFormat: Text.PlainText
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
    color: root.foreground
  }

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
      color: root.view ? root.view.levelColor(meter.percent) : root.foreground
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
        text: root.view ? root.view.resetText(row.window) : ""
        color: root.dim
        font.pixelSize: Style.font.bodySmall

        HoverHandler { id: resetHover }
        PanelToolTip {
          visible: resetHover.hovered && windowReset.text !== ""
          text: root.view ? root.view.resetTooltip(row.window) : ""
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
      text: (chip.usageType === "week" ? root.t("usageTypeWeek", "Week") : root.t("usageTypeSession", "Session")).toUpperCase()
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
      onClicked: root.usageTypeRequested(chip.index, chip.usageType === "week" ? "session" : "week")
    }

    PanelToolTip {
      visible: chipMouse.containsMouse
      implicitWidth: Math.min(implicitContentWidth + leftPadding + rightPadding, Style.space(300))
      text: chip.usageType === "week"
        ? root.t("usageTypeWeekTooltip", "The bar shows this account's overall weekly usage. Click to show the 5-hour session instead.")
        : root.t("usageTypeSessionTooltip", "The bar shows this account's 5-hour session. Click to show the overall weekly usage instead.")
      fontFamily: root.fontFamily
    }
  }

  component AccountCard: Rectangle {
    id: card
    property var entry: ({})
    property int index: 0
    readonly property var snapshot: entry.snapshot || null
    readonly property var windows: snapshot ? Model.toList(snapshot.windows) : []
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

        // The mark covers exactly the rows of the name's figures.
        ProviderIcon {
          id: cardIcon
          anchors.left: parent.left
          y: cardName.y + Math.floor(cardName.baselineOffset) - metrics.figureHeight
          provider: card.claude ? "claude" : "codex"
          figureHeight: metrics.figureHeight
          color: root.foreground
          colorful: !root.view || root.view.colorMascot
          orange: root.view ? root.view.claudeOrange : "#d97757"
        }

        PlainText {
          id: cardName
          anchors.left: cardIcon.right
          anchors.leftMargin: Style.space(8)
          anchors.right: headlineRow.left
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          anchors.verticalCenterOffset: metrics.offset
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
            anchors.verticalCenterOffset: metrics.offset
            text: card.entry.headline ? Model.percentText(card.entry.headline.usedPercent) : "–"
            color: card.entry.headline && root.view ? root.view.levelColor(card.entry.headline.usedPercent) : root.dim
            font.bold: true

            HoverHandler { id: headlineHover }
            PanelToolTip {
              visible: headlineHover.hovered && !card.entry.headline
              text: root.t("headlineMissing", "The usage shown in the bar is not reported for this account.")
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
        text: root.t("noLimits", "No limits reported")
        color: root.dim
        font.pixelSize: Style.font.bodySmall
      }

      PlainText {
        visible: !!root.view && root.view.isStale(card.snapshot)
        text: card.snapshot && root.view ? root.view.ageText(card.snapshot.fetchedAt) : ""
        color: root.view ? root.view.warningColor : root.foreground
        font.pixelSize: Style.font.caption
      }

      PlainText {
        visible: !card.snapshot && !card.entry.error
        text: root.t("loading", "Loading…")
        color: root.dim
        font.pixelSize: Style.font.bodySmall
      }

      PlainText {
        visible: !!card.entry.error
        width: parent.width
        text: String(card.entry.error || "")
        color: root.view ? root.view.warningColor : root.foreground
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }
    }
  }

  PanelHero {
    width: parent.width
    title: root.t("title", "AI Usage")
    meta: root.view ? root.view.updatedText() : ""
    foreground: root.foreground
    fontFamily: root.fontFamily
    iconComponent: Component {
      Mascot {
        width: implicitWidth
        height: implicitHeight
        figureHeight: Style.space(20)
        bodyColor: !root.view || root.view.colorMascot ? (root.view ? root.view.claudeOrange : "#d97757") : root.foreground
        fillEyes: !root.view || root.view.colorMascot
        pose: root.view ? root.view.poseFor("hero", root.view.frameMs) : null

        TapHandler { onTapped: root.mascotTapped() }
      }
    }
    trailingControl: Component {
      Row {
        spacing: Style.space(4)

        PanelActionButton {
          iconText: "󰑐"
          tooltipText: root.t("actionRefresh", "Refresh now (R)")
          foreground: root.foreground
          fontFamily: root.fontFamily
          enabled: !root.view || !root.view.refreshing
          onClicked: root.refreshRequested()
        }

        PanelActionButton {
          iconText: "󰏫"
          tooltipText: root.t("actionEdit", "Edit accounts (E)")
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.editRequested()
        }
      }
    }
  }

  PlainText {
    visible: !!root.view && root.view.configError !== ""
    width: parent.width
    text: root.view ? root.view.configError : ""
    color: root.view ? root.view.urgent : root.foreground
    wrapMode: Text.WordWrap
  }

  PlainText {
    visible: !!root.view && root.view.refreshFailed
    width: parent.width
    text: root.t("refreshFailed", "Couldn't refresh. Run ai-usage refresh in a terminal to see why.")
    color: root.view ? root.view.urgent : root.foreground
    font.pixelSize: Style.font.bodySmall
    wrapMode: Text.WordWrap
  }

  PlainText {
    visible: !!root.view && !!root.view.status && root.view.configError === "" && root.view.accounts.length === 0
    width: parent.width
    text: root.t("empty", "No accounts yet. Add a Claude Code or Codex login with ai-usage add, or edit %1.")
      .arg(root.view && root.view.status ? String(root.view.status.configPath || "") : "")
    color: root.dim
    wrapMode: Text.WordWrap
  }

  Repeater {
    model: root.view ? root.view.accounts : []

    Column {
      id: accountBlock
      required property var modelData
      required property int index
      readonly property bool header: Model.startsGroup(root.view.accounts, index)
      width: root.width
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
