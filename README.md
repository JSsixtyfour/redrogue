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

## Releasing to testers

```sh
make release
```

From WSL, with everything committed and pushed. It asks for "What's new" and "What to test" (Enter
on "What's new" lets the playtest bot draft it from the commit messages), then:

1. Refuses uncommitted changes or an unpushed commit, before building anything.
2. Builds all three ROMs and runs `make smoke`. Any failure stops it; nothing is sent.
3. Keeps that build's `pokeblue_debug_` `.gbc` and `.sym` in `builds/releases/`, which `BUILD_KEEP`
   never prunes, so crash screens from it can always be looked up.
4. Sends the ROM to the playtest bot through a Discord webhook. The bot makes the patches, updates the
   patch page, marks reports Fixed from `Fixes RR-0012` commits, announces, and replies under the
   webhook's message in that channel.

`make release RELEASE_ARGS='--notes "New gym" --testing "Gym 3"'` skips the questions,
`--no-announce` sets the build without announcing it, and `--dry-run` does everything except send.

**One-time setup:** in a private developers' channel, **Edit Channel > Integrations > Webhooks > New
Webhook**, copy its URL, and put it in an untracked `.env` at the repo root:

```
RELEASE_WEBHOOK_URL=https://discord.com/api/webhooks/...
```

The bot side (its `release_webhook_id` and the Message Content intent) is in the playtest bot's
README.

## Crash screen

In the debug build, a crash shows a screen instead of freezing. It catches a jump into unused ROM
or to `$0000`, which is how most of this project's bugs end. Release builds still just hang.
`tools/crash_lookup.py` turns that screen into routine names, using the `.sym` that `builds/`
archived for that exact build.

**When a tester sends a crash screenshot**, open PowerShell in the repo folder (type `powershell` in
File Explorer's address bar while in `redrogue`) and run:

```
py tools\crash_lookup.py
```

It asks for four things, all copied from the screen:

| It asks for | Where it is on the screen | Example |
| --- | --- | --- |
| ID line | line 4, after `ID` | `9dba3ff3-dirty` |
| Date and time | line 3 (only needed if you built that commit more than once; Enter skips) | `2026-10-01 13:24` |
| PC line | after `PC` | `00:3E7C` |
| The six STACK words | the three `STACK` lines, left to right, top to bottom | `352B 01DC 2240 3733 3785 3070` |

Or type it all on one line: `py tools\crash_lookup.py 9dba3ff3 00:3E7C 352B 01DC 2240 3733 3785 3070`
(add `--built "2026-10-01 13:24"` to pick between builds of the same commit). From WSL, use
`python3 tools/crash_lookup.py` the same way.

**Reading the answer:**
- `PC` is where the CPU ended up. If it says the byte is `$FF` padding, the bug is whatever *jumped
  there*, not the code at that address.
- Each `stack` line is a lead on who called whom, most recent first. HOME addresses (below `4000`)
  are exact. Addresses from `4000` to `7FFF` are looked up in the crash's bank, which is wrong if
  that call came through a farcall from another bank. A word that lands exactly on a label (no
  `+$..`) is usually a saved register, not a call.
- The screen also shows the registers, the WRAM bank (anything other than `01` at a crash is itself
  a clue, see WRAM Bible section I1), and the map with X and Y.

Next step is the usual one: put a BGB breakpoint on the routine the stack names, and reproduce.

It needs that build's `.sym`. Builds sent with `make release` are kept for good in
`builds/releases/`, which the tool searches too. Anything else lives only in `builds/`, where
`BUILD_KEEP` (default 20 per ROM) prunes older ones within a day or two of normal work: copy those
somewhere safe and pass the `.sym` path in place of the ID. A clean commit can also be rebuilt for
the same addresses; a `-dirty` build cannot.

## Project docs

Design plans, the ROM and WRAM space ledgers, and debugging guides live outside the repo, in the
`Red Rogue Files` folder. Agent instructions are in `CLAUDE.md` and `AGENTS.md`.
