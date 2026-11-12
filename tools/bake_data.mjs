// Bake Game_test@33f4be8 data tables into res://data JSON.
//
// The prototype is NOT vendored in this repo. Pass a text snapshot of
// Mrzandb/Game_test commit 33f4be8b19df7fe4137550e1da8ee38bf41aa94e
// (the zip extracted somewhere outside the repo). This script imports that
// tree under Node's type-stripping loader, evaluates shape constructors
// (src/data/shapes.ts) and the leg rest pose (src/sim/vehicle/legs.ts),
// and writes the resulting numbers. Do not recompute those polygons in
// GDScript — Math.sin / Math.cos will not match.
//
//   node tools/bake_data.mjs --snapshot /path/to/Game_test
//
// Node >= 22.18. The script re-invokes itself with --experimental-strip-types.
// camera.ts is read as text only (parameter properties are not strip-safe,
// and the camera is not part of this port). lookRange is checked against
// `2400 * RANGE_SCALE` and stored as a number.

import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const PROTOTYPE_COMMIT = "33f4be8b19df7fe4137550e1da8ee38bf41aa94e";
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
  let out = path.resolve(HERE, "..");
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--snapshot") {
      snapshot = argv[++i] ?? "";
    } else if (arg === "--out") {
      out = path.resolve(argv[++i] ?? "");
    } else if (arg === "--help" || arg === "-h") {
      console.log("usage: node tools/bake_data.mjs --snapshot <Game_test@33f4be8> [--out repo]");
      process.exit(0);
    } else {
      throw new Error("unknown argument " + arg);
    }
  }
  if (!snapshot) {
    throw new Error("missing --snapshot <dir containing src/data>");
  }
  return { snapshot: path.resolve(snapshot), out };
}

function mustText(snapshot, rel) {
  const file = path.join(snapshot, rel);
  if (!fs.existsSync(file)) {
    throw new Error("snapshot is missing " + rel + " (" + file + ")");
  }
  return fs.readFileSync(file, "utf8");
}

function mustInclude(snapshot, rel, needle) {
  const text = mustText(snapshot, rel);
  if (!text.includes(needle)) {
    throw new Error(rel + " does not contain fingerprint [" + needle + "] — expected Game_test@" + PROTOTYPE_COMMIT);
  }
  return text;
}

function canonicalize(value, where) {
  if (value === undefined) {
    return undefined;
  }
  if (typeof value === "number") {
    if (Number.isNaN(value)) {
      throw new Error("NaN at " + where);
    }
    if (value === Infinity) {
      return { $: "inf" };
    }
    if (value === -Infinity) {
      return { $: "-inf" };
    }
    return value;
  }
  if (typeof value === "string" || typeof value === "boolean" || value === null) {
    return value;
  }
  if (Array.isArray(value)) {
    return value.map((item, i) => {
      const next = canonicalize(item, where + "[" + i + "]");
      if (next === undefined) {
        throw new Error("undefined in array at " + where);
      }
      return next;
    });
  }
  if (typeof value === "object") {
    const out = {};
    for (const key of Object.keys(value).sort()) {
      const next = canonicalize(value[key], where + "." + key);
      if (next !== undefined) {
        out[key] = next;
      }
    }
    return out;
  }
  throw new Error("unsupported value at " + where + ": " + typeof value);
}

function flatten(value, leafPath, out) {
  if (value && typeof value === "object" && !Array.isArray(value)) {
    const keys = Object.keys(value);
    if (keys.length === 1 && keys[0] === "$" && (value.$ === "inf" || value.$ === "-inf")) {
      out[leafPath] = value.$;
      return;
    }
  }
  if (Array.isArray(value)) {
    value.forEach((item, i) => flatten(item, leafPath + "[" + i + "]", out));
    return;
  }
  if (value && typeof value === "object") {
    for (const key of Object.keys(value).sort()) {
      if (key === "parts") {
        const parts = value.parts;
        out[leafPath + ".partCount"] = parts.length;
        let verts = 0;
        for (const ring of parts) {
          verts += ring.length;
        }
        out[leafPath + ".vertexCount"] = verts;
        continue;
      }
      const next = leafPath === "" ? key : leafPath + "." + key;
      flatten(value[key], next, out);
    }
    return;
  }
  out[leafPath] = value;
}

function writeJson(outRoot, rel, value) {
  const file = path.join(outRoot, rel);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const text = JSON.stringify(value, null, 2) + "\n";
  fs.writeFileSync(file, text);
  return text;
}

function withCost(vehicle) {
  const copy = structuredClone(vehicle);
  if (Object.prototype.hasOwnProperty.call(copy, "cost")) {
    throw new Error(copy.id + " already has cost in the prototype; refusing to overwrite");
  }
  copy.cost = 0;
  return copy;
}

const { snapshot, out } = parseArgs(process.argv.slice(2));
const snapReal = fs.realpathSync(snapshot);
const outReal = fs.realpathSync(out);
if (snapReal === outReal || snapReal.startsWith(outReal + path.sep) || outReal.startsWith(snapReal + path.sep)) {
  throw new Error("snapshot and --out must be separate directories; do not commit the prototype");
}

mustInclude(snapshot, "src/data/weapons.ts", "export const RANGE_SCALE = 3;");
mustInclude(snapshot, "src/data/weapons.ts", "id: 'torpedo_ap'");
mustInclude(snapshot, "src/data/weapons.ts", "id: 'emp_missile'");
mustInclude(snapshot, "src/data/weapons.ts", "reload: 34");
mustInclude(snapshot, "src/data/weapons.ts", "shellSpeed: 1500");
mustInclude(snapshot, "src/data/rules.ts", "wallHp: 1800");
mustInclude(snapshot, "src/data/rules.ts", "heMinFactor: 0.15");
mustInclude(snapshot, "src/data/rules.ts", "quotaPerType: 2");
mustInclude(snapshot, "src/data/maps/hills.ts", "export const MIN_PASSAGE = 520;");
mustInclude(snapshot, "src/data/maps/hills.ts", "w: 10000, h: 10000");
mustInclude(snapshot, "src/data/vehicles/bulwark.ts", "armor: 350, structure: 560, stunMax: 120");
mustInclude(snapshot, "src/data/structures.ts", "export const BASE_SIZE = 480;");
mustInclude(snapshot, "src/sim/vehicle/legs.ts", "export function legParts");
mustText(snapshot, "src/data/shapes.ts");

const camera = mustText(snapshot, "src/render/camera.ts");
const lookFormula = "lookRange: 2400 * RANGE_SCALE";
if (!camera.includes(lookFormula)) {
  throw new Error("camera.ts is missing [" + lookFormula + "]; expected Game_test@" + PROTOTYPE_COMMIT);
}

async function load(rel) {
  return import(pathToFileURL(path.join(snapshot, rel)).href);
}

const weaponsMod = await load("src/data/weapons.ts");
const rulesMod = await load("src/data/rules.ts");
const bulwarkMod = await load("src/data/vehicles/bulwark.ts");
const hawkMod = await load("src/data/vehicles/hawk.ts");
const swarmMod = await load("src/data/vehicles/swarm.ts");
const hillsMod = await load("src/data/maps/hills.ts");
const mapIndex = await load("src/data/maps/index.ts");
const structuresMod = await load("src/data/structures.ts");

if (weaponsMod.RANGE_SCALE !== 3) {
  throw new Error("RANGE_SCALE evaluated to " + weaponsMod.RANGE_SCALE);
}
const lookRange = 2400 * weaponsMod.RANGE_SCALE;
if (lookRange !== 7200) {
  throw new Error("lookRange " + lookRange);
}
if (mapIndex.MAPS.hills !== hillsMod.hills) {
  throw new Error("maps/index.ts does not export the hills object");
}

const lineup = [bulwarkMod.bulwark, swarmMod.swarm, hawkMod.hawk];
const concepts = [hawkMod.hawkB, hawkMod.hawkC];
const bases = [structuresMod.baseDef(0), structuresMod.baseDef(1)];
for (const def of [...lineup, ...concepts, ...bases]) {
  if (!def || typeof def.id !== "string") {
    throw new Error("vehicle def missing id");
  }
}

const index = canonicalize({
  prototype: {
    repo: "Mrzandb/Game_test",
    commit: PROTOTYPE_COMMIT,
  },
  sight: { lookRange },
  lineup: lineup.map((def) => def.id),
  concepts: concepts.map((def) => def.id),
  structures: bases.map((def) => def.id),
  maps: Object.keys(mapIndex.MAPS),
}, "index");

const rules = canonicalize(rulesMod.RULES, "rules");
const weapons = canonicalize({
  rangeScale: weaponsMod.RANGE_SCALE,
  defaultSigmaRatio: weaponsMod.DEFAULT_SIGMA_RATIO,
  bulwarkAp: weaponsMod.BULWARK_AP,
  swarmAp: weaponsMod.SWARM_AP,
  weapons: weaponsMod.WEAPONS,
}, "weapons");
const structures = canonicalize({
  baseSize: structuresMod.BASE_SIZE,
  baseStats: structuresMod.BASE_STATS,
}, "structures");

function vehicleDoc(def, extra) {
  const body = { vehicle: withCost(def) };
  if (extra) {
    Object.assign(body, extra);
  }
  return canonicalize(body, def.id);
}

const vehicleDocs = {
  [bulwarkMod.bulwark.id]: vehicleDoc(bulwarkMod.bulwark, {
    legSpec: bulwarkMod.BULWARK_LEG,
    legRest: bulwarkMod.BULWARK_LEG_REST,
  }),
  [hawkMod.hawk.id]: vehicleDoc(hawkMod.hawk),
  [hawkMod.hawkB.id]: vehicleDoc(hawkMod.hawkB),
  [hawkMod.hawkC.id]: vehicleDoc(hawkMod.hawkC),
  [swarmMod.swarm.id]: vehicleDoc(swarmMod.swarm),
  [bases[0].id]: vehicleDoc(bases[0]),
  [bases[1].id]: vehicleDoc(bases[1]),
};

const hills = canonicalize({
  minPassage: hillsMod.MIN_PASSAGE,
  map: hillsMod.hills,
}, "hills");

const written = [];
function emit(rel, value) {
  const text = writeJson(out, rel, value);
  written.push(rel);
  return text;
}

emit("data/index.json", index);
emit("data/rules.json", rules);
emit("data/weapons.json", weapons);
emit("data/structures.json", structures);
for (const id of Object.keys(vehicleDocs).sort()) {
  emit("data/vehicles/" + id + ".json", vehicleDocs[id]);
}
emit("data/maps/hills.json", hills);

const leaves = {};
flatten(index, "index", leaves);
flatten(rules, "rules", leaves);
flatten(weapons, "weapons", leaves);
flatten(structures, "structures", leaves);
for (const id of Object.keys(vehicleDocs).sort()) {
  flatten(vehicleDocs[id], "vehicles." + id, leaves);
}
flatten(hills, "maps.hills", leaves);
emit("tests/golden/scalars.json", leaves);

const hashes = {};
for (const rel of written) {
  const bytes = fs.readFileSync(path.join(out, rel));
  hashes[rel] = createHash("sha256").update(bytes).digest("hex");
}
const hashDoc = {};
for (const rel of Object.keys(hashes).sort()) {
  hashDoc[rel] = hashes[rel];
}
const hashText = writeJson(out, "tests/golden/sha256.json", hashDoc);
const lock = createHash("sha256").update(hashText).digest("hex");

const partCount = lineup.concat(concepts, bases).reduce((sum, def) => {
  return sum + def.modules.reduce((inner, mod) => inner + mod.parts.length, 0);
}, 0);
console.log("baked commit %s", PROTOTYPE_COMMIT);
console.log("vehicles %d weapons %d maps %d parts %d scalar_leaves %d", Object.keys(vehicleDocs).length, Object.keys(weaponsMod.WEAPONS).length, index.maps.length, partCount, Object.keys(leaves).length);
console.log("SHA256 tests/golden/sha256.json %s", lock);
console.log("ranges %s", JSON.stringify(Object.fromEntries(Object.entries(weaponsMod.WEAPONS).map(([id, weapon]) => [id, weapon.range]))));
