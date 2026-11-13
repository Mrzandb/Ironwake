// Golden numbers for the world, match, and AI port.
//
// Node's type stripper rejects constructor parameter properties. This script
// rewrites those in the snapshot before import (world, match, nav, replay).
// Absolute tolerance in GDScript is 1e-9. Values are rounded to 1e-12.
//
//   node tools/golden_world.mjs --snapshot /path/to/Game_test

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
    ["--experimental-strip-types", "--import", path.join(HERE, "register_ts.mjs"), fileURLToPath(import.meta.url), ...process.argv.slice(2)],
    { stdio: "inherit" },
  );
  process.exit(child.status === null ? 1 : child.status);
}

relaunch();

function parseArgs(argv) {
  let snapshot = "";
  let out = path.join(HERE, "..", "tests", "world_golden.json");
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

function replaceOnce(rel, old, next) {
  const file = path.join(snapshot, rel);
  const src = fs.readFileSync(file, "utf8");
  if (!src.includes(old)) {
    if (!src.includes(next.slice(0, 40))) throw new Error(rel + " did not match and is not already patched");
    return;
  }
  fs.writeFileSync(file, src.replace(old, next));
}

replaceOnce(
  "src/sim/world.ts",
  `  constructor(
    readonly arena: { w: number; h: number },
    readonly seed = 1,
    readonly map: MapDef | null = null,
  ) {
    this.rng = makeStreams(seed);
    this.terrain = new Terrain(map);
  }`,
  `  arena: { w: number; h: number };
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
  }`,
);

replaceOnce(
  "src/sim/match/match.ts",
  `  constructor(
    readonly world: World,
    readonly map: MapDef,
    readonly defs: Readonly<Record<string, VehicleDef>>,
    roster: readonly RosterEntry[],
    duration: number = RULES.match.duration,
  ) {
    this.timeLeft = duration;`,
  `  world: World;
  map: MapDef;
  defs: Readonly<Record<string, VehicleDef>>;
  constructor(
    world: World,
    map: MapDef,
    defs: Readonly<Record<string, VehicleDef>>,
    roster: readonly RosterEntry[],
    duration: number = RULES.match.duration,
  ) {
    this.world = world;
    this.map = map;
    this.defs = defs;
    this.timeLeft = duration;`,
);

replaceOnce(
  "src/sim/ai/nav.ts",
  `  constructor(
    private readonly world: World,
    readonly clearance = 170,
  ) {
    this.cols = Math.ceil(world.arena.w / NAV_CELL);`,
  `  private world: World;
  readonly clearance: number;
  constructor(
    world: World,
    clearance = 170,
  ) {
    this.world = world;
    this.clearance = clearance;
    this.cols = Math.ceil(world.arena.w / NAV_CELL);`,
);

replaceOnce(
  "src/sim/replay.ts",
  `  constructor(readonly replay: Replay) {
    this.world = replayWorld(replay);
  }`,
  `  replay: Replay;
  constructor(replay: Replay) {
    this.replay = replay;
    this.world = replayWorld(replay);
  }`,
);

const load = (rel) => import(pathToFileURL(path.join(snapshot, rel)).href);
const worldMod = await load("src/sim/world.ts");
const simpleMod = await load("src/sim/ai/simple.ts");
const teamMod = await load("src/sim/ai/team.ts");
const navMod = await load("src/sim/ai/nav.ts");
const matchMod = await load("src/sim/match/match.ts");
const commandMod = await load("src/sim/command.ts");
const weaponsMod = await load("src/data/weapons.ts");
const hillsMod = await load("src/data/maps/hills.ts");
const bulwarkMod = await load("src/data/vehicles/bulwark.ts");
const hawkMod = await load("src/data/vehicles/hawk.ts");
const swarmMod = await load("src/data/vehicles/swarm.ts");

const { World } = worldMod;
const { thinkSimple, DEFAULT_AI } = simpleMod;
const { thinkTeam } = teamMod;
const { NavGrid } = navMod;
const { Match, defaultRoster } = matchMod;
const { IDLE } = commandMod;
const { WEAPONS } = weaponsMod;
const hills = hillsMod.hills;
const bulwark = bulwarkMod.bulwark;
const hawk = hawkMod.hawk;
const swarm = swarmMod.swarm;
const DEFS = { bulwark, hawk, swarm };
const round = (value) => (typeof value === "number" && Number.isFinite(value) ? Math.round(value * 1e12) / 1e12 : value);
const body = (vehicle) => ({
  x: round(vehicle.pos.x),
  y: round(vehicle.pos.y),
  vx: round(vehicle.vel.x),
  vy: round(vehicle.vel.y),
  heading: round(vehicle.heading),
  angVel: round(vehicle.angVel),
  speed: round(vehicle.speed),
  crown: round(vehicle.crownAngle),
  alive: vehicle.alive,
  modules: vehicle.def.modules.map((module) => ({
    id: module.id,
    armor: round(vehicle.modules[module.id].armor),
    structure: round(vehicle.modules[module.id].structure),
  })),
});
const cmdFields = (cmd) => ({
  throttle: round(cmd.throttle),
  turn: round(cmd.turn),
  strafe: round(cmd.strafe),
  fire: cmd.fire,
  slot: cmd.slot,
  lock: cmd.lock,
  aimX: round(cmd.aim.x),
  aimY: round(cmd.aim.y),
});

const orbitWorld = new World({ w: 8000, h: 8000 }, 1);
const anchor = orbitWorld.spawn(bulwark, 0, { x: 4000, y: 4000 }, 0);
const flyer = orbitWorld.spawn(hawk, 1, { x: 4000, y: 4000 - 800 }, Math.PI / 2);
const orbitAi = { ...DEFAULT_AI, orbitRadius: 600, fire: false };
let samples = 0;
let distSum = 0;
for (let i = 0; i < 30 * 60; i++) {
  orbitWorld.step(
    new Map([
      [anchor.id, { ...IDLE, aim: { x: flyer.pos.x, y: flyer.pos.y }, secondaries: false }],
      [flyer.id, thinkSimple(flyer, anchor, orbitAi)],
    ]),
  );
  if (i > 10 * 60) {
    samples++;
    distSum += Math.hypot(flyer.pos.x - anchor.pos.x, flyer.pos.y - anchor.pos.y);
  }
}

const noseWorld = new World({ w: 8000, h: 8000 }, 1);
const noseTarget = noseWorld.spawn(bulwark, 0, { x: 4000, y: 4000 }, 0);
const noseHawk = noseWorld.spawn(hawk, 1, { x: 4000, y: 3400 }, Math.PI / 2);
const noseCold = thinkSimple(noseHawk, noseTarget, DEFAULT_AI);
const missile = noseHawk.def.modules.find((module) => module.weapon && WEAPONS[module.weapon].kind === "missile");
noseHawk.weapons[missile.id].reload = 0;
const noseHot = thinkSimple(noseHawk, noseTarget, DEFAULT_AI);

const duel = new World({ w: 20000, h: 20000 }, 11);
const left = duel.spawn(bulwark, 0, { x: 8000, y: 10000 }, 0);
const right = duel.spawn(bulwark, 1, { x: 10000, y: 10000 }, Math.PI);
const duelAi = { ...DEFAULT_AI, keepDistance: 1500 };
let duelShots = 0;
for (let i = 0; i < 180; i++) {
  duel.step(new Map([[left.id, thinkSimple(left, right, duelAi)], [right.id, thinkSimple(right, left, duelAi)]]));
  duelShots += duel.events.filter((event) => event.t === "fire").length;
}

const hillsWorld = new World(hills.size, 1, hills);
const nav = new NavGrid(hillsWorld);
const paths = hills.spawns.map((spawn) => {
  const base = hills.bases.find((site) => site.team !== spawn.team);
  const path = nav.findPath(spawn.pos, base.pos);
  return {
    team: spawn.team,
    x: round(spawn.pos.x),
    y: round(spawn.pos.y),
    points: (path ?? []).map((point) => [round(point.x), round(point.y)]),
  };
});

const teamWorld = new World(hills.size, 1, hills);
const roster = defaultRoster(0, "bulwark", ["bulwark", "swarm", "hawk"]);
const match = new Match(teamWorld, hills, DEFS, roster, 600);
const teamNav = new NavGrid(teamWorld);
let teamShots = 0;
for (let i = 0; i < 180; i++) {
  const cmds = new Map();
  for (const player of match.players) {
    const vehicle = match.vehicleOf(player);
    if (vehicle?.alive) cmds.set(vehicle.id, thinkTeam(teamWorld, teamNav, vehicle));
  }
  teamWorld.step(cmds);
  match.step();
  teamShots += teamWorld.events.filter((event) => event.t === "fire").length;
}

const golden = {
  tolerance: 1e-9,
  source: "Game_test@33f4be8 thinkSimple, NavGrid, thinkTeam, Match. Rounded to 1e-12.",
  orbit: {
    average: round(distSum / samples),
    samples,
    end: {
      x: round(flyer.pos.x),
      y: round(flyer.pos.y),
      vx: round(flyer.vel.x),
      vy: round(flyer.vel.y),
      heading: round(flyer.heading),
      angVel: round(flyer.angVel),
      speed: round(flyer.speed),
    },
  },
  noseCold: cmdFields(noseCold),
  noseHot: cmdFields(noseHot),
  duel180: { shots: duelShots, left: body(left), right: body(right), projectiles: duel.projectiles.length },
  paths,
  team180: {
    shots: teamShots,
    timeLeft: round(match.timeLeft),
    vehicles: teamWorld.vehicles
      .filter((vehicle) => vehicle.def.locomotion !== "static")
      .map((vehicle) => ({ id: vehicle.id, def: vehicle.def.id, ...body(vehicle) })),
  },
};

fs.writeFileSync(out, JSON.stringify(golden) + "\n");
console.log("wrote %s", out);
console.log("orbit average %s samples %s", golden.orbit.average, golden.orbit.samples);
console.log("nose cold slot %s turn %s fire %s", golden.noseCold.slot, golden.noseCold.turn, golden.noseCold.fire);
console.log("nose hot slot %s turn %s fire %s", golden.noseHot.slot, golden.noseHot.turn, golden.noseHot.fire);
console.log("duel shots %s projectiles %s", golden.duel180.shots, golden.duel180.projectiles);
console.log("paths %s", golden.paths.map((path) => path.points.length).join(","));
console.log("team shots %s timeLeft %s", golden.team180.shots, golden.team180.timeLeft);
