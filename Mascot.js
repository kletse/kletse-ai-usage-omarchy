.pragma library

// The Claude Code mascot, as it is printed on startup (▐▛███▜▌ / ▝▜█████▛▘ / ▘▘ ▝▝), on a 16×5
// grid of quadrant-block pixels, and its 35 bar animations. Ported from the macOS app's
// Icons.swift. Pure functions, so tests can run them in Node.

var COLUMNS = 16
var ROWS = 5

// Pixel cell values in `cells()`.
var EMPTY = 0
var BODY = 1
var EYE = 2

function range(from, to) {
  var out = []
  for (var i = from; i <= to; i++) out.push(i)
  return out
}

// Seconds each animation runs; keep in sync with `pose()`.
var animations = [
  { id: "hop", name: "Hop", duration: 1 },
  { id: "wave", name: "Wave", duration: 1.3 },
  { id: "lookAround", name: "Look around", duration: 1.5 },
  { id: "dance", name: "Dance", duration: 1.4 },
  { id: "shiver", name: "Shiver", duration: 0.8 },
  { id: "bigJump", name: "Big jump", duration: 1.2 },
  { id: "cheer", name: "Cheer", duration: 1.3 },
  { id: "wink", name: "Wink", duration: 0.9 },
  { id: "walk", name: "Walk", duration: 1.6 },
  { id: "bounce", name: "Bounce", duration: 0.9 },
  { id: "doze", name: "Doze off", duration: 2 },
  { id: "surprise", name: "Surprise", duration: 1 },
  { id: "flap", name: "Flap", duration: 1.5 },
  { id: "stretch", name: "Stretch", duration: 1.6 },
  { id: "rockOut", name: "Rock out", duration: 1.2 },
  { id: "spin", name: "Spin", duration: 1 },
  { id: "curious", name: "Curious", duration: 1.6 },
  { id: "boing", name: "Boing", duration: 1 },
  { id: "pop", name: "Pop", duration: 0.7 },
  { id: "scared", name: "Scared", duration: 1.4 },
  { id: "teleport", name: "Teleport", duration: 1.3 },
  { id: "ghost", name: "Ghost", duration: 1.8 },
  { id: "sneeze", name: "Sneeze", duration: 1.4 },
  { id: "snore", name: "Snore", duration: 2.4 },
  { id: "backflip", name: "Backflip", duration: 1.2 },
  { id: "wobble", name: "Wobble", duration: 1.2 },
  { id: "jumpingJacks", name: "Jumping jacks", duration: 1.5 },
  { id: "tapFoot", name: "Tap foot", duration: 1.6 },
  { id: "moonwalk", name: "Moonwalk", duration: 1.6 },
  { id: "peekaboo", name: "Peekaboo", duration: 1.4 },
  { id: "shy", name: "Shy", duration: 1.6 },
  { id: "hiccup", name: "Hiccup", duration: 1.8 },
  { id: "heartbeat", name: "Heartbeat", duration: 1.4 },
  { id: "dizzy", name: "Dizzy", duration: 2 },
  { id: "swim", name: "Swim", duration: 1.8 }
]

function animation(id) {
  for (var i = 0; i < animations.length; i++) {
    if (animations[i].id === id) return animations[i]
  }
  return null
}

function duration(id) {
  var found = animation(id)
  return found ? found.duration : 0
}

// A resting pose. Lift and shift are in points for an 11-point-tall mascot, tilt in degrees
// clockwise about the centre, scale about the feet, stretch is height on top of scale.
function restingPose() {
  return {
    lift: 0, shift: 0, tilt: 0, scale: 1, stretch: 1, opacity: 1,
    eyes: "open", leftArm: "down", rightArm: "down", legs: "standing"
  }
}

// Different animations for each of `count` mascots, as long as there are enough to go round.
// `random` returns [0, 1); injectable for tests.
function assign(count, random) {
  random = random || Math.random
  var ids = animations.map(function(item) { return item.id })
  for (var i = ids.length - 1; i > 0; i--) {
    var j = Math.floor(random() * (i + 1))
    var swap = ids[i]; ids[i] = ids[j]; ids[j] = swap
  }
  var out = []
  for (var k = 0; k < count; k++) out.push(ids[k % ids.length])
  return out
}

function pose(id, t) {
  // A jump of `height` points from `start` to `start + length`.
  function arc(start, length, height) {
    var progress = (t - start) / length
    return progress >= 0 && progress <= 1 ? height * Math.sin(Math.PI * progress) : 0
  }
  function during(start, end) { return t >= start && t < end }
  // Alternates every `period` seconds, starting true.
  function beat(period) { return Math.floor(t / period) % 2 === 0 }
  // Eases between [time, value] keyframes, holding the first and last values outside them.
  function keys(frames) {
    var next = -1
    for (var i = 0; i < frames.length; i++) {
      if (frames[i][0] > t) { next = i; break }
    }
    if (next === -1) return frames.length ? frames[frames.length - 1][1] : 0
    if (next === 0) return frames[0][1]
    var t0 = frames[next - 1][0], v0 = frames[next - 1][1]
    var t1 = frames[next][0], v1 = frames[next][1]
    var progress = (t - t0) / (t1 - t0)
    return v0 + (v1 - v0) * (1 - Math.cos(Math.PI * progress)) / 2
  }
  function wave(period) { return Math.sin(2 * Math.PI * t / period) }

  var p = restingPose()
  switch (id) {
  case "hop":
    // Two hops, the second smaller, then a blink.
    p.lift = arc(0, 0.36, 3) + arc(0.36, 0.26, 1.5)
    if (during(0.08, 0.28)) p.legs = "tucked"
    if (during(0.75, 0.9)) p.eyes = "closed"
    break
  case "wave":
    if (during(0.1, 1.15)) p.rightArm = beat(0.15) ? "high" : "raised"
    if (during(1.15, 1.27)) p.eyes = "closed"
    break
  case "lookAround":
    p.eyes = during(0.15, 0.6) ? "left" : during(0.6, 1.05) ? "right" : during(1.2, 1.32) ? "closed" : "open"
    break
  case "dance":
    if (t >= 1.4) break
    p.legs = beat(0.175) ? "stepLeft" : "stepRight"
    p.lift = beat(0.175) ? 0 : 1
    p.shift = beat(0.35) ? -1 : 1
    p.leftArm = beat(0.35) ? "raised" : "down"
    p.rightArm = beat(0.35) ? "down" : "raised"
    break
  case "shiver":
    if (t >= 0.7) break
    p.shift = (beat(0.05) ? 1 : -1) * (t < 0.45 ? 1 : 0.5)
    p.eyes = "wide"
    break
  case "bigJump":
    // Crouch, leap with arms up, land in a crouch.
    p.lift = during(0, 0.2) || during(0.75, 0.9) ? -1 : arc(0.2, 0.55, 3.5)
    if (during(0.25, 0.7)) p.legs = "tucked"
    if (during(0.3, 0.65)) { p.leftArm = "high"; p.rightArm = "high" }
    if (during(0.95, 1.07)) p.eyes = "closed"
    break
  case "cheer":
    if (t >= 1.1) break
    p.leftArm = beat(0.15) ? "high" : "raised"
    p.rightArm = beat(0.15) ? "raised" : "high"
    p.eyes = "closed"
    p.lift = arc(0, 0.3, 1) + arc(0.3, 0.3, 1) + arc(0.6, 0.3, 1)
    break
  case "wink":
    p.lift = arc(0, 0.25, 1)
    if (during(0.2, 0.7)) { p.eyes = "wink"; p.rightArm = "raised" }
    break
  case "walk":
    // A few steps left, a look back, and home again.
    p.shift = t < 0.7 ? -2 * t / 0.7 : t < 0.9 ? -2 : -2 + 2 * Math.min(1, (t - 0.9) / 0.7)
    if (!during(0.7, 0.9) && t < 1.6) p.legs = beat(0.12) ? "stepLeft" : "stepRight"
    p.eyes = t < 0.7 ? "left" : t < 0.9 ? "open" : "right"
    break
  case "bounce":
    p.lift = arc(0, 0.3, 1.5) + arc(0.3, 0.3, 1) + arc(0.6, 0.3, 0.5)
    break
  case "doze":
    // Nods off, then wakes with a start.
    if (during(0.2, 1.5)) p.eyes = "closed"
    if (during(0.5, 1.5)) p.lift = -0.5
    if (during(1.5, 1.9)) p.eyes = "wide"
    p.lift += arc(1.5, 0.3, 2)
    break
  case "surprise":
    p.lift = arc(0, 0.35, 2.5)
    if (during(0, 0.8)) p.eyes = "wide"
    if (during(0.05, 0.5)) { p.leftArm = "high"; p.rightArm = "high" }
    if (during(0.05, 0.3)) p.legs = "tucked"
    break
  case "flap":
    // Flaps up into the air, then drops.
    if (t < 1.2) {
      p.leftArm = beat(0.1) ? "raised" : "down"
      p.rightArm = p.leftArm
      p.lift = 2.5 * Math.min(1, t / 0.9)
      if (t > 0.3) p.legs = "tucked"
    } else if (t < 1.35) {
      p.lift = 2.5 * (1.35 - t) / 0.15
    }
    break
  case "stretch":
    var arm = during(0.3, 1.2) ? "high" : during(0.1, 1.35) ? "raised" : "down"
    p.leftArm = arm
    p.rightArm = arm
    if (during(0.3, 1.2)) p.lift = 0.5
    if (during(0.25, 1.25)) p.eyes = "closed"
    break
  case "rockOut":
    if (t >= 1.05) break
    p.lift = beat(0.15) ? 0 : -1
    p.eyes = "closed"
    p.rightArm = "high"
    break
  case "spin":
    // Smaller while turning, so its corners stay inside the bar.
    p.tilt = keys([[0.1, 0], [0.8, 360]])
    if (during(0.1, 0.8)) p.scale = 0.8
    p.lift = arc(0.05, 0.8, 1.5)
    break
  case "curious":
    p.tilt = keys([[0, 0], [0.2, -12], [0.6, -12], [0.8, 0], [1, 12], [1.4, 12], [1.6, 0]])
    p.eyes = during(0.15, 0.7) ? "left" : during(0.9, 1.45) ? "right" : "open"
    break
  case "boing":
    p.stretch = keys([[0, 1], [0.15, 0.7], [0.3, 1.25], [0.55, 1.1], [0.7, 0.75], [0.85, 1.08], [1, 1]])
    p.lift = arc(0.25, 0.4, 3)
    if (during(0.3, 0.55)) p.legs = "tucked"
    break
  case "pop":
    p.scale = keys([[0, 1], [0.12, 1.2], [0.3, 0.92], [0.45, 1.05], [0.6, 1]])
    if (during(0.05, 0.4)) p.eyes = "wide"
    break
  case "scared":
    p.scale = keys([[0, 1], [0.1, 0.65], [1, 0.65], [1.3, 1]])
    if (during(0.1, 1)) { p.shift = beat(0.06) ? 0.5 : -0.5; p.eyes = "wide" }
    break
  case "teleport":
    // Beams out as a thin streak and back in, then blinks.
    p.opacity = keys([[0, 1], [0.3, 0], [0.6, 0], [0.9, 1]])
    p.scale = keys([[0, 1], [0.3, 0.6], [0.6, 0.6], [0.9, 1]])
    p.stretch = keys([[0, 1], [0.3, 1.8], [0.6, 1.8], [0.9, 1]])
    if (during(0.95, 1.07)) p.eyes = "closed"
    break
  case "ghost":
    p.opacity = keys([[0, 1], [0.2, 0.35], [1.5, 0.35], [1.75, 1]])
    if (during(0.2, 1.6)) {
      p.lift = 1.5 * wave(0.8)
      p.leftArm = "raised"
      p.rightArm = "raised"
      p.eyes = "wide"
    }
    break
  case "sneeze":
    // Leans back as it builds, then lurches forward.
    p.tilt = keys([[0, 0], [0.7, -8], [0.78, 10], [1, 0]])
    p.stretch = keys([[0, 1], [0.7, 1.12], [0.78, 0.8], [1, 1]])
    p.shift = keys([[0, 0], [0.7, -0.5], [0.78, 1], [1, 0]])
    if (during(0.35, 1)) p.eyes = "closed"
    break
  case "snore":
    if (t >= 2.2) break
    p.eyes = "closed"
    p.lift = -0.5
    p.stretch = 1 - 0.08 * (1 - Math.cos(2 * Math.PI * t / 1.1)) / 2
    break
  case "backflip":
    p.lift = arc(0.1, 0.8, 3.5)
    p.tilt = keys([[0.2, 0], [0.75, -360]])
    if (during(0.2, 0.75)) p.scale = 0.8
    if (during(0.15, 0.8)) p.legs = "tucked"
    p.stretch = keys([[0.85, 1], [0.92, 0.8], [1.05, 1]])
    break
  case "wobble":
    p.tilt = 12 * wave(0.3) * Math.max(0, 1 - t / 1.2)
    break
  case "jumpingJacks":
    if (t >= 1.5) break
    if (t % 0.5 < 0.25) {
      p.leftArm = "high"
      p.rightArm = "high"
      p.legs = "wide"
    }
    p.lift = arc(0, 0.25, 1) + arc(0.5, 0.25, 1) + arc(1, 0.25, 1)
    break
  case "tapFoot":
    if (t >= 1.5) break
    p.legs = beat(0.1) ? "stepRight" : "standing"
    p.eyes = "left"
    p.tilt = -3
    break
  case "moonwalk":
    // Slides backwards while the legs walk forwards.
    p.shift = keys([[0, 0], [1.1, -3], [1.35, -3], [1.6, 0]])
    if (t < 1.1) {
      p.legs = beat(0.14) ? "stepLeft" : "stepRight"
      p.eyes = "right"
      p.tilt = 4
    }
    break
  case "peekaboo":
    p.lift = keys([[0, 0], [0.15, -2], [0.7, -2], [0.8, 1.5], [1, 0]])
    p.stretch = keys([[0, 1], [0.15, 0.75], [0.7, 0.75], [0.8, 1.15], [1, 1]])
    p.eyes = during(0.1, 0.72) ? "closed" : during(0.72, 1.2) ? "wide" : "open"
    if (during(0.72, 1.1)) { p.leftArm = "high"; p.rightArm = "high" }
    break
  case "shy":
    p.tilt = keys([[0, 0], [0.25, -10], [1.2, -10], [1.5, 0]])
    p.scale = keys([[0, 1], [0.25, 0.9], [1.2, 0.9], [1.5, 1]])
    p.shift = keys([[0, 0], [0.25, -1], [1.2, -1], [1.5, 0]])
    p.eyes = during(0.7, 1) ? "wink" : during(0.2, 1.3) ? "left" : "open"
    break
  case "hiccup":
    var starts = [0.2, 0.9, 1.35]
    for (var s = 0; s < starts.length; s++) {
      if (!during(starts[s], starts[s] + 0.3)) continue
      p.lift = arc(starts[s], 0.18, 1.5)
      p.eyes = "wide"
      if (during(starts[s], starts[s] + 0.18)) p.legs = "tucked"
    }
    break
  case "heartbeat":
    // Lub-dub, twice.
    p.scale = 1 + arc(0, 0.14, 0.15) + arc(0.18, 0.14, 0.1) + arc(0.7, 0.14, 0.15) + arc(0.88, 0.14, 0.1)
    break
  case "dizzy":
    if (t < 1.6) {
      p.tilt = 10 * wave(0.6)
      p.shift = Math.cos(2 * Math.PI * t / 0.6)
      p.eyes = beat(0.12) ? "left" : "right"
    } else {
      p.eyes = "closed"
      p.stretch = keys([[1.6, 1], [1.7, 0.85], [1.9, 1]])
    }
    break
  case "swim":
    p.lift = arc(0, 1.8, 2.5) + 0.5 * wave(0.45)
    p.leftArm = beat(0.225) ? "raised" : "down"
    p.rightArm = p.leftArm
    if (during(0.2, 1.6)) p.legs = "tucked"
    break
  }
  return p
}

function eyeColumns(eyes) {
  switch (eyes) {
  case "closed": return []
  case "left": return [3, 10]
  case "right": return [5, 12]
  case "wide": return [4, 5, 10, 11]
  case "wink": return [4]
  default: return [4, 11]
  }
}

// The pixel rows for a pose, as lists of filled columns: eyes are the gaps in the second row,
// arms the two pixels either side of the third, and legs the bottom row.
function rows(p) {
  p = p || restingPose()
  var eyes = eyeColumns(p.eyes)
  var out = [
    range(2, 13),
    range(2, 13).filter(function(column) { return eyes.indexOf(column) === -1 }),
    range(0, 15),
    range(2, 13),
    [3, 5, 10, 12]
  ]
  var arms = [[p.leftArm, [0, 1], 0], [p.rightArm, [14, 15], 15]]
  for (var i = 0; i < arms.length; i++) {
    var arm = arms[i][0], columns = arms[i][1], outer = arms[i][2]
    if (arm === "raised") {
      out[1] = out[1].concat(columns)
    } else if (arm === "high") {
      // Straight up along the outer column, apart from the body so it doesn't read as a hat.
      out[0].push(outer)
      out[1].push(outer)
    } else {
      continue
    }
    out[2] = out[2].filter(function(column) { return columns.indexOf(column) === -1 })
  }
  switch (p.legs) {
  case "stepLeft": out[4] = [3, 10]; break
  case "stepRight": out[4] = [5, 12]; break
  case "tucked": out[4] = []; break
  case "wide": out[4] = [2, 13]; break
  }
  return out
}

// Every cell of the 16×5 grid, row by row: EMPTY, BODY, or EYE (the eye gaps, drawn dark on the
// coloured mascot and left see-through otherwise).
function cells(p) {
  p = p || restingPose()
  var body = rows(p)
  var eyes = eyeColumns(p.eyes)
  var out = []
  for (var row = 0; row < ROWS; row++) {
    for (var column = 0; column < COLUMNS; column++) {
      if (body[row].indexOf(column) !== -1) out.push(BODY)
      else if (row === 1 && eyes.indexOf(column) !== -1) out.push(EYE)
      else out.push(EMPTY)
    }
  }
  return out
}
