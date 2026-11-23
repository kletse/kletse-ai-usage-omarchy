import QtQuick

// Figure metrics for lining marks up with text. A Text centered in its line box sits high,
// because the box keeps room for descenders; `offset` moves it so its figures are centered.
// `figureHeight` names the font and size so it is measured again when they arrive or change:
// tightBoundingRect() is a call, which a binding can't track by itself.
FontMetrics {
  readonly property int figureHeight: font.pixelSize > 0 && font.family !== undefined
    ? Math.max(5, Math.round(tightBoundingRect("0").height)) : 5
  readonly property real offset: Math.round((descent - ascent + figureHeight) / 2)
}
