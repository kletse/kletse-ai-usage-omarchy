import QtQuick
import "Mascot.js" as Clawd

// The Claude mascot or the Codex knot, as tall as the text's figures (`figureHeight`). The
// mascot's width is the slot width for every provider, so names and numbers line up.
Item {
  id: icon

  property string provider: "claude"
  property int figureHeight: 10
  property var pose: Clawd.restingPose()
  property color color: "white"
  // The mascot in Claude's orange, with dark eyes; off, it takes `color` like the knot.
  property bool colorful: true
  property color orange: "#d97757"

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
    bodyColor: icon.colorful ? icon.orange : icon.color
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
