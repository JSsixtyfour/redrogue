#!/usr/bin/env python3
"""Audit dialogue text for letters the engine erases or pushes past the box.

The text box has 18 columns, 1 to 18, but column 18 of the bottom row is also
where the engine draws its down arrow (home/text.asm, `ldcoord_a 18, 16`). `cont`,
`para`, `prompt` and `text_promptbutton` all overwrite that tile with the arrow,
and `cont` and `prompt` then blank it. An 18-wide bottom line therefore loses its
last letter before a wait: "wants to join your" scrolled up as "wants to join you"
(Psychic Psyduck's join offer, measured from wTileMap 2026-11-06).

`done` and a bare `text_end` place no arrow: WaitForTextScrollButtonPress starts
its blink counter at 0, which keeps HandleDownArrowBlinkTiming from drawing one.
An 18-wide line before those is fine, and so is one on the top row.

It also fails a text command inside a string that `@` has not closed. `text` is byte
$00 there, which PlaceNextChar runs as NullChar: _Route3Youngster4AfterBattleText and
FacManiacBeatenText each stopped at an error line instead of finishing the sentence.

  FIX       a literal line meets the arrow or passes column 18, or a command sits
            in an open string. Fails the audit.
  DYNAMIC   the line holds a name or number and reaches column 18 only at its
            worst-case width. Listed with --all, does not fail.

Rows are followed through `text_far`, so a wrapper's `text_promptbutton` is checked
against the line its body ended on. After `next` the row is unknown (Pokedex pages
and menu layouts), and nothing is reported until the next `line`, `cont` or `para`.

The audit reads source, so it cannot tell whether a player ever sees a line. Vanilla
text on maps the game never enters stays as pret wrote it, listed in UNUSED_TEXT: that
list is written by hand because a reachability guess called the player's own Dorm dead.
For scale, pret's whole tree has 3 literal arrow hits in 8154 strings.

  python tools/audit_text_columns.py          # problems only
  python tools/audit_text_columns.py --all    # dynamic and unused lines too
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCAN_DIRS = ("text", "data/text", "scripts", "engine", "custom_functions", "home")
TOP, BOTTOM = 14, 16
COLUMNS = 18

FIXED_WIDTH = {"#": 4, "<PKMN>": 2, "<PC>": 2, "<TM>": 2, "<TRAINER>": 7, "<ROCKET>": 6}
# Worst case. <USER> and <TARGET> can print "Enemy " before a 10-letter name.
NAME_WIDTH = {"<PLAYER>": 7, "<RIVAL>": 7, "<USER>": 16, "<TARGET>": 16}
RAM_WIDTH = {"wPlayerName": 7, "wRivalName": 7, "wBoxNumString": 2}
UNKNOWN_RAM_WIDTH = 10

LABEL = re.compile(r"^([A-Za-z_][\w]*|\.[\w]+)(::?)?(\s|$)")
STRING_COMMAND = re.compile(r'^(text|line|cont|para|next|page)\s+"(.*)"$')
TOKEN = re.compile(r"<[^<>]*>|'[dlmrstv]|\{[^}]*\}|\\.|.", re.S)  # the 'x glyphs are one tile
# Bytes below the charmap's letters: in an open string they print or stop it.
COMMANDS_NEEDING_CLOSED_STRING = {"text_start", "text_ram", "text_bcd", "text_decimal", "text_far",
                                  "text_asm", "text_promptbutton", "text_scroll", "text_pause",
                                  "text_dots", "text_waitbutton"}
NOT_A_LABEL = {"text", "line", "cont", "para", "next", "page", "prompt", "done", "dex"}
# Remove an entry if its map comes back into play: its findings count again from then on.
UNUSED_TEXT = {
    "text/SaffronGates.asm": "vanilla: no warp enters the Route 5 to 8 gates in a run",
}


def strip_comment(raw):
    quoted = False
    for i, ch in enumerate(raw):
        if ch == '"':
            quoted = not quoted
        elif ch == ";" and not quoted:
            return raw[:i]
    return raw


class Finding:
    def __init__(self, path, number, text, width, why, dynamic):
        self.path, self.number, self.text = path, number, text
        self.width, self.why, self.dynamic = width, why, dynamic

    def __str__(self):
        return f'{self.path}:{self.number}: "{self.text}" is {self.width} wide, {self.why}'


class Cursor:
    """Where the next letter lands. row None: not in a body, or a layout we can't place."""

    def __init__(self):
        self.reset()

    def reset(self):
        self.row = None
        self.width = 0
        self.dynamic = False
        self.shown = ""
        self.where = None
        self.source = None  # the file `where` is in, when a text_far crossed into another
        self.open = False  # a string is open: a command byte here prints or stops it

    def new_row(self, row, where):
        self.row, self.width, self.dynamic, self.shown, self.where = row, 0, False, "", where
        self.source = None

    def visible_width(self):
        """A trailing space has nothing to lose, at column 18 or past it."""
        return self.width - (len(self.shown) - len(self.shown.rstrip(" ")))


def scan(path_name, lines, far_exits, findings):
    """Walk one file. Returns {label: (row, width, dynamic, shown, where, source)} at each body's end."""
    exits = {}
    cursor = Cursor()
    scope = None
    labels = []
    overflowed = set()

    def add_letters(string):
        for token in TOKEN.findall(string):
            if token == "@":
                cursor.open = False
                return
            if token in ("<LINE>", "<CONT>", "<PARA>", "<NEXT>", "<PROMPT>", "<DONE>"):
                cursor.shown += token
                continue
            if token in NAME_WIDTH:
                cursor.width += NAME_WIDTH[token]
                cursor.dynamic = True
            elif token.startswith("{") or token.startswith("\\"):
                cursor.width += 1
                cursor.dynamic = True
            else:
                cursor.width += FIXED_WIDTH.get(token, 1)
            cursor.shown += token

    def check_overflow():
        if cursor.row is None or cursor.dynamic or cursor.where in overflowed:
            return
        if cursor.visible_width() > COLUMNS:
            overflowed.add(cursor.where)
            findings.append(Finding(path_name, cursor.where, cursor.shown, cursor.visible_width(),
                                    "past column 18", False))

    def check_arrow(command):
        width = cursor.visible_width()
        if cursor.row != BOTTOM or width < COLUMNS or width > COLUMNS and not cursor.dynamic:
            return
        findings.append(Finding(cursor.source or path_name, cursor.where, cursor.shown, width,
                                f"its column 18 is erased by the arrow of `{command}`", cursor.dynamic))

    def check_closed(command, number):
        if cursor.open:
            findings.append(Finding(path_name, number, cursor.shown, cursor.width,
                                    f"`{command}` follows it with no @, inside the open string", False))
            cursor.open = False

    def save_exit():
        state = (cursor.row, cursor.width, cursor.dynamic, cursor.shown, cursor.where,
                 cursor.source or path_name)
        for label in labels:
            exits.setdefault(label, state)

    for number, raw in enumerate(lines, 1):
        code = strip_comment(raw).strip()
        if not code:
            continue
        first = code.split()[0].rstrip(":")
        at_column_0 = raw[:1] not in (" ", "\t")
        match = LABEL.match(code)
        if match and (at_column_0 or code.startswith(".")) and first not in NOT_A_LABEL and (
                match.group(2) or code.startswith(".") or code == first):
            name = match.group(1)
            if name.startswith("."):
                labels.append(f"{scope}{name}")
            else:
                scope = name
                labels = [name]
            cursor.reset()
            rest = code[match.end():].strip()
            if not rest:
                continue
            code = rest
            first = code.split()[0]

        string = STRING_COMMAND.match(code)
        if string:
            command, body = string.groups()
            if command == "text":
                check_closed("text", number)
                if cursor.row is None and not cursor.where:
                    cursor.new_row(TOP, number)
                cursor.open = True
            elif command == "line":
                check_overflow()
                cursor.new_row(BOTTOM, number)
            elif command == "cont":
                check_overflow()
                check_arrow("cont")
                cursor.new_row(BOTTOM, number)
            elif command == "para":
                check_overflow()
                check_arrow("para")
                cursor.new_row(TOP, number)
            else:  # next, page: a layout this audit does not place
                check_overflow()
                cursor.new_row(None, number)
            cursor.open = True
            add_letters(body)
            check_overflow()
            continue

        if first in COMMANDS_NEEDING_CLOSED_STRING:
            check_closed(first, number)
        if first == "text_start":
            if cursor.row is None and not cursor.where:
                cursor.new_row(TOP, number)
            cursor.open = True
        elif first == "text_ram":
            ram = code.split()[1].rstrip(",")
            cursor.width += RAM_WIDTH.get(ram, UNKNOWN_RAM_WIDTH)
            cursor.dynamic = True
            cursor.shown += f"<{ram}>"
        elif first in ("text_bcd", "text_decimal"):
            args = [arg.strip() for arg in code.split(None, 1)[1].split(",")]
            digits = re.search(r"\d+", args[-1])
            count = int(digits.group()) if digits and first == "text_decimal" else 6
            cursor.width += count
            cursor.dynamic = True
            cursor.shown += f"<{count} digits>"
        elif first == "text_far":
            target = code.split()[1]
            state = far_exits.get(target)
            if state:
                cursor.row, cursor.width, cursor.dynamic, cursor.shown, cursor.where, cursor.source = state
            else:
                cursor.new_row(None, number)
        elif first == "text_promptbutton":
            check_arrow("text_promptbutton")
            cursor.width = cursor.width if cursor.row is None else 0
            cursor.dynamic = False
        elif first == "prompt":
            check_arrow("prompt")
            cursor.reset()
        elif first in ("done", "dex"):
            cursor.reset()
        elif first == "text_end":
            save_exit()
            cursor.reset()
        elif first == "text_scroll":
            cursor.new_row(BOTTOM, number)
        elif first in ("text_pause", "text_dots", "text_waitbutton", "text_low",
                       "text_box", "text_move") or first.startswith("sound_"):
            continue
        else:
            # Code or data: the text stream, if any, has ended.
            cursor.reset()
    return exits


def far_exit_map(sources):
    exits = {}
    for name, lines in sources.items():
        exits.update(scan(name, lines, {}, []))
    return exits


def load_sources():
    sources = {}
    for folder in SCAN_DIRS:
        for path in sorted((ROOT / folder).rglob("*.asm")):
            sources[str(path.relative_to(ROOT)).replace("\\", "/")] = path.read_text(
                encoding="utf-8", errors="replace").splitlines()
    return sources


def audit(sources, skip=UNUSED_TEXT):
    far_exits = far_exit_map(sources)
    findings = []
    for name, lines in sources.items():
        scan(name, lines, far_exits, findings)
    # The same location only: one body reached through several wrappers.
    unique, seen = [], set()
    for finding in findings:
        key = (finding.path, finding.number, finding.why)
        if key not in seen and finding.path not in skip:
            seen.add(key)
            unique.append(finding)
    return unique


def main(argv):
    sys.stdout.reconfigure(encoding="utf-8")
    fix, dynamic, unused = [], [], []
    for finding in audit(load_sources(), skip=()):
        if finding.path in UNUSED_TEXT:
            unused.append(finding)
        else:
            (dynamic if finding.dynamic else fix).append(finding)
    for finding in fix:
        print(f"FIX      {finding}")
    if "--all" in argv:
        for finding in dynamic:
            print(f"DYNAMIC  {finding}")
        for finding in unused:
            print(f"UNUSED   {finding} ({UNUSED_TEXT[finding.path]})")
    print(f"\n{len(fix)} to fix, {len(dynamic)} dynamic (worst case only), {len(unused)} in unused text")
    return 1 if fix else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
