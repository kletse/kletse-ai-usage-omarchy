import QtQuick
import "Mascot.js" as Clawd

// The Claude Code mascot as crisp pixel art, `figureHeight` screen pixels tall and as wide as
// the terminal original's proportions allow (terminal cells are about 1.8 times as tall as
// wide). Cell edges snap to whole pixels, mirrored about the middle so the eyes and legs stay
// symmetric at any size. `pose` (from Mascot.js) moves the eyes, arms and legs and lifts,
// shifts, turns and squashes the whole figure; its offsets are in points for an 11-point
// mascot and are scaled to the size drawn.
Item {
  id: root

  property int figureHeight: 10
  property var pose: Clawd.restingPose()
  property color bodyColor: "#d97757"
  property color eyeColor: "black"
  // Off draws the eyes as see-through gaps, as a one-color mascot needs.
  property bool fillEyes: true

  // Even, so the middle edge falls on a whole pixel.
  readonly property int figureWidth: Math.max(Clawd.COLUMNS, 2 * Math.round(figureHeight * Clawd.COLUMNS / (Clawd.ROWS * 1.8) / 2))
  readonly property real motion: figureHeight / 11
  readonly property var grid: Clawd.cells(pose)
  readonly property var columnEdges: {
    var edges = []
    var half = Clawd.COLUMNS / 2
    for (var c = 0; c <= Clawd.COLUMNS; c++) {
      edges.push(c <= half
        ? Math.round(c * figureWidth / Clawd.COLUMNS)
        : figureWidth - Math.round((Clawd.COLUMNS - c) * figureWidth / Clawd.COLUMNS))
    }
    return edges
  }
  readonly property var rowEdges: {
    var edges = []
    for (var r = 0; r <= Clawd.ROWS; r++) edges.push(Math.round(r * figureHeight / Clawd.ROWS))
    return edges
  }

  implicitWidth: figureWidth
  implicitHeight: figureHeight

  Item {
    id: figure
    width: root.figureWidth
    height: root.figureHeight
    x: Math.round((root.pose ? root.pose.shift : 0) * root.motion)
    y: -Math.round((root.pose ? root.pose.lift : 0) * root.motion)
    opacity: root.pose ? root.pose.opacity : 1

    // Scale about the feet first, then turn about the centre.
    transform: [
      Scale {
        origin.x: figure.width / 2
        origin.y: figure.height
        xScale: root.pose ? root.pose.scale : 1
        yScale: root.pose ? root.pose.scale * root.pose.stretch : 1
      },
      Rotation {
        origin.x: figure.width / 2
        origin.y: figure.height / 2
        angle: root.pose ? root.pose.tilt : 0
      }
    ]

    Repeater {
      model: Clawd.COLUMNS * Clawd.ROWS

      Rectangle {
        required property int index
        readonly property int cell: root.grid[index]
        readonly property int column: index % Clawd.COLUMNS
        readonly property int row: Math.floor(index / Clawd.COLUMNS)
        x: root.columnEdges[column]
        y: root.rowEdges[row]
        width: root.columnEdges[column + 1] - x
        height: root.rowEdges[row + 1] - y
        antialiasing: false
        visible: cell === Clawd.BODY || (cell === Clawd.EYE && root.fillEyes)
        color: cell === Clawd.EYE ? root.eyeColor : root.bodyColor
      }
    }
  }
}
