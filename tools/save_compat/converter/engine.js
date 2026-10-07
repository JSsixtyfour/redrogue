/*
 * Red Rogue save converter engine. No dependencies; runs in a browser (window.RRSaveConvert)
 * and in Node (module.exports) so the patch page and the regression tests run the same code.
 *
 * A "package" (built by tools/save_compat/build_package.py) carries everything for one target
 * build: its schema, the schemas of every source it accepts, how to recognise those sources,
 * the migrations between them, and (when recovery is offered) a verified post-reset template.
 *
 *   identify(save, pkg)                       -> what the save is, or why it can't be read
 *   sourceFromRom(romSha256, pkg)             -> the untagged source a player's old ROM identifies
 *   convert(save, pkg, {source, mode})        -> {ok, bytes, report} or {ok: false, reason}
 *
 * Saves are raw 32 KiB MBC3 SRAM (.sav / .srm). Every function takes and returns Uint8Arrays and
 * never modifies its input.
 */
(function (root) {
  "use strict";

  var SRAM_SIZE = 0x8000;
  var BANK_SIZE = 0x2000;
  var MAGIC = [0x52, 0x52, 0x53, 0x47]; // "RRSG"

  function fail(code, message) {
    return { ok: false, code: code, reason: message };
  }

  function offsetOf(bank, address) {
    return bank * BANK_SIZE + (parseInt(address, 16) - 0xa000);
  }

  function sum8(bytes, start, length) {
    var d = 0;
    for (var i = 0; i < length; i++) d = (d + bytes[start + i]) & 0xff;
    return (~d) & 0xff;
  }

  function sramField(schema, label) {
    for (var i = 0; i < schema.sram.length; i++) if (schema.sram[i].label === label) return schema.sram[i];
    return null;
  }

  function wramField(schema, label) {
    for (var i = 0; i < schema.saved_wram.length; i++) if (schema.saved_wram[i].label === label) return schema.saved_wram[i];
    return null;
  }

  // Byte offset in the .sav of a saved-WRAM field (it lives inside one of the main save blocks).
  function wramOffset(schema, label) {
    var f = wramField(schema, label);
    if (!f) return -1;
    var block = sramField(schema, f.block);
    return offsetOf(block.bank, block.address) + f.offset;
  }

  function readHeader(save) {
    var o = offsetOf(1, "a040");
    var bytes = Array.prototype.slice.call(save, o, o + 8);
    var magic = bytes[0] === MAGIC[0] && bytes[1] === MAGIC[1] && bytes[2] === MAGIC[2] && bytes[3] === MAGIC[3];
    if (!magic) return { present: false };
    var id = bytes[4] | (bytes[5] << 8);
    var inverse = bytes[6] | (bytes[7] << 8);
    return { present: true, valid: ((~id) & 0xffff) === inverse, schemaId: id };
  }

  function writeHeader(save, schemaId) {
    var o = offsetOf(1, "a040");
    var inverse = (~schemaId) & 0xffff;
    var bytes = MAGIC.concat([schemaId & 0xff, schemaId >> 8, inverse & 0xff, inverse >> 8]);
    for (var i = 0; i < 8; i++) save[o + i] = bytes[i];
  }

  function checksumStatus(save, schema) {
    var out = {};
    schema.checksums.forEach(function (c) {
      var start = offsetOf(c.bank, c.start);
      var at = offsetOf(c.at_bank, c.at);
      out[c.name] = sum8(save, start, c.length) === save[at];
    });
    return out;
  }

  function recomputeChecksums(save, schema, names) {
    schema.checksums.forEach(function (c) {
      if (names && names.indexOf(c.name) < 0) return;
      save[offsetOf(c.at_bank, c.at)] = sum8(save, offsetOf(c.bank, c.start), c.length);
    });
  }

  // Structural checks a real save from this schema always passes. A failure means corrupt data,
  // or a save from some other layout that happens to share a checksum.
  function boundsProblems(save, schema) {
    var problems = [];
    function byte(label) {
      var o = wramOffset(schema, label);
      return o < 0 ? null : save[o];
    }
    var name = wramOffset(schema, "wPlayerName");
    var terminated = false;
    for (var i = 0; i < 11; i++) if (save[name + i] === 0x50) terminated = true;
    if (!terminated || save[name] === 0x50) problems.push("the player name is missing or unterminated");
    var party = byte("wPartyCount");
    if (party === null || party > 6) problems.push("party count " + party + " is more than 6");
    else {
      var species = wramOffset(schema, "wPartySpecies");
      if (save[species + party] !== 0xff) problems.push("the party list isn't terminated after " + party + " Pokemon");
    }
    var box = byte("wBoxCount");
    if (box === null || box > 20) problems.push("current box count " + box + " is more than 20");
    var boxNum = byte("wCurrentBoxNum");
    if (boxNum !== null && (boxNum & 0x7f) >= 12) problems.push("current box number " + (boxNum & 0x7f) + " is past box 12");
    return problems;
  }

  // What a save is, according to this package. Never trusts a header alone: the main checksum
  // and the structure must agree with the schema it names.
  function identify(save, pkg) {
    if (!(save instanceof Uint8Array)) return fail("type", "expected the save's bytes");
    if (save.length !== SRAM_SIZE) {
      if (save.length > SRAM_SIZE && save.length <= SRAM_SIZE + 64)
        return fail("wrapped", "This file is " + save.length + " bytes: an emulator added extra data after the save. " +
          "Export a raw 32 KB .sav (in mGBA: File > Export save; most emulators have a 'raw' or '.sav' option).");
      if (save.length > 0x10000)
        return fail("state", "This looks like an emulator save state, not a battery save. Use the game's own save " +
          "file (.sav or .srm), not a state (.ss1, .sn1, .state, ...).");
      return fail("size", "A Red Rogue save is exactly 32768 bytes; this file is " + save.length + ".");
    }
    var header = readHeader(save);
    if (header.present) {
      if (!header.valid) return fail("header", "The save's header is damaged, so its layout can't be trusted.");
      var schema = pkg.schemas[String(header.schemaId)];
      if (!schema) return fail("unknown_schema", "This save uses save format " + header.schemaId +
        ", which this build's converter doesn't know. Pick a newer build on this page, or ask the developers.");
      return checkAgainst(save, schema, { tagged: true, source: String(header.schemaId) });
    }
    return { ok: true, tagged: false, needsRom: true,
      reason: "This save has no format tag, so it comes from an older build. Pick the patched ROM you played it with " +
        "so the converter can tell which build that was." };
  }

  function checkAgainst(save, schema, result) {
    var sums = checksumStatus(save, schema);
    if (!sums.main) return fail("checksum", "The save's main checksum doesn't match: the file is damaged, or it isn't " +
      "from the build you picked.");
    var problems = boundsProblems(save, schema);
    if (problems.length) return fail("bounds", "The save doesn't look like a Red Rogue save from that build: " + problems.join("; ") + ".");
    result.ok = true;
    result.checksums = sums;
    return result;
  }

  function sourceFromRom(romSha256, pkg) {
    var hash = String(romSha256).toLowerCase();
    for (var i = 0; i < pkg.sources.length; i++) {
      var s = pkg.sources[i];
      if (s.rom_sha256.indexOf(hash) >= 0) return s;
    }
    return null;
  }

  function findMigration(pkg, from) {
    for (var i = 0; i < pkg.migrations.length; i++) if (pkg.migrations[i].from === from) return pkg.migrations[i];
    return null;
  }

  // Migration steps, by name. Each takes (bytes, fromSchema, toSchema) and edits the copy in place,
  // or returns a refusal string. They are explicit on purpose: a matching label name never proves
  // two fields mean the same thing.
  var STEPS = {
    // Same layout and meaning (tools/save_schema.py diff --ignore-header said identical): only the
    // header is new, and it sits in padding no checksum covers.
    tag: function () { return null; },

    // Schema 1 -> 2 (2026-10-03): the three item count arrays grew to their slot sizes
    // (wRecoveryItemCounts 21 -> 24, wStatItemCounts 15 -> 24, wValuableItemCounts 4 -> 8).
    // Every byte from the field after them (wNumBagItems) to the end of the bank-1 save
    // sections (rest of the main block, sprite/party/box data, the main checksum, the Final
    // Team Archive and the Procedural Facility state) moved up by the total growth unchanged,
    // so it is shifted as one run; the archive's own checksums travel with their data.
    // Each count array keeps its old entries at the same indices, and the new spare slots are
    // 0, as a new game leaves them. Old saves counted PP UP / M.GENE / M.TOME in the
    // Pearl / Big Pearl / Nugget bytes (the array was one table too short); those bytes can't
    // be split, so they stay Valuable counts.
    itemCountSlots: function (bytes, from, to) {
      var src = new Uint8Array(bytes);
      var arrays = ["wRecoveryItemCounts", "wStatItemCounts", "wValuableItemCounts"];
      var growth = 0;
      for (var i = 0; i < arrays.length; i++) {
        var a = wramField(from, arrays[i]), b = wramField(to, arrays[i]);
        if (!a || !b || b.size < a.size) return "item count layout not recognised (" + arrays[i] + ")";
        growth += b.size - a.size;
      }
      var mainFrom = sramField(from, "sMainData"), mainTo = sramField(to, "sMainData");
      if (mainTo.size - mainFrom.size !== growth) return "main save block grew by an unexpected amount";
      var start = wramOffset(from, "wNumBagItems");
      if (wramOffset(to, "wNumBagItems") - start !== growth) return "wNumBagItems did not move by the item count growth";
      // The shifted run ends at the last bank-1 label at or after it; each of those labels must
      // have moved by exactly the growth, and nothing in the old save may sit where the run lands.
      var end = start;
      for (var j = 0; j < from.sram.length; j++) {
        var f = from.sram[j];
        var o = offsetOf(f.bank, f.address);
        if (f.bank !== 1 || o < start) continue;
        var t = sramField(to, f.label);
        if (!t || offsetOf(t.bank, t.address) - o !== growth || t.size !== f.size)
          return "save field " + f.label + " did not move by the item count growth";
        end = Math.max(end, o + f.size);
      }
      for (var k = 0; k < from.sram.length; k++) {
        var g = from.sram[k], go = offsetOf(g.bank, g.address);
        if (go >= end && go < end + growth) return "the shifted save data would overwrite " + g.label;
      }
      for (var n = end - 1; n >= start; n--) bytes[n + growth] = src[n];
      for (var m = 0; m < arrays.length; m++) {
        var oldF = wramField(from, arrays[m]), newF = wramField(to, arrays[m]);
        var so = wramOffset(from, arrays[m]), d = wramOffset(to, arrays[m]);
        for (var p = 0; p < newF.size; p++) bytes[d + p] = p < oldF.size ? src[so + p] : 0;
      }
      recomputeChecksums(bytes, to, ["main"]);
      return null;
    },

    // Schema 2 -> 3 (2026-10-03): the two vanilla list inventories were deleted from the main
    // block: the legacy bag (wNumBagItems .. before wBagPocketsFlags, 8 bytes) and the PC item
    // box (wNumBoxItems .. before wCurrentBoxNum, 102 bytes). Neither held anything Red Rogue
    // uses: items in no pocket have no use, and nothing deposited into the PC box. Every byte
    // after each hole, to the end of the bank-1 save sections, moves down by the bytes removed
    // before it, unchanged; the archive's own checksums travel with their data.
    legacyInventoriesRemoved: function (bytes, from, to) {
      var src = new Uint8Array(bytes);
      var holes = [["wNumBagItems", "wBagPocketsFlags", 8], ["wNumBoxItems", "wCurrentBoxNum", 102]];
      var spans = [], removed = 0;
      for (var i = 0; i < holes.length; i++) {
        var s = wramOffset(from, holes[i][0]), e = wramOffset(from, holes[i][1]);
        if (s < 0 || e < 0 || e - s !== holes[i][2]) return "save field " + holes[i][0] + " not recognised";
        removed += e - s;
        if (wramOffset(to, holes[i][1]) !== e - removed) return "save field " + holes[i][1] + " did not move as expected";
        spans.push([s, e]);
      }
      var mainFrom = sramField(from, "sMainData"), mainTo = sramField(to, "sMainData");
      if (mainFrom.size - mainTo.size !== removed) return "main save block shrank by an unexpected amount";
      function removedBefore(o) {
        var n = 0;
        for (var k = 0; k < spans.length; k++) if (spans[k][1] <= o) n += spans[k][1] - spans[k][0];
        return n;
      }
      var start = spans[0][0], end = start;
      for (var j = 0; j < from.sram.length; j++) {
        var f = from.sram[j], o = offsetOf(f.bank, f.address);
        if (f.bank !== 1 || o < start) continue;
        var t = sramField(to, f.label);
        if (!t || o - offsetOf(t.bank, t.address) !== removedBefore(o) || t.size !== f.size)
          return "save field " + f.label + " did not move as expected";
        end = Math.max(end, o + f.size);
      }
      var dst = start;
      for (var n = start; n < end; n++) {
        var inHole = false;
        for (var h = 0; h < spans.length; h++) if (n >= spans[h][0] && n < spans[h][1]) inHole = true;
        if (!inHole) bytes[dst++] = src[n];
      }
      for (; dst < end; dst++) bytes[dst] = 0; // past the new end of the bank-1 data: unused
      recomputeChecksums(bytes, to, ["main"]);
      return null;
    },

    // Schema 3 -> 4 (2026-10-06): a new SRAM bank 2 section, "Reward Offer DVs SRAM"
    // (sRogueOfferDVs 6 bytes + sRogueOfferDVTag 3 bytes), right after the fallen log. Nothing
    // moved and no checksum covers it. Zeroed, as a new game leaves it (RogueOfferDVsClear): a
    // zero tag matches no offer, so each offer rolls its DVs the first time it is looked at.
    rogueOfferDVsAdded: function (bytes, from, to) {
      for (var i = 0; i < from.sram.length; i++) {
        var f = from.sram[i], t = sramField(to, f.label);
        if (!t || t.bank !== f.bank || t.address !== f.address || t.size !== f.size)
          return "save field " + f.label + " moved, which this step does not expect";
      }
      if (sramField(from, "sRogueOfferDVs")) return "this save already has reward offer DVs";
      var dvs = sramField(to, "sRogueOfferDVs"), tags = sramField(to, "sRogueOfferDVTag");
      if (!dvs || !tags || dvs.size !== 6 || tags.size !== 3 || dvs.bank !== tags.bank ||
          offsetOf(tags.bank, tags.address) !== offsetOf(dvs.bank, dvs.address) + dvs.size)
        return "reward offer DV layout not recognised";
      var start = offsetOf(dvs.bank, dvs.address), end = start + dvs.size + tags.size;
      for (var j = 0; j < from.sram.length; j++) {
        var g = from.sram[j], go = offsetOf(g.bank, g.address);
        if (g.size && go < end && go + g.size > start) return "the reward offer DVs would overwrite " + g.label;
      }
      for (var n = start; n < end; n++) bytes[n] = 0;
      return null;
    },

    // Schema 4 -> 5 (2026-10-07): wPlayerStarterForm, one byte carved from the pad after
    // wFossilMon in the main block, so nothing moved. Zeroed (the base form), as a new game
    // leaves it, and the main checksum recomputed since the block covers it.
    playerStarterFormAdded: function (bytes, from, to) {
      for (var i = 0; i < from.sram.length; i++) {
        var f = from.sram[i], t = sramField(to, f.label);
        if (!t || t.bank !== f.bank || t.address !== f.address || t.size !== f.size)
          return "save field " + f.label + " moved, which this step does not expect";
      }
      if (wramField(from, "wPlayerStarterForm")) return "this save already has a starter form";
      var fossil = wramOffset(from, "wFossilMon"), form = wramOffset(to, "wPlayerStarterForm");
      if (fossil < 0 || wramOffset(to, "wFossilMon") !== fossil || form !== fossil + 1)
        return "starter form layout not recognised";
      bytes[form] = 0;
      recomputeChecksums(bytes, to, ["main"]);
      return null;
    }
  };

  function convert(save, pkg, options) {
    options = options || {};
    var mode = options.mode || "continue";
    var target = pkg.target;
    var targetSchema = pkg.schemas[String(target.schema)];
    var from;
    var id = identify(save, pkg);
    if (!id.ok) return id;
    if (id.tagged) from = id.source;
    else {
      if (!options.source) return fail("needs_rom", id.reason);
      from = options.source;
      var sourceSchema = pkg.schemas[from];
      if (!sourceSchema) return fail("unknown_source", "This converter can't read saves from " + from + ".");
      var check = checkAgainst(save, sourceSchema, { tagged: false, source: from });
      if (!check.ok) return check;
    }
    var out = new Uint8Array(save);
    var report = { from: from, to: String(target.schema), mode: mode, steps: [] };

    if (mode === "continue") {
      if (from === String(target.schema)) {
        report.steps.push("already in this build's save format; nothing to change");
      } else {
        // Follow migrations one schema at a time, so a save that skipped releases still arrives.
        var at = from, seen = {};
        while (at !== String(target.schema)) {
          var migration = findMigration(pkg, at);
          if (!migration || seen[at])
            return fail("no_migration", "There's no way to carry this save into this build" +
              (pkg.recovery ? ". A recovery (keeping permanent progress) may be possible." : "."));
          seen[at] = true;
          for (var i = 0; i < migration.steps.length; i++) {
            var step = STEPS[migration.steps[i]];
            if (!step) return fail("bad_package", "Unknown migration step " + migration.steps[i] + ".");
            var refusal = step(out, pkg.schemas[at], pkg.schemas[migration.to]);
            if (refusal) return fail("refused", refusal);
            report.steps.push(at + " -> " + migration.to + ": " + migration.steps[i]);
          }
          at = migration.to;
        }
        writeHeader(out, target.schema);
        report.steps.push("wrote save format " + target.schema);
      }
    } else if (mode === "recovery") {
      var made = recover(save, pkg, from, report);
      if (!made.ok) return made;
      out = made.bytes;
    } else {
      return fail("mode", "Unknown conversion mode " + mode + ".");
    }

    var verify = identify(out, pkg);
    if (!verify.ok || !verify.tagged || verify.source !== String(target.schema))
      return fail("verify", "The converted save failed its own check (" + (verify.reason || "wrong format") + "). Nothing was changed.");
    report.checksums = verify.checksums;
    return { ok: true, bytes: out, report: report };
  }

  // Recovery: the target's verified post-reset Dorm save, with the source's permanent progress
  // copied in. Only fields listed in pkg.recovery.keep are carried, each by label, and only when
  // source and target agree on its size.
  function recover(save, pkg, from, report) {
    var r = pkg.recovery;
    if (!r || !r.template) return fail("no_recovery", "Recovery isn't offered for this build yet.");
    var sourceSchema = pkg.schemas[from];
    var targetSchema = pkg.schemas[String(pkg.target.schema)];
    var out = base64Bytes(r.template);
    if (out.length !== SRAM_SIZE) return fail("bad_package", "The recovery template is damaged.");
    var kept = [], lost = [];
    function copy(srcOff, dstOff, size) { for (var i = 0; i < size; i++) out[dstOff + i] = save[srcOff + i]; }
    r.keep_sram.forEach(function (label) {
      var a = sramField(sourceSchema, label), b = sramField(targetSchema, label);
      if (!a || !b || a.size !== b.size) { lost.push(label); return; }
      copy(offsetOf(a.bank, a.address), offsetOf(b.bank, b.address), a.size);
      kept.push(label);
    });
    r.keep_wram.forEach(function (label) {
      var a = wramField(sourceSchema, label), b = wramField(targetSchema, label);
      if (!a || !b || a.size !== b.size) { lost.push(label); return; }
      copy(wramOffset(sourceSchema, label), wramOffset(targetSchema, label), a.size);
      kept.push(label);
    });
    (r.keep_event_bytes || []).forEach(function (range) {
      var a = wramOffset(sourceSchema, "wEventFlags"), b = wramOffset(targetSchema, "wEventFlags");
      copy(a + range[0], b + range[0], range[1] - range[0]);
    });
    recomputeChecksums(out, targetSchema, r.recompute_checksums);
    writeHeader(out, pkg.target.schema);
    report.kept = kept;
    report.lost = lost.concat(r.always_lost || []);
    report.steps.push("started from the post-reset Dorm template", "copied " + kept.length + " permanent fields");
    return { ok: true, bytes: out };
  }

  function base64Bytes(text) {
    if (typeof atob === "function") {
      var bin = atob(text), out = new Uint8Array(bin.length);
      for (var i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
      return out;
    }
    return new Uint8Array(Buffer.from(text, "base64"));
  }

  var api = {
    SRAM_SIZE: SRAM_SIZE,
    identify: identify,
    sourceFromRom: sourceFromRom,
    convert: convert,
    readHeader: readHeader,
    checksumStatus: checksumStatus,
    _internal: { sum8: sum8, writeHeader: writeHeader, recomputeChecksums: recomputeChecksums, wramOffset: wramOffset,
      offsetOf: offsetOf, boundsProblems: boundsProblems, STEPS: STEPS }
  };
  if (typeof module === "object" && module.exports) module.exports = api;
  else root.RRSaveConvert = api;
})(typeof self !== "undefined" ? self : this);
