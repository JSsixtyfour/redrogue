# Red Rogue

A roguelike built on the [pret/pokered](https://github.com/pret/pokered) disassembly.

## Building

See [INSTALL.md](INSTALL.md) for toolchain setup (rgbds version in `.rgbds-version`). Build from WSL
or Linux:

```sh
make            # pokered.gbc, pokeblue.gbc, pokeblue_debug.gbc
```

Always build all three ROMs when verifying a change. Every link is also archived to `builds/` with its
matching `.sym`, stamped with date and git hash (`BUILD_KEEP=N` keeps the newest N per ROM).

## Verification

| Target | What it checks |
| --- | --- |
| `make smoke` | PyBoy smoke suite against `pokeblue_debug.gbc`. `make smoke TEST='*pattern*'` runs a subset; `python3 tools/pyboy_smoke/run_smoke.py --list` lists test IDs. See [tools/pyboy_smoke/README.md](tools/pyboy_smoke/README.md). |
| `make audit` | Static bank/call/clobber, stack, SRAM, and text-trap analyzers over all three ROMs. `INFO=1` shows info-level findings; triage lives in `tools/static_audit/allowlist.txt`. |
| `make space` | Free bytes per bank (total and largest gap, min across all three ROMs) with deltas since the last run, plus which labels changed bank or shifted (`tools/sym_diff.py`). `SPACE_ARGS='--all'` shows every bank; `SPACE_ARGS='--min-free ROM0=64'` enforces a floor. |
| `make audits_long` | The slower standalone regression guards registered in `tools/pyboy_smoke/audits.json` (about 5 minutes). `AUDITS='*cave*'` narrows the set; `run_audits.py --list` shows what each guards. |
| `make integration` | Slower tier that drives complete gameplay interactions. |
| `make balance_report` | Balance model self-check and report. |

`git config core.hooksPath tools/hooks` enables a pre-commit hook that runs the source-only map and
text audits (a few seconds, and only when relevant files are staged) and compiles staged Python.

A clean build proves only that the ROM links. Visual and timing behavior (palettes, fades, raster
effects, walk cadence) still needs a BGB check.

## Project docs

Design plans, the ROM and WRAM space ledgers, and debugging guides live outside the repo, in the
`Red Rogue Files` folder. Agent instructions are in `CLAUDE.md` and `AGENTS.md`.
