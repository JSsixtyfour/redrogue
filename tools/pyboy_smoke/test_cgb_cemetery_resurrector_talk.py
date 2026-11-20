"""test_cemetery_resurrector_talk on CGB (the smoke runner classifies modules by name)."""

from __future__ import annotations

import unittest

import test_cemetery_resurrector_talk as talk


class CGBIronmanTalkTest(talk.IronmanTalkTest):
    CGB = True


class CGBReviveTalkTest(talk.ReviveTalkTest):
    CGB = True


if __name__ == "__main__":
    unittest.main()
