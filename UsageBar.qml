import QtQuick
import qs.Commons

// The bar's content: per account, its mark and its number, with a dot between groups. Each
// mark covers exactly the rows of the number's figures, so both sit on the bar's middle line
// like the rest of the bar's text. A vertical bar stacks them.
Grid {
  id: root

  property var view: null

  columns: view && view.vertical ? 1 : Math.max(1, segments.count + (fallback.visible ? 1 : 0))
  rowSpacing: Style.space(6)
  columnSpacing: Style.space(6)
  horizontalItemAlignment: Grid.AlignHCenter
  verticalItemAlignment: Grid.AlignVCenter

  FigureMetrics {
    id: metrics
    font.family: root.view ? root.view.fontFamily : Style.font.family
    font.pixelSize: root.view && root.view.vertical ? Style.font.caption : Style.font.body
  }

  component BarText: Text {
    textFormat: Text.PlainText
    font.family: metrics.font.family
    font.pixelSize: metrics.font.pixelSize
    color: root.view ? root.view.barForeground : "white"
    renderType: Text.NativeRendering
  }

  // Shown before the first status arrives, with no accounts, or when the config is broken.
  Item {
    id: fallback
    visible: !root.view || root.view.barItems.length === 0
    implicitWidth: fallbackText.implicitWidth
    implicitHeight: fallbackText.implicitHeight

    BarText {
      id: fallbackText
      anchors.centerIn: parent
      anchors.verticalCenterOffset: metrics.offset
      text: root.view && root.view.configError !== "" ? "AI ⚠" : "AI …"
      color: root.view && root.view.configError !== "" ? root.view.urgent : (root.view ? root.view.barForeground : "white")
    }
  }

  Repeater {
    id: segments
    model: root.view ? root.view.barItems : []

    Item {
      id: segment
      required property var modelData
      readonly property bool separator: modelData.kind === "separator"
      readonly property bool stacked: !!root.view && root.view.vertical
      readonly property int gap: Style.space(4)
      // Rendered figures end one pixel above the (rounded down) baseline.
      readonly property int figuresTop: label.y + Math.floor(label.baselineOffset) - metrics.figureHeight

      implicitWidth: separator ? dot.width
        : (stacked ? Math.max(mark.implicitWidth, label.implicitWidth) : mark.implicitWidth + gap + label.implicitWidth)
      implicitHeight: separator ? dot.height
        : (stacked ? mark.implicitHeight + gap + metrics.figureHeight : Math.max(mark.implicitHeight, label.implicitHeight))

      Rectangle {
        id: dot
        visible: segment.separator
        anchors.centerIn: parent
        width: Math.max(3, Style.space(3))
        height: width
        radius: width / 2
        color: root.view ? root.view.barForeground : "white"
      }

      ProviderIcon {
        id: mark
        visible: !segment.separator
        x: segment.stacked ? Math.round((segment.width - width) / 2) : 0
        y: segment.stacked ? 0 : segment.figuresTop
        width: implicitWidth
        height: implicitHeight
        provider: segment.separator ? "claude" : segment.modelData.provider
        figureHeight: metrics.figureHeight
        color: root.view ? root.view.barForeground : "white"
        colorful: !root.view || root.view.colorMascot
        orange: root.view ? root.view.claudeOrange : "#d97757"
        pose: !root.view ? null
          : (segment.separator ? root.view.restingPose : root.view.poseFor(segment.modelData.key, root.view.frameMs))
      }

      BarText {
        id: label
        visible: !segment.separator
        anchors.right: segment.stacked ? undefined : parent.right
        anchors.horizontalCenter: segment.stacked ? parent.horizontalCenter : undefined
        // Centered by its figures, on a whole pixel; stacked, the figures start one gap below
        // the mark.
        y: segment.stacked
          ? mark.height + segment.gap - (Math.floor(baselineOffset) - metrics.figureHeight)
          : Math.round((segment.height - implicitHeight) / 2 + metrics.offset)
        text: segment.separator ? "" : segment.modelData.text
      }
    }
  }
}
