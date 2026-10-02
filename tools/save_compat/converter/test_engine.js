// Regression tests for the save converter. Run through `make save_converter` (WSL, Node 18+):
//   RR_SAVE_PACKAGE=<built save-convert-*.js> node --test tools/save_compat/converter/test_engine.js
// RR_SAVE_FIXTURES=<dir of real .sav files from saves.py make, untagged baseline> adds real-save cases
// and writes each converted save to <dir>/converted/ for the emulator gate (saves.py continue).
"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const PKG_PATH = process.env.RR_SAVE_PACKAGE;
if (!PKG_PATH) throw new Error("set RR_SAVE_PACKAGE to a built save-convert-*.js");
const api = require(path.resolve(PKG_PATH));
const PKG = api.PACKAGE;
const { sum8, writeHeader, recomputeChecksums, wramOffset, offsetOf } = api._internal;
const TARGET = String(PKG.target.schema);
const BASELINE = "baseline_74f82c1b";
const BASELINE_ROM = PKG.sources.find((s) => s.id === BASELINE).rom_sha256[0];

// A minimal valid save in `schemaKey`'s layout: a named player, empty party and box, good checksums.
function syntheticSave(schemaKey, { tag = true } = {}) {
  const schema = PKG.schemas[schemaKey];
  const save = new Uint8Array(api.SRAM_SIZE).fill(0xff);
  // Zero the main block, then fill in what a real save always has.
  const main = schema.checksums.find((c) => c.name === "main");
  save.fill(0, offsetOf(main.bank, main.start), offsetOf(main.bank, main.start) + main.length);
  const name = wramOffset(schema, "wPlayerName");
  save.set([0x91, 0x84, 0x83, 0x50], name); // "RED@"
  save[wramOffset(schema, "wPartyCount")] = 0;
  save[wramOffset(schema, "wPartySpecies")] = 0xff;
  save[wramOffset(schema, "wBoxCount")] = 0;
  save[wramOffset(schema, "wCurrentBoxNum")] = 0;
  recomputeChecksums(save, schema);
  if (tag && /^\d+$/.test(schemaKey)) writeHeader(save, Number(schemaKey));
  return save;
}

test("a tagged save of the target format is a no-op conversion", () => {
  const save = syntheticSave(TARGET);
  const id = api.identify(save, PKG);
  assert.equal(id.ok, true);
  assert.equal(id.tagged, true);
  assert.equal(id.source, TARGET);
  const out = api.convert(save, PKG, { mode: "continue" });
  assert.equal(out.ok, true);
  assert.deepEqual(Array.from(out.bytes), Array.from(save));
});

test("an untagged save needs the old ROM, and only a known ROM identifies it", () => {
  const save = syntheticSave(BASELINE, { tag: false });
  const id = api.identify(save, PKG);
  assert.equal(id.ok, true);
  assert.equal(id.needsRom, true);
  assert.equal(api.convert(save, PKG, {}).code, "needs_rom");
  assert.equal(api.sourceFromRom("00".repeat(32), PKG), null);
  assert.equal(api.sourceFromRom(BASELINE_ROM.toUpperCase(), PKG).id, BASELINE);
});

test("baseline to target: tagged, every other byte identical, input untouched", () => {
  const save = syntheticSave(BASELINE, { tag: false });
  const before = Array.from(save);
  const out = api.convert(save, PKG, { source: BASELINE, mode: "continue" });
  assert.equal(out.ok, true, out.reason);
  assert.deepEqual(Array.from(save), before, "the original must not change");
  const header = api.readHeader(out.bytes);
  assert.deepEqual(header, { present: true, valid: true, schemaId: Number(TARGET) });
  const h = offsetOf(1, "a040");
  for (let i = 0; i < api.SRAM_SIZE; i++) {
    if (i >= h && i < h + 8) continue;
    if (out.bytes[i] !== save[i]) assert.fail(`byte ${i.toString(16)} changed`);
  }
  assert.equal(out.report.checksums.main, true);
  assert.equal(api.identify(out.bytes, PKG).source, TARGET);
});

test("a skipped release still arrives through a chain of migrations", () => {
  // A package with an extra format between the baseline and the target.
  const chained = JSON.parse(JSON.stringify(PKG));
  chained.schemas.mid = chained.schemas[BASELINE];
  chained.migrations = [{ from: BASELINE, to: "mid", steps: ["tag"] }, { from: "mid", to: TARGET, steps: ["tag"] }];
  const out = api.convert(syntheticSave(BASELINE, { tag: false }), chained, { source: BASELINE, mode: "continue" });
  assert.equal(out.ok, true, out.reason);
  assert.equal(out.report.steps.length, 3);
  const looped = JSON.parse(JSON.stringify(chained));
  looped.migrations = [{ from: BASELINE, to: "mid", steps: ["tag"] }, { from: "mid", to: BASELINE, steps: ["tag"] }];
  assert.equal(api.convert(syntheticSave(BASELINE, { tag: false }), looped, { source: BASELINE }).code, "no_migration");
});

test("damaged, foreign or wrapped files are refused with a reason", () => {
  const good = syntheticSave(TARGET);
  const cases = [
    [good.slice(0, 1000), "size"],
    [new Uint8Array(api.SRAM_SIZE + 16), "wrapped"],
    [new Uint8Array(84410), "state"],
  ];
  const badSum = new Uint8Array(good);
  badSum[wramOffset(PKG.schemas[TARGET], "wPlayerName") + 5] ^= 1;
  cases.push([badSum, "checksum"]);
  const badHeader = new Uint8Array(good);
  badHeader[offsetOf(1, "a040") + 6] ^= 0xff;
  cases.push([badHeader, "header"]);
  const future = new Uint8Array(good);
  writeHeader(future, 99);
  cases.push([future, "unknown_schema"]);
  const party = new Uint8Array(good);
  party[wramOffset(PKG.schemas[TARGET], "wPartyCount")] = 7;
  recomputeChecksums(party, PKG.schemas[TARGET], ["main"]);
  cases.push([party, "bounds"]);
  for (const [bytes, code] of cases) {
    const r = api.convert(bytes, PKG, { mode: "continue" });
    assert.equal(r.ok, false);
    assert.equal(r.code, code, `${code}: got ${r.code} (${r.reason})`);
    assert.ok(r.reason.length > 10);
  }
});

test("a baseline save with a bad checksum is refused even with the right ROM", () => {
  const save = syntheticSave(BASELINE, { tag: false });
  save[wramOffset(PKG.schemas[BASELINE], "wPlayerName") + 6] ^= 1;
  assert.equal(api.convert(save, PKG, { source: BASELINE }).code, "checksum");
});

test("a package with an unknown step is refused, not half-applied", () => {
  const broken = JSON.parse(JSON.stringify(PKG));
  broken.migrations = [{ from: BASELINE, to: TARGET, steps: ["teleport"] }];
  assert.equal(api.convert(syntheticSave(BASELINE, { tag: false }), broken, { source: BASELINE }).code, "bad_package");
});

test("recovery copies only the listed permanent fields into the template", () => {
  const schema = PKG.schemas[TARGET];
  const template = syntheticSave(TARGET);
  const source = syntheticSave(TARGET);
  const keyItems = schema.sram.find((f) => f.label === "sKeyItemTiers");
  const tm = schema.sram.find((f) => f.label === "sTMBitfield");
  source.set([1, 2, 3, 4], offsetOf(keyItems.bank, keyItems.address));
  source.set([9, 9, 9, 9, 9, 9, 9], offsetOf(tm.bank, tm.address));
  source.set([0x81, 0x50], wramOffset(schema, "wPlayerName"));
  recomputeChecksums(source, schema, ["main"]);
  const pkg = JSON.parse(JSON.stringify(PKG));
  pkg.recovery = { template: Buffer.from(template).toString("base64"), keep_sram: ["sKeyItemTiers"],
    keep_wram: ["wPlayerName"], keep_event_bytes: [], recompute_checksums: ["main"], always_lost: ["party"] };
  const out = api.convert(source, pkg, { mode: "recovery" });
  assert.equal(out.ok, true, out.reason);
  const o = offsetOf(keyItems.bank, keyItems.address);
  assert.deepEqual(Array.from(out.bytes.slice(o, o + 4)), [1, 2, 3, 4]);
  const t = offsetOf(tm.bank, tm.address);
  assert.deepEqual(Array.from(out.bytes.slice(t, t + 7)), Array.from(template.slice(t, t + 7)), "TMs are run state");
  assert.equal(out.bytes[wramOffset(schema, "wPlayerName")], 0x81);
  assert.deepEqual(out.report.kept, ["sKeyItemTiers", "wPlayerName"]);
  assert.ok(out.report.lost.includes("party"));
  assert.equal(api.checksumStatus(out.bytes, schema).main, true);
  assert.equal(api.convert(source, PKG, { mode: "recovery" }).code, PKG.recovery ? undefined : "no_recovery");
});

const FIXTURES = process.env.RR_SAVE_FIXTURES;
test("real baseline saves convert", { skip: !FIXTURES && "RR_SAVE_FIXTURES not set" }, () => {
  const outDir = path.join(FIXTURES, "converted");
  fs.mkdirSync(outDir, { recursive: true });
  const files = fs.readdirSync(FIXTURES).filter((f) => f.endsWith(".sav"));
  assert.ok(files.length > 0);
  for (const file of files) {
    const save = new Uint8Array(fs.readFileSync(path.join(FIXTURES, file)));
    const id = api.identify(save, PKG);
    assert.equal(id.needsRom, true, file);
    const out = api.convert(save, PKG, { source: BASELINE, mode: "continue" });
    assert.equal(out.ok, true, `${file}: ${out.reason}`);
    fs.writeFileSync(path.join(outDir, file), out.bytes);
    const meta = path.join(FIXTURES, file.replace(/\.sav$/, ".json"));
    if (fs.existsSync(meta)) fs.copyFileSync(meta, path.join(outDir, path.basename(meta)));
  }
});
