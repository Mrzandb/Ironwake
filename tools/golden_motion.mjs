// Golden numbers for the movement / gait / terrain port.
//
// Imports Game_test@33f4be8 kinematics, gait, terrain, pose and the mobility
// formula. Collide is the movement half of src/sim/world.ts (vehicle circles,
// terrain push, arena clamp). World itself cannot be imported: its constructor
// uses TypeScript parameter properties, which Node's strip-types loader rejects.
//
//   node tools/golden_motion.mjs --snapshot /path/to/Game_test
//
// Compare in GDScript with absolute tolerance 1e-9.

import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));

function relaunch() {
  const flag = process.execArgv.includes("--experimental-strip-types");
  const hooked = process.execArgv.some((arg) => arg.includes("register_ts.mjs"));
  if (flag && hooked) {
    return;
  }
  const child = spawnSync(
    process.execPath,
    [
      "--experimental-strip-types",
      "--import",
      path.join(HERE, "register_ts.mjs"),
      fileURLToPath(import.meta.url),
      ...process.argv.slice(2),
    ],
    { stdio: "inherit" },
  );
  process.exit(child.status === null ? 1 : child.status);
}

relaunch();

function parseArgs(argv) {
  let snapshot = "";
  let out = path.join(HERE, "..", "tests", "motion_golden.json");
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--snapshot") snapshot = argv[++i] ?? "";
    else if (arg === "--out") out = argv[++i] ?? "";
    else throw new Error("unknown argument " + arg);
  }
  if (!snapshot) throw new Error("missing --snapshot");
  return { snapshot: path.resolve(snapshot), out: path.resolve(out) };
}

const { snapshot, out } = parseArgs(process.argv.slice(2));

async function load(rel) {
  return import(pathToFileURL(path.join(snapshot, rel)).href);
}

const kin = await load("src/sim/movement/kinematics.ts");
const gait = await load("src/sim/movement/gait.ts");
const terrainMod = await load("src/sim/terrain/terrain.ts");
const pose = await load("src/sim/vehicle/pose.ts");
const legs = await load("src/sim/vehicle/legs.ts");
const poly = await load("src/sim/geometry/poly.ts");
const modules = await load("src/sim/combat/modules.ts");
const angle = await load("src/core/math/angle.ts");
const loop = await load("src/core/loop.ts");
const command = await load("src/sim/command.ts");
const bulwarkMod = await load("src/data/vehicles/bulwark.ts");
const hawkMod = await load("src/data/vehicles/hawk.ts");
const swarmMod = await load("src/data/vehicles/swarm.ts");
const hillsMod = await load("src/data/maps/hills.ts");
const structures = await load("src/data/structures.ts");
const rules = await load("src/data/rules.ts");

const { stepBody, FULL_MOBILITY } = kin;
const { initGait, stepGait } = gait;
const { Terrain, pointInPolygon, closestOnPolygon } = terrainMod;
const { firstHit, ZERO_POSE } = pose;
const { legParts } = legs;
const { insetConvex, signedArea, segmentVsConvex } = poly;
const { mobilityOf, initModules } = modules;
const { angleDelta, clamp } = angle;
const DT = loop.DT;
const IDLE = command.IDLE;
const bulwark = bulwarkMod.bulwark;
const hawk = hawkMod.hawk;
const swarm = swarmMod.swarm;
const hills = hillsMod.hills;

const defs = {
  bulwark,
  swarm,
  hawk,
  hawkB: hawkMod.hawkB,
  hawkC: hawkMod.hawkC,
  base0: structures.baseDef(0),
  base1: structures.baseDef(1),
};

function cmd(partial) {
  return { ...IDLE, ...partial };
}

let nextId = 1;
function make(def, pos, heading) {
  const vehicle = {
    id: nextId++,
    def,
    alive: true,
    pos: { x: pos.x, y: pos.y },
    vel: { x: 0, y: 0 },
    heading,
    angVel: 0,
    speed: 0,
    legs: [],
    down: new Set(),
    mods: { ...FULL_MOBILITY },
    modules: initModules(def),
  };
  vehicle.legs = initGait(def, vehicle);
  return vehicle;
}

function collide(vehicles, terrain, arena) {
  for (let i = 0; i < vehicles.length; i++) {
    for (let j = i + 1; j < vehicles.length; j++) {
      const a = vehicles[i];
      const b = vehicles[j];
      const dx = b.pos.x - a.pos.x;
      const dy = b.pos.y - a.pos.y;
      const d = Math.hypot(dx, dy) || 1e-6;
      const overlap = a.def.collisionRadius + b.def.collisionRadius - d;
      if (overlap <= 0) continue;
      const sa = a.def.locomotion === "static";
      const sb = b.def.locomotion === "static";
      if (sa && sb) continue;
      const nx = dx / d;
      const ny = dy / d;
      const wa = sa ? 0 : sb ? 1 : b.def.collisionRadius / (a.def.collisionRadius + b.def.collisionRadius);
      a.pos = { x: a.pos.x - nx * overlap * wa, y: a.pos.y - ny * overlap * wa };
      b.pos = { x: b.pos.x + nx * overlap * (1 - wa), y: b.pos.y + ny * overlap * (1 - wa) };
      for (const [v, s] of [
        [a, 1],
        [b, -1],
      ]) {
        const vn = (v.vel.x * nx + v.vel.y * ny) * s;
        if (vn > 0) v.vel = { x: v.vel.x - nx * vn * s, y: v.vel.y - ny * vn * s };
      }
    }
  }
  for (const v of vehicles) {
    const r = v.def.collisionRadius;
    if (v.def.locomotion !== "static") {
      for (let k = 0; k < 3; k++) {
        const h = terrain.pushCircle(v.pos, r);
        if (!h) break;
        v.pos = h.pos;
        const vn = v.vel.x * h.n.x + v.vel.y * h.n.y;
        if (vn < 0) v.vel = { x: v.vel.x - h.n.x * vn, y: v.vel.y - h.n.y * vn };
      }
    }
    const x = Math.min(Math.max(v.pos.x, r), arena.w - r);
    const y = Math.min(Math.max(v.pos.y, r), arena.h - r);
    if (x !== v.pos.x) v.vel = { x: 0, y: v.vel.y };
    if (y !== v.pos.y) v.vel = { x: v.vel.x, y: 0 };
    v.pos = { x, y };
  }
}

function stepAll(vehicles, terrain, arena, commands) {
  let plants = 0;
  for (const v of vehicles) {
    const order = commands.get(v.id) ?? IDLE;
    if (v.def.locomotion !== "static") stepBody(v.def, v, order, v.mods, DT);
  }
  collide(vehicles, terrain, arena);
  for (const v of vehicles) {
    const ev = [];
    stepGait(v.def, v, v.legs, DT, ev, (id) => v.alive && !v.down.has(id));
    plants += ev.length;
  }
  return plants;
}

function runPhases(def, origin, heading, phases, arena = { w: 20000, h: 20000 }, map = null) {
  const terrain = new Terrain(map);
  const vehicle = make(def, origin, heading);
  for (const phase of phases) {
    const order = cmd({ throttle: phase.throttle ?? 0, turn: phase.turn ?? 0, strafe: phase.strafe ?? 0 });
    for (let i = 0; i < phase.ticks; i++) {
      stepAll([vehicle], terrain, arena, new Map([[vehicle.id, order]]));
    }
  }
  return vehicle;
}

function bodyOf(v) {
  return {
    x: v.pos.x,
    y: v.pos.y,
    vx: v.vel.x,
    vy: v.vel.y,
    heading: v.heading,
    angVel: v.angVel,
    speed: v.speed,
  };
}

function feetOf(v) {
  const out = {};
  for (const leg of v.legs) out[leg.id] = [leg.foot.x, leg.foot.y];
  return out;
}

const square = [
  { x: 0, y: 0 },
  { x: 10, y: 0 },
  { x: 10, y: 10 },
  { x: 0, y: 10 },
];
const inset = insetConvex(square, 2);
const seg = segmentVsConvex({ x: -10, y: 5 }, { x: 20, y: 5 }, square);
const shield = firstHit(bulwark, ZERO_POSE, { x: 400, y: 0 }, { x: -400, y: 0 }, (m) => !m.movingPart);
const arm = firstHit(bulwark, ZERO_POSE, { x: 400, y: 29 }, { x: -400, y: 29 }, (m) => !m.movingPart);
const fl = bulwark.modules.find((m) => m.id === "legFL");
const lifted = legParts(fl.leg.hip, fl.leg.foot, fl.leg.spec, 1);

const singles = [
  ["bulwark_throttle_240", "bulwark", [{ ticks: 240, throttle: 1 }]],
  ["bulwark_throttle_turn_180", "bulwark", [{ ticks: 180, throttle: 1, turn: 1 }]],
  ["bulwark_coast", "bulwark", [{ ticks: 240, throttle: 1 }, { ticks: 60 }]],
  ["hawk_slide", "hawk", [{ ticks: 180, throttle: 1 }, { ticks: 90, turn: 1 }]],
  ["hawk_strafe_240", "hawk", [{ ticks: 240, strafe: 1 }]],
  ["hawk_coast", "hawk", [{ ticks: 180, throttle: 1 }, { ticks: 60 }]],
  ["swarm_strafe_300", "swarm", [{ ticks: 300, throttle: 1, strafe: 1 }]],
  ["swarm_turn_300", "swarm", [{ ticks: 300, throttle: 1, turn: 1 }]],
  ["swarm_spin_180", "swarm", [{ ticks: 180, turn: 1 }]],
  ["swarm_accel_60", "swarm", [{ ticks: 60, throttle: 1 }]],
  ["swarm_coast", "swarm", [{ ticks: 240, throttle: 1 }, { ticks: 120 }]],
].map(([name, id, phases]) => {
  const vehicle = runPhases(defs[id], { x: 10000, y: 10000 }, 0, phases);
  return { name, vehicle: id, x: 10000, y: 10000, heading: 0, phases, end: bodyOf(vehicle) };
});

const arena = { w: 20000, h: 20000 };
const empty = new Terrain(null);
const gaitVehicle = make(bulwark, { x: 10000, y: 10000 }, 0);
const gaitCmds = [
  cmd({ throttle: 1 }),
  cmd({ throttle: 1, turn: 1 }),
  cmd({ turn: -1 }),
  cmd({ throttle: -1 }),
];
let plants = 0;
let maxGroups = 0;
for (const order of gaitCmds) {
  for (let i = 0; i < 240; i++) {
    plants += stepAll([gaitVehicle], empty, arena, new Map([[gaitVehicle.id, order]]));
    const groups = new Set(gaitVehicle.legs.filter((l) => l.stepping).map((l) => l.group));
    maxGroups = Math.max(maxGroups, groups.size);
  }
}

const frozen = make(bulwark, { x: 10000, y: 10000 }, 0);
frozen.modules.legFR.state = "DESTROYED";
frozen.down.add("legFR");
frozen.mods = mobilityOf(frozen);
const toWorld = (v, p) => {
  const c = Math.cos(v.heading);
  const s = Math.sin(v.heading);
  return { x: v.pos.x + p.x * c - p.y * s, y: v.pos.y + p.x * s + p.y * c };
};
const hipDist = (v) => {
  const hip = bulwark.modules.find((m) => m.id === "legFR").leg.hip;
  const leg = v.legs.find((l) => l.id === "legFR");
  const h = toWorld(v, hip);
  return Math.hypot(leg.foot.x - h.x, leg.foot.y - h.y);
};
const throttle = cmd({ throttle: 1 });
for (let i = 0; i < 6; i++) stepAll([frozen], empty, arena, new Map([[frozen.id, throttle]]));
const d0 = hipDist(frozen);
for (let i = 0; i < 600; i++) stepAll([frozen], empty, arena, new Map([[frozen.id, throttle]]));
const moved = Math.hypot(frozen.pos.x - 10000, frozen.pos.y - 10000);
for (let i = 0; i < 240; i++) stepAll([frozen], empty, arena, new Map([[frozen.id, cmd({ throttle: 1, turn: 1 })]]));
const d1 = hipDist(frozen);

const pairTerrain = new Terrain(null);
const pairA = make(bulwark, { x: 9000, y: 10000 }, 0);
const pairB = make(hawk, { x: 9400, y: 10000 }, Math.PI);
for (let i = 0; i < 600; i++) {
  const s = Math.sin(i / 37);
  stepAll([pairA, pairB], pairTerrain, arena, new Map([
    [pairA.id, cmd({ throttle: s, turn: Math.cos(i / 53) })],
    [pairB.id, cmd({ throttle: 1, turn: s, strafe: -1 })],
  ]));
}

function polyGap(a, b) {
  if (a.some((v) => pointInPolygon(v, b)) || b.some((v) => pointInPolygon(v, a))) {
    return { d: 0, p: a[0], q: a[0] };
  }
  let best = { d: Infinity, p: a[0], q: b[0] };
  for (const [P, Q, swap] of [
    [a, b, false],
    [b, a, true],
  ]) {
    for (const v of P) {
      const c = closestOnPolygon(v, Q);
      if (c.d < best.d) best = swap ? { d: c.d, p: c.q, q: v } : { d: c.d, p: v, q: c.q };
    }
  }
  return best;
}

const byId = new Map(hills.obstacles.map((o) => [o.id, o]));
function clusters() {
  const ids = hills.obstacles.map((o) => o.id);
  const parent = new Map(ids.map((i) => [i, i]));
  const find = (i) => (parent.get(i) === i ? i : find(parent.get(i)));
  for (let i = 0; i < ids.length; i++) {
    for (let j = i + 1; j < ids.length; j++) {
      if (polyGap(byId.get(ids[i]).poly, byId.get(ids[j]).poly).d <= 1) parent.set(find(ids[i]), find(ids[j]));
    }
  }
  const out = new Map();
  for (const i of ids) {
    const root = find(i);
    out.set(root, [...(out.get(root) ?? []), i]);
  }
  return [...out.values()];
}
const groups = clusters();
const groupW1 = groups.find((g) => g.includes("w1")).slice().sort();
const groupW3 = groups.find((g) => g.includes("w3")).slice().sort();
let narrow = Infinity;
let bestGap = null;
for (let i = 0; i < groups.length; i++) {
  for (let j = i + 1; j < groups.length; j++) {
    for (const a of groups[i]) {
      for (const b of groups[j]) {
        const g = polyGap(byId.get(a).poly, byId.get(b).poly);
        if (g.d < narrow) {
          narrow = g.d;
          bestGap = g;
        }
      }
    }
  }
}
const mid = { x: (bestGap.p.x + bestGap.q.x) / 2, y: (bestGap.p.y + bestGap.q.y) / 2 };
const gapLen = bestGap.d;
const gapN = { x: -(bestGap.q.y - bestGap.p.y) / gapLen, y: (bestGap.q.x - bestGap.p.x) / gapLen };
const hillsArena = { w: hills.size.w, h: hills.size.h };
const hillsTerrain = new Terrain(hills);
const start = { x: mid.x - gapN.x * 450, y: mid.y - gapN.y * 450 };
const end = { x: mid.x + gapN.x * 450, y: mid.y + gapN.y * 450 };
const driver = make(bulwark, start, Math.atan2(gapN.y, gapN.x));
let arrived = false;
let arriveTick = -1;
for (let i = 0; i < 25 * 60; i++) {
  const want = Math.atan2(end.y - driver.pos.y, end.x - driver.pos.x);
  const err = angleDelta(driver.heading, want);
  const order = cmd({ turn: clamp(err * 3, -1, 1), throttle: Math.abs(err) < 0.3 ? 1 : 0 });
  stepAll([driver], hillsTerrain, hillsArena, new Map([[driver.id, order]]));
  if (Math.hypot(end.x - driver.pos.x, end.y - driver.pos.y) < 60) {
    arrived = true;
    arriveTick = i;
    break;
  }
}

const rocks = [];
for (const id of ["bulwark", "hawk", "swarm"]) {
  const rockTerrain = new Terrain(hills);
  const rock = make(defs[id], { x: 5500 - 900, y: 4300 }, 0);
  let touched = false;
  let minClear = Infinity;
  const rockPoly = byId.get("rF").poly;
  for (let i = 0; i < 15 * 60; i++) {
    stepAll([rock], rockTerrain, hillsArena, new Map([[rock.id, cmd({ throttle: 1 })]]));
    const clear = closestOnPolygon(rock.pos, rockPoly).d;
    minClear = Math.min(minClear, clear);
    if (clear < defs[id].collisionRadius + 2) touched = true;
  }
  rocks.push({
    vehicle: id,
    touched,
    inside: pointInPolygon(rock.pos, rockPoly),
    minClear,
    end: { x: rock.pos.x, y: rock.pos.y },
  });
}

const baseTerrain = new Terrain(hills);
const base = make(structures.baseDef(1), { x: 9330, y: 760 }, 0);
const pusher = make(swarm, { x: 9330 - 400, y: 760 }, 0);
for (let i = 0; i < 4 * 60; i++) {
  stepAll([base, pusher], baseTerrain, hillsArena, new Map([[pusher.id, cmd({ throttle: 1, secondaries: false })]]));
}
const baseSep = Math.hypot(pusher.pos.x - base.pos.x, pusher.pos.y - base.pos.y);

const orbitArena = { w: 8000, h: 8000 };
const orbitTerrain = new Terrain(null);
const orbitRadius = 600;
const anchor = make(bulwark, { x: 4000, y: 4000 }, 0);
const flyer = make(hawk, { x: 4000, y: 4000 - orbitRadius - 200 }, Math.PI / 2);
const nose = (50 * Math.PI) / 180;
let distSum = 0;
let samples = 0;
for (let i = 0; i < 30 * 60; i++) {
  const dx = anchor.pos.x - flyer.pos.x;
  const dy = anchor.pos.y - flyer.pos.y;
  const d = Math.hypot(dx, dy) || 1;
  const bearing = Math.atan2(dy, dx);
  const m = flyer.def.move;
  const vmax = m.maxSpeed;
  const rx = dx / d;
  const ry = dy / d;
  const tx = -ry;
  const ty = rx;
  const radial = clamp((d - orbitRadius) * 1.5, -vmax, vmax);
  const vt = vmax * 0.85;
  const wantX = tx * vt + rx * radial;
  const wantY = ty * vt + ry * radial;
  const fx = Math.cos(flyer.heading);
  const fy = Math.sin(flyer.heading);
  const along = wantX * fx + wantY * fy;
  const side = -wantX * fy + wantY * fx;
  const throttleIn = clamp(along >= 0 ? along / vmax : along / (vmax * m.reverseRatio), -1, 1);
  const strafe = clamp(side / (vmax * m.strafeRatio), -1, 1);
  const turn = clamp(angleDelta(flyer.heading, bearing + nose) * 3, -1, 1);
  stepAll([anchor, flyer], orbitTerrain, orbitArena, new Map([
    [anchor.id, cmd({ secondaries: false })],
    [flyer.id, cmd({ throttle: throttleIn, turn, strafe })],
  ]));
  if (i > 10 * 60) {
    samples++;
    distSum += Math.hypot(flyer.pos.x - anchor.pos.x, flyer.pos.y - anchor.pos.y);
  }
}

const wallTerrain = new Terrain(hills);
const wall = wallTerrain.obstacles.find((o) => o.def.id === "w3");
const events = [];
wallTerrain.damage(wall, 24 * rules.RULES.terrain.heMul, { x: 0, y: 0 }, events);
const hpAfter = wall.hp;
wallTerrain.damage(wall, 1e9, { x: 0, y: 0 }, events);
const wallCenter = wall.def.poly.reduce(
  (s, v) => ({ x: s.x + v.x / wall.def.poly.length, y: s.y + v.y / wall.def.poly.length }),
  { x: 0, y: 0 },
);
const rock = wallTerrain.obstacles.find((o) => o.def.id === "rF");
const rockEvents = [];
wallTerrain.damage(rock, 1e9, { x: 0, y: 0 }, rockEvents);

const swarmNoTurret = {
  ...swarm,
  modules: swarm.modules.filter((m) => !m.turret),
};
const { vehicleRadius } = await load("src/sim/vehicle/validate.ts");

const doc = {
  tolerance: 1e-9,
  source: "Game_test@33f4be8 kinematics, gait, terrain, pose. Collide transcribed from world.ts.",
  geometry: {
    insetArea: Math.abs(signedArea(inset)),
    segmentT: seg.t,
    normalX: seg.normal.x,
    normalY: seg.normal.y,
  },
  hits: {
    shield: { id: shield.module.id, t: shield.t },
    arm: { id: arm.module.id, t: arm.t },
  },
  lift1Foot: [lifted[4][0].x, lifted[4][0].y],
  radii: {
    hawk: vehicleRadius(hawkMod.hawk),
    hawkB: vehicleRadius(hawkMod.hawkB),
    hawkC: vehicleRadius(hawkMod.hawkC),
    swarmNoTurret: vehicleRadius(swarmNoTurret),
  },
  mobility: {
    legFR: mobilityOf(frozen),
    trackR: (() => {
      const v = { id: 1, def: swarm, alive: true, modules: initModules(swarm), calm: 0 };
      v.modules.trackR.state = "DESTROYED";
      return mobilityOf(v);
    })(),
    bothTracks: (() => {
      const v = { id: 1, def: swarm, alive: true, modules: initModules(swarm), calm: 0 };
      v.modules.trackR.state = "DESTROYED";
      v.modules.trackL.state = "DESTROYED";
      return mobilityOf(v);
    })(),
  },
  single: singles,
  gait: {
    plants,
    maxGroups,
    end: bodyOf(gaitVehicle),
    feet: feetOf(gaitVehicle),
  },
  frozen: {
    speedMul: frozen.mods.speedMul,
    turnBias: frozen.mods.turnBias,
    d0,
    d1,
    moved,
    end: bodyOf(frozen),
  },
  pair: {
    a: bodyOf(pairA),
    b: bodyOf(pairB),
    feet: feetOf(pairA),
  },
  gap: {
    groupW1,
    groupW3,
    narrow,
    arrived,
    arriveTick,
    end: bodyOf(driver),
  },
  rocks,
  base: {
    x: base.pos.x,
    y: base.pos.y,
    swarm: bodyOf(pusher),
    separation: baseSep,
  },
  orbit: {
    average: distSum / samples,
    samples,
    end: bodyOf(flyer),
  },
  wall: {
    hpAfter36: hpAfter,
    alive: wall.alive,
    push: wallTerrain.pushCircle(wallCenter, 100) === null,
    blocked: wallTerrain.segmentHit({ x: wallCenter.x - 120, y: wallCenter.y }, { x: wallCenter.x + 120, y: wallCenter.y }) === null,
    rockAlive: rock.alive,
    rockEventDamage: rockEvents[0].damage,
  },
};

fs.writeFileSync(out, JSON.stringify(doc) + "\n");
console.log("wrote", out);
console.log("plants", plants, "maxGroups", maxGroups, "gap", arrived, arriveTick, "narrow", narrow);
console.log("orbit", doc.orbit.average, "samples", samples);
console.log("frozen moved", moved, "d0", d0, "d1", d1);
console.log("rocks", rocks.map((r) => r.vehicle + ":" + r.touched + ":" + r.minClear.toFixed(2)).join(" "));
