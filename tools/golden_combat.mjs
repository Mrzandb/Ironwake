// Golden numbers for the combat port.
//
// Imports Game_test@33f4be8 combat modules. World is loaded only after its
// constructor parameter properties are rewritten; Node's type stripper rejects
// those (AGENTS.md pit 21). Absolute tolerance in GDScript is 1e-9.
//
//   node tools/golden_combat.mjs --snapshot /path/to/Game_test

import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));

function relaunch() {
  const flag = process.execArgv.includes("--experimental-strip-types");
  const hooked = process.execArgv.some((arg) => arg.includes("register_ts.mjs"));
  if (flag && hooked) return;
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
  let out = path.join(HERE, "..", "tests", "combat_golden.json");
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

function patchWorld(root) {
  const file = path.join(root, "src/sim/world.ts");
  const src = fs.readFileSync(file, "utf8");
  if (!src.includes("readonly arena")) return;
  const old = `  constructor(
    readonly arena: { w: number; h: number },
    readonly seed = 1,
    readonly map: MapDef | null = null,
  ) {
    this.rng = makeStreams(seed);
    this.terrain = new Terrain(map);
  }`;
  const next = `  arena: { w: number; h: number };
  seed: number;
  map: MapDef | null;
  constructor(
    arena: { w: number; h: number },
    seed = 1,
    map: MapDef | null = null,
  ) {
    this.arena = arena;
    this.seed = seed;
    this.map = map;
    this.rng = makeStreams(seed);
    this.terrain = new Terrain(map);
  }`;
  if (!src.includes(old)) throw new Error("world.ts constructor did not match");
  fs.writeFileSync(file, src.replace(old, next));
}

patchWorld(snapshot);

async function load(rel) {
  return import(pathToFileURL(path.join(snapshot, rel)).href);
}

const pen = await load("src/sim/combat/penetration.ts");
const modules = await load("src/sim/combat/modules.ts");
const stats = await load("src/sim/stats/resolver.ts");
const turret = await load("src/sim/combat/turret.ts");
const worldMod = await load("src/sim/world.ts");
const command = await load("src/sim/command.ts");
const weapons = await load("src/data/weapons.ts");
const rulesMod = await load("src/data/rules.ts");
const bulwarkMod = await load("src/data/vehicles/bulwark.ts");
const hawkMod = await load("src/data/vehicles/hawk.ts");
const swarmMod = await load("src/data/vehicles/swarm.ts");
const hillsMod = await load("src/data/maps/hills.ts");
const structures = await load("src/data/structures.ts");
const angle = await load("src/core/math/angle.ts");

const { World } = worldMod;
const IDLE = command.IDLE;
const RULES = rulesMod.RULES;
const bulwark = bulwarkMod.bulwark;
const hawk = hawkMod.hawk;
const swarm = swarmMod.swarm;
const hills = hillsMod.hills;
const { deg } = angle;

const cmd = (partial) => ({ ...IDLE, ...partial });
const round = (value) => {
  if (typeof value !== "number" || !Number.isFinite(value)) return value;
  return Math.round(value * 1e12) / 1e12;
};

function num(value) {
  if (Array.isArray(value)) return value.map(num);
  if (value && typeof value === "object") {
    const out = {};
    for (const key of Object.keys(value)) out[key] = num(value[key]);
    return out;
  }
  if (typeof value === "number") {
    if (!Number.isFinite(value)) return value < 0 ? "-inf" : "inf";
    return round(value);
  }
  return value;
}

const penRows = [];
for (const dist of [0, 200, 400, 600, 800, 1000, 1200, 1600]) {
  penRows.push({
    p0: weapons.BULWARK_AP.p0,
    range: weapons.BULWARK_AP.range,
    dist,
    value: pen.penetrationAtDistance(weapons.BULWARK_AP.p0, weapons.BULWARK_AP.range, dist),
  });
}
for (const weapon of Object.values(weapons.WEAPONS)) {
  if (weapon.kind !== "kinetic") continue;
  for (const ammo of weapon.ammo) {
    if (ammo.kind !== "AP") continue;
    penRows.push({
      id: weapon.id,
      p0: ammo.p0,
      range: weapon.range,
      dist: weapon.range,
      value: pen.penetrationAtDistance(ammo.p0, weapon.range, weapon.range),
    });
  }
}

const effRows = [];
for (const degrees of [0, 45, 55, 60, 69]) {
  effRows.push({ armor: 320, deg: degrees, value: pen.effectiveArmor(320, deg(degrees)) });
}

const hitRows = [];
for (const [dist, degrees] of [
  [200, 0],
  [200, 60],
  [800, 0],
  [800, 0],
]) {
  const p = pen.penetrationAtDistance(weapons.BULWARK_AP.p0, weapons.BULWARK_AP.range, dist);
  hitRows.push({ dist, deg: degrees, armor: dist === 800 && hitRows.length > 2 ? 314 : 320, result: null });
}
hitRows.length = 0;
const table = [
  [200, 0, 320],
  [200, 45, 320],
  [200, 55, 320],
  [200, 60, 320],
  [400, 0, 320],
  [400, 45, 320],
  [600, 0, 320],
  [800, 0, 320],
  [800, 0, 314],
  [1600, 0, 320],
];
for (const [dist, degrees, armor] of table) {
  const p = pen.penetrationAtDistance(weapons.BULWARK_AP.p0, weapons.BULWARK_AP.range, dist);
  hitRows.push({ dist, deg: degrees, armor, result: pen.resolveHit(p, armor, deg(degrees)) });
}
hitRows.push({ dist: 0, deg: 69, armor: 320, pen: 9999, result: pen.resolveHit(9999, 320, deg(69)) });
hitRows.push({ dist: 0, deg: 80, armor: 70, pen: 446, k: RULES.overmatchK, result: pen.resolveHit(446, 70, deg(80), RULES.overmatchK) });
hitRows.push({ dist: 0, deg: 80, armor: 70, pen: 446, result: pen.resolveHit(446, 70, deg(80)) });
hitRows.push({ dist: 0, deg: 80, armor: 320, pen: 446, k: RULES.overmatchK, result: pen.resolveHit(446, 320, deg(80), RULES.overmatchK) });

const maxRows = [];
for (const armor of [320, 300, 280, 240, 200]) {
  maxRows.push({ armor, value: pen.maxPenDistance(weapons.BULWARK_AP.p0, weapons.BULWARK_AP.range, armor, 0) });
}

const heRows = [
  { hePen: 120, armor: 55, value: pen.heFactor(120, 55) },
  { hePen: 120, armor: 120, value: pen.heFactor(120, 120) },
  { hePen: 120, armor: 320, value: pen.heFactor(120, 320) },
  { hePen: 120, armor: 40, value: pen.heFactor(120, 40) },
];

const apDamage = pen.apPenDamage(100, 500, 320);

function holder() {
  return { mods: [] };
}
function modifier(partial) {
  return { id: "m", source: "test", appliesTo: "self", stack: "stack", ...partial };
}
const statHolder = holder();
stats.addModifier(statHolder, modifier({ stat: "range", op: { kind: "flat", v: 100 } }));
stats.addModifier(statHolder, modifier({ stat: "range", op: { kind: "mul", v: 2 } }));
stats.addModifier(statHolder, modifier({ stat: "range", op: { kind: "mul", v: 1.5 } }));
const statFlatMul = stats.stat(statHolder, "range", 1000);
stats.addModifier(statHolder, modifier({ stat: "range", op: { kind: "set", v: 500 } }));
const statSet = stats.stat(statHolder, "range", 1000);
const statReload = holder();
stats.addModifier(statReload, modifier({ stat: "reload", op: { kind: "mul", v: 0 } }));
const statClamp = stats.stat(statReload, "reload", 7);
const scoped = holder();
stats.addModifier(scoped, modifier({ stat: "reload", op: { kind: "mul", v: 0.5 }, module: "main" }));
const marked = holder();
const shooter = holder();
stats.addModifier(marked, modifier({ stat: "dispersion", op: { kind: "mul", v: 0.8 }, appliesTo: "target", source: "hawk.lock" }));
const refresh = holder();
stats.addModifier(refresh, modifier({ id: "r", stat: "damage", op: { kind: "mul", v: 1.2 }, stack: "refresh", duration: 1 }));
stats.tickModifiers(refresh, 0.8);
stats.addModifier(refresh, modifier({ id: "r", stat: "damage", op: { kind: "mul", v: 1.2 }, stack: "refresh", duration: 1 }));
const exclusive = holder();
stats.addModifier(exclusive, modifier({ id: "a", stat: "damage", op: { kind: "mul", v: 1.5 }, stack: "exclusive", source: "siege" }));
stats.addModifier(exclusive, modifier({ id: "b", stat: "damage", op: { kind: "mul", v: 1.2 }, stack: "exclusive", source: "siege" }));
const timed = holder();
stats.addModifier(timed, modifier({ stat: "damage", op: { kind: "mul", v: 2 }, duration: 0.5 }));
stats.addModifier(timed, modifier({ stat: "range", op: { kind: "mul", v: 2 }, source: "perm" }));
stats.tickModifiers(timed, 0.3);
const timedMid = stats.stat(timed, "damage", 10);
stats.tickModifiers(timed, 0.3);
const timedEnd = stats.stat(timed, "damage", 10);
stats.removeModifiers(timed, "perm");

const mod = (def = bulwark) => ({ id: 1, def, alive: true, modules: modules.initModules(def), calm: 0 });
const findMod = (v, id) => v.def.modules.find((m) => m.id === id);
const legVehicle = mod();
const legEvents = [];
modules.applyDamage(legVehicle, findMod(legVehicle, "legFR"), { struct: 150, stun: 120, erode: 0 }, 0, legEvents);
const legAfterOne = { ...legVehicle.modules.legFR };
modules.applyDamage(legVehicle, findMod(legVehicle, "legFR"), { struct: 150, stun: 120, erode: 0 }, 0.5, legEvents);
const legDisabled = { ...legVehicle.modules.legFR };
for (let i = 0; i < 11.9 * 60; i++) modules.tickModules(legVehicle, 1 / 60, 0.5 + i / 60, []);
const legBeforeReboot = legVehicle.modules.legFR.state;
for (let i = 0; i < 0.2 * 60; i++) modules.tickModules(legVehicle, 1 / 60, 12.4 + i / 60, []);
const legAfterReboot = { ...legVehicle.modules.legFR };
modules.applyDamage(legVehicle, findMod(legVehicle, "legFR"), { struct: 150, stun: 120, erode: 0 }, 13, []);
const legFinal = legVehicle.modules.legFR.state;

const decay = mod();
modules.applyDamage(decay, findMod(decay, "legFL"), { struct: 0, stun: 100, erode: 0 }, 0, []);
for (let i = 0; i < 2 * 60; i++) modules.tickModules(decay, 1 / 60, i / 60, []);
const stunAt2 = decay.modules.legFL.stun;
for (let i = 0; i < 60; i++) modules.tickModules(decay, 1 / 60, 2 + i / 60, []);
const stunAt3 = decay.modules.legFL.stun;

const host = mod();
const hostEvents = [];
modules.applyDamage(host, findMod(host, "armR"), { struct: 9999, stun: 0, erode: 0 }, 0, hostEvents);
const hostStates = {
  secR: host.modules.secR.state,
  armR: host.modules.armR.state,
};
modules.applyDamage(host, findMod(host, "core"), { struct: 9999, stun: 0, erode: 0 }, 0, hostEvents);
const coreKill = {
  alive: host.alive,
  mainGun: host.modules.mainGun.state,
  killed: hostEvents.some((e) => e.t === "vehicleDestroyed"),
};

const floorV = mod();
modules.applyDamage(floorV, findMod(floorV, "armR"), { struct: 0, stun: 0, erode: 10000 }, 0, []);

const repairV = mod();
const leg = repairV.def.modules.find((m) => m.kind === "locomotion");
modules.destroyModule(repairV, leg, []);
repairV.calm = 0;
const repairSeconds = RULES.reboot.large * RULES.repair.timeMul;
for (let i = 0; i < (repairSeconds - 0.5) * 60; i++) modules.tickModules(repairV, 1 / 60, i / 60, []);
const repairPending = repairV.modules[leg.id].state;
for (let i = 0; i < 60; i++) modules.tickModules(repairV, 1 / 60, i / 60, []);
const repaired = { ...repairV.modules[leg.id] };

const ARENA = { w: 30000, h: 30000 };

function body(v) {
  const modulesOut = {};
  for (const m of v.def.modules) {
    const rt = v.modules[m.id];
    modulesOut[m.id] = { armor: rt.armor, structure: rt.structure, stun: rt.stun, state: rt.state };
  }
  const weaponsOut = {};
  for (const id of Object.keys(v.weapons)) {
    const w = v.weapons[id];
    weaponsOut[id] = {
      reload: w.reload,
      ammo: w.ammo,
      disp: w.disp,
      heat: w.heat,
      inArc: w.inArc,
      aimErr: w.aimErr,
      aimVehicle: w.aimVehicle,
      aimModule: w.aimModule,
      pending: w.pending,
    };
  }
  return {
    pos: v.pos,
    vel: v.vel,
    heading: v.heading,
    crown: v.crownAngle,
    speed: v.speed,
    alive: v.alive,
    slot: v.slot,
    lock: v.lock,
    calm: v.calm,
    turrets: { ...v.turretAngles },
    modules: modulesOut,
    weapons: weaponsOut,
  };
}

function shells(w) {
  return w.projectiles.map((p) => ({
    pos: p.pos,
    vel: p.vel,
    travelled: p.travelled,
    range: p.range,
    ammo: p.ammo,
    weapon: p.weapon,
  }));
}

const one = new World(ARENA, 1);
const gunner = one.spawn(bulwark, 0, { x: 15000, y: 15000 }, 0);
one.step(new Map([[gunner.id, cmd({ aim: { x: 20000, y: 15000 }, fire: true, secondaries: false })]]));
const oneShot = { shooter: body(gunner), projectiles: shells(one), beams: one.beams.length };
for (let i = 0; i < 30; i++) one.step(new Map([[gunner.id, cmd({ aim: { x: 20000, y: 15000 }, secondaries: false })]]));
const oneLater = { projectiles: shells(one), shooter: { pos: gunner.pos, heading: gunner.heading, crown: gunner.crownAngle } };

const slotWorld = new World(ARENA, 1);
const slotted = slotWorld.spawn(bulwark, 0, { x: 15000, y: 15000 }, 0);
slotWorld.step(new Map([[slotted.id, cmd({ slot: 7 })]]));
const slotClamp = slotted.slot;
slotWorld.step(new Map([[slotted.id, cmd({ slot: 1 })]]));
const slotAmmo = { ammo: slotted.weapons.mainGun.ammo, reload: slotted.weapons.mainGun.reload };

const laserWorld = new World(ARENA, 1);
const laser = laserWorld.spawn(hawk, 0, { x: 15000, y: 15000 }, 0);
for (let i = 0; i < 60; i++) laserWorld.step(new Map([[laser.id, cmd({ aim: { x: 14000, y: 15000 }, fire: true })]]));
const laserBehind = { beams: laserWorld.beams.length, heatL: laser.weapons.laserL.heat, heatR: laser.weapons.laserR.heat };
for (let i = 0; i < 90; i++) laserWorld.step(new Map([[laser.id, cmd({ aim: { x: 15500, y: 15000 }, fire: true })]]));
const laserAhead = { beams: laserWorld.beams.length, heatL: laser.weapons.laserL.heat, modules: laserWorld.beams.map((b) => b.module) };

const duel = new World({ w: 4000, h: 4000 }, 7);
const left = duel.spawn(bulwark, 0, { x: 1000, y: 2000 }, 0);
const right = duel.spawn(hawk, 1, { x: 1600, y: 2000 }, Math.PI / 2);
for (let i = 0; i < 180; i++) {
  duel.step(
    new Map([
      [left.id, cmd({ aim: { x: right.pos.x, y: right.pos.y }, fire: true, turn: Math.sin(i / 40) })],
      [right.id, cmd({ aim: { x: left.pos.x, y: left.pos.y }, fire: i % 200 < 120, throttle: 1, turn: 0.4 })],
    ]),
  );
}
const duelSnap = {
  tick: duel.tick,
  projectiles: duel.projectiles.length,
  missiles: duel.missiles.length,
  left: body(left),
  right: body(right),
  hash: duel.hash(),
};

const missileWorld = new World(ARENA, 3);
const owner = missileWorld.spawn(hawk, 0, { x: 1000, y: 15000 }, 0);
const { launchMissile } = await load("src/sim/combat/missiles.ts");
launchMissile(missileWorld, owner.id, "missile", weapons.WEAPONS.hawk_missile, { x: 1100, y: 15000 }, 0, null, missileWorld.rng.spread);
for (let i = 0; i < 60; i++) missileWorld.step(new Map());
const missileSnap = missileWorld.missiles.map((m) => ({
  pos: m.pos,
  heading: m.heading,
  speed: m.speed,
  age: m.age,
  travelled: m.travelled,
}));

const speedRun = (mul) => {
  const w = new World(ARENA, 1);
  const h = w.spawn(hawk, 0, { x: 15000, y: 15000 }, 0);
  if (mul !== 1) stats.addModifier(h, modifier({ stat: "maxSpeed", op: { kind: "mul", v: mul } }));
  for (let i = 0; i < 360; i++) w.step(new Map([[h.id, cmd({ throttle: 1 })]]));
  return Math.hypot(h.vel.x, h.vel.y);
};

const arc = turret.arcGoal(deg(60), deg(-20), bulwark.modules.find((m) => m.id === "secR").turret);
const arcHold = turret.arcGoal(deg(135), deg(-100), bulwark.modules.find((m) => m.id === "secR").turret);

const golden = num({
  tol: 1e-9,
  pen: penRows,
  eff: effRows,
  hits: hitRows,
  maxPen: maxRows,
  he: heRows,
  apDamage,
  stats: {
    flatMul: statFlatMul,
    set: statSet,
    clamp: statClamp,
    scoped: stats.stat(scoped, "reload", 8, { module: "main" }),
    other: stats.stat(scoped, "reload", 8, { module: "secL" }),
    marked: stats.stat(shooter, "dispersion", 1, {}, marked),
    unmarked: stats.stat(shooter, "dispersion", 1),
    selfMarked: stats.stat(marked, "dispersion", 1),
    refreshLeft: refresh.mods[0].left,
    refreshCount: refresh.mods.length,
    exclusive: stats.stat(exclusive, "damage", 100),
    timedMid,
    timedEnd,
    timedLeft: timed.mods.length,
    plain: stats.stat(holder(), "reload", 7),
  },
  modules: {
    legAfterOne,
    legDisabled,
    legBeforeReboot,
    legAfterReboot,
    legFinal,
    stunAt2,
    stunAt3,
    hostStates,
    coreKill,
    armorFloor: floorV.modules.armR.armor,
    repairPending,
    repaired,
    legRated: { structure: leg.structure, armor: leg.armor },
  },
  arc: { goal: arc.goal, inArc: arc.inArc, hold: arcHold.goal, holdIn: arcHold.inArc },
  oneShot,
  oneLater,
  slotClamp,
  slotAmmo,
  laserBehind,
  laserAhead,
  duel: duelSnap,
  missile: missileSnap,
  speed: { half: speedRun(0.5), full: speedRun(1) },
});

fs.writeFileSync(out, JSON.stringify(golden) + "\n");
console.log("wrote", out, "bytes", fs.statSync(out).size);
