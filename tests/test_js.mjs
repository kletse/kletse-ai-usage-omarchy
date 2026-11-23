// Tests for the widget's pure JavaScript (Model.js, Mascot.js). Run: node --test tests/
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";

function load(name) {
  // QML's `.pragma library` line isn't JavaScript.
  const source = readFileSync(new URL(`../${name}`, import.meta.url), "utf8").replace(/^\.pragma library\s*$/m, "");
  const context = { Math, Number, String, Array, Object, JSON, isFinite };
  vm.createContext(context);
  vm.runInContext(source, context, { filename: name });
  return context;
}

const Model = load("Model.js");
const Clawd = load("Mascot.js");
const plain = (value) => JSON.parse(JSON.stringify(value));

test("levels follow the 75% and 90% thresholds", () => {
  assert.deepEqual([0, 74.9, 75, 89.9, 90, 140, "x"].map(Model.level),
    ["normal", "normal", "warning", "warning", "critical", "critical", "normal"]);
  assert.equal(Model.percentText(42.5), "43%");
  assert.equal(Model.percentText(-3), "0%");
  assert.equal(Model.percentText(250), "100%");
});

test("reset countdowns and ages", () => {
  const now = 1_800_000_000_000;
  const at = (seconds) => now / 1000 + seconds;
  assert.equal(Model.untilText(at(2 * 86400 + 3 * 3600 + 59), now), "2d 3h");
  assert.equal(Model.untilText(at(4 * 3600 + 12 * 60), now), "4h 12m");
  assert.equal(Model.untilText(at(59), now), "0m");
  assert.equal(Model.untilText(at(-100), now), "0m");
  assert.deepEqual(plain(Model.age(at(-30), now)), { unit: "now", value: 0 });
  assert.deepEqual(plain(Model.age(at(-5 * 60), now)), { unit: "m", value: 5 });
  assert.deepEqual(plain(Model.age(at(-3 * 3600), now)), { unit: "h", value: 3 });
  assert.deepEqual(plain(Model.age(at(-2 * 86400), now)), { unit: "d", value: 2 });
});

test("bar segments put a dot between groups", () => {
  const accounts = [
    { id: "a", provider: "claude", group: "Work", menuText: "12%", headline: { usedPercent: 12 } },
    { id: "b", provider: "codex", group: "Work", menuText: "80%", headline: { usedPercent: 80 } },
    { id: "c", provider: "claude", group: "Personal", menuText: "–" },
    { id: "d", provider: "codex" },
  ];
  const segments = plain(Model.segments(accounts));
  assert.deepEqual(segments.map((s) => s.kind === "separator" ? "·" : `${s.key}:${s.text}:${s.level}`),
    ["a:12%:normal", "b:80%:warning", "·", "c:–:normal", "·", "d:–:normal"]);
  assert.deepEqual(plain(Model.segments(null)), []);
  assert.equal(Model.startsGroup(accounts, 0), true);
  assert.equal(Model.startsGroup(accounts, 1), false);
  assert.equal(Model.startsGroup(accounts, 2), true);
  assert.equal(Model.startsGroup(accounts, 3), false);
});

test("only Claude usage changes to a real value animate", () => {
  const before = Model.segments([
    { id: "a", provider: "claude", menuText: "10%" },
    { id: "b", provider: "codex", menuText: "10%" },
    { id: "c", provider: "claude", menuText: "10%" },
  ]);
  const after = Model.segments([
    { id: "a", provider: "claude", menuText: "11%" },
    { id: "b", provider: "codex", menuText: "12%" },
    { id: "c", provider: "claude", menuText: "–" },
  ]);
  assert.deepEqual(plain(Model.changedClaudeSegments(before, after)), [0]);
  assert.deepEqual(plain(Model.changedClaudeSegments([], after)), []);
  assert.deepEqual(plain(Model.changedClaudeSegments(before, after.slice(0, 2))), []);
});

test("theme colors and status parsing", () => {
  const colors = Model.themeColors('mode = "dark"\ngreen = "#608f76"\nred="#8A563E" # comment\nbad = "blue"\n');
  assert.deepEqual(plain(colors), { green: "#608f76", red: "#8A563E" });
  assert.equal(Model.parseStatus("{"), null);
  assert.equal(Model.parseStatus('{"version":2}'), null);
  assert.deepEqual(plain(Model.parseStatus('{"version":1,"accounts":[1,{"id":"a"},null]}').accounts), [{ id: "a" }]);
  assert.deepEqual(plain(Model.parseStatus('{"version":1}').accounts), []);
  assert.equal(Model.metaLine({ identity: "you@example.com", plan: "Max" }), "you@example.com · Max");
  assert.equal(Model.metaLine({ plan: "Pro" }), "Pro");
});

// The resting mascot is the one Claude Code prints: ▐▛███▜▌ / ▝▜█████▛▘ / ▘▘ ▝▝.
test("the resting mascot", () => {
  const cells = Clawd.cells(Clawd.restingPose());
  const art = [];
  for (let row = 0; row < 5; row++) {
    art.push(cells.slice(row * 16, row * 16 + 16).map((c) => [" ", "#", "o"][c]).join(""));
  }
  assert.deepEqual(art, [
    "  ############  ",
    "  ##o######o##  ",
    "################",
    "  ############  ",
    "   # #    # #   ",
  ]);
});

test("arms, legs and eyes", () => {
  const pose = Object.assign(Clawd.restingPose(), { leftArm: "raised", rightArm: "high", legs: "wide", eyes: "wide" });
  const rows = plain(Clawd.rows(pose));
  assert.deepEqual(rows[0], [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 15]);
  assert.deepEqual(rows[1].slice().sort((a, b) => a - b), [0, 1, 2, 3, 6, 7, 8, 9, 12, 13, 15]);
  assert.deepEqual(rows[2], [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13]);
  assert.deepEqual(rows[4], [2, 13]);
  assert.deepEqual(plain(Clawd.eyeColumns("wink")), [4]);
  assert.deepEqual(plain(Clawd.rows(Object.assign(Clawd.restingPose(), { legs: "tucked" })))[4], []);
});

test("every animation is defined, moves back to rest, and stays in bounds", () => {
  assert.equal(Clawd.animations.length, 35);
  assert.equal(new Set(Clawd.animations.map((a) => a.id)).size, 35);
  const rest = plain(Clawd.restingPose());
  for (const { id, duration } of Clawd.animations) {
    let moved = false;
    for (let t = 0; t <= duration; t += 1 / 30) {
      const pose = Clawd.pose(id, t);
      if (JSON.stringify(plain(pose)) !== JSON.stringify(rest)) moved = true;
      for (const key of ["lift", "shift", "tilt", "scale", "stretch", "opacity"]) {
        assert.ok(Number.isFinite(pose[key]), `${id} ${key} at ${t}`);
      }
      assert.ok(Math.abs(pose.lift) <= 4 && Math.abs(pose.shift) <= 3, `${id} moves too far at ${t}`);
      assert.ok(pose.opacity >= 0 && pose.opacity <= 1, `${id} opacity at ${t}`);
    }
    assert.ok(moved, `${id} never moves`);
    const end = plain(Clawd.pose(id, duration + 0.01));
    for (const key of ["lift", "shift", "scale", "stretch", "opacity"]) {
      assert.ok(Math.abs(end[key] - rest[key]) < 0.1, `${id} doesn't come back to rest (${key} ${end[key]})`);
    }
    assert.ok(Math.abs(end.tilt % 360) < 0.5, `${id} ends tilted (${end.tilt})`);
    // Eyes, arms and legs may end mid-pose (walk ends looking right, as on macOS); the player
    // drops a finished animation, which puts them back at rest.
  }
  assert.equal(Clawd.pose("nope", 0.5).lift, 0);
});

test("spot checks against the macOS timings", () => {
  assert.equal(Clawd.pose("hop", 0.18).lift, 3);
  assert.equal(Clawd.pose("hop", 0.18).legs, "tucked");
  assert.equal(Clawd.pose("hop", 0.8).eyes, "closed");
  assert.ok(Math.abs(Clawd.pose("spin", 0.45).tilt - 180) < 1e-9);
  assert.ok(Math.abs(Clawd.pose("backflip", 0.475).tilt + 180) < 1e-9);
  assert.equal(Clawd.pose("walk", 0.35).shift, -1);
  assert.equal(Clawd.pose("jumpingJacks", 0.1).legs, "wide");
  assert.equal(Clawd.pose("jumpingJacks", 0.3).legs, "standing");
});

test("assign deals out different animations", () => {
  let seed = 1;
  const random = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
  const ids = plain(Clawd.assign(4, random));
  assert.equal(ids.length, 4);
  assert.equal(new Set(ids).size, 4);
  assert.equal(plain(Clawd.assign(40, random)).length, 40);
});

test("lists QML hands back count as lists", () => {
  // A QML sequence wrapper is array-like but not an Array.
  const wrapper = { length: 2, 0: { id: "a", provider: "claude", menuText: "1%" }, 1: { id: "b", provider: "claude", menuText: "2%" } };
  assert.equal(Model.isList(wrapper), true);
  assert.equal(Model.isList("text"), false);
  assert.equal(Model.isList(null), false);
  const before = Model.segments([{ id: "a", provider: "claude", menuText: "1%" }]);
  const after = Model.segments([{ id: "a", provider: "claude", menuText: "5%" }]);
  const asWrapper = (list) => Object.assign({ length: list.length }, list);
  assert.deepEqual(plain(Model.changedClaudeSegments(asWrapper(before), asWrapper(after))), [0]);
});
