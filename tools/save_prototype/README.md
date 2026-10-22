# Isolated protected-main ROM experiment

These files are not included in the production build. `prepare.py` modifies a
separate, already-built source copy inside this workspace. Do not use its ROM or
format fixtures with a real player save.

The executable slice implements `PSSelect`, `PSSave`, and `PSLoad` against the
physical map in `model_save_handoff.Layout('sum8', descriptor=True,
shared_marker=True)`. It uses the existing 3,800-byte main payload, two framed
records, and the model's two 18-byte CRC32-protected selectors. Writes invalidate
the inactive record, copy generation and payload, publish its checksum and
marker, then publish the inactive selector marker last. Selection validates
format, modular sequence ordering, selected generation, checksum, marker and
active-box identity. Equal/half-range sequences refuse. Context must be DONE,
with no undo cursor and an active box below 12. An invalid selected context
refuses instead of silently choosing an older record.

`PSLoad` validates before changing serialized WRAM/HRAM. `PSSave` requires the
same active box. Input WRAM is assumed already prepared; gamma synchronization
and theft-snapshot preparation remain the caller's responsibility. Unknown
formats, including genuine schema-11 saves, are refused by these primitives
without SRAM or serialized-destination writes. `wPSResult` is 0 for success and
1 for refusal. Scratch fields initialize at their producing routines; no cache
or persistent caller authorization is assumed.

The host seeds an already-initialized experimental format fixture. This is not
new-game initialization, a production schema change, or a migration converter.
The production Continue implementation still refuses the experimental format.
Cold-load tests explicitly invoke `PSLoad` at a safe title boundary; they do not
demonstrate the player-facing Continue/map-entry lifecycle.

Only the isolated copy gets a SaveGameData dispatch that recognizes the exact
experimental descriptor and invokes PSSave. Other formats follow the existing
writer. This measurement adapter permits real START > SAVE profiling with live
interrupts; it does not make a complete player-save system. In particular:

- Companion SRAM, rental/reset/PC journals, derived box-checksum repair,
  migration, and early boot recovery dispatch are not implemented here.
- The active archive's first 251 bytes and all modeled pool extents belong to
  the experiment. Box changes must refuse until the modeled handoff exists.
- Payload integrity remains additive sum8. Balanced corruption can collide.
- Unallocated SRAM extents are explicitly reserved in the isolated RAM file;
  the three existing padding spans receive names without moving other fields.
- The experiment adds 79 WRAM bytes. It does not use a union reclamation.
- All reserved X7 pages remain untouched.

First-pass evidence is under
`tools/pyboy_smoke/artifacts/save_main_prototype_2026-10-22_00f2dd1d`.
The live save measurement exceeds the 50 ms target. Keep the experiment out of
production and optimize measured selection/validation before integration.

Reproduction, from the repository root with a built, isolated source copy:

```text
python tools/save_prototype/prepare.py tmp/ISOLATED_BUILT_SOURCE
wsl make -C tmp/ISOLATED_BUILT_SOURCE
wsl python3 tools/save_prototype/verify.py tmp/ISOLATED_BUILT_SOURCE --output tmp/PROOF
wsl python3 tools/save_prototype/profile.py tmp/ISOLATED_BUILT_SOURCE --output tmp/PROOF
```

`verify.py` checks all 12 active boxes and both destination slots, captures the
actual ROM write trace, replays every byte boundary with the independent model,
tries every torn byte value at metadata/marker stores, and cold-boots actual
SRAM snapshots captured at instruction boundaries. The snapshot reader restores
the live bank and enable state before the observed CPU store resumes. Full
parked baselines are restored between independent routine probes.

`profile.py` uses real save-menu inputs and calibrates PyBoy's counter against
display frames independently for DMG/CGB single/CGB double speed. Every sample
must service VBlank. These small phase samples identify bottlenecks; they are
not the final 60-phase protected-writer acceptance gate.
