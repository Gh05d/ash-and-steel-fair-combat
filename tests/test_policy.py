import unittest
from pathlib import Path

import lupa.lua54 as lupa
from luaparser import ast

SCRIPTS = Path(__file__).resolve().parent.parent / 'mod' / 'FairCombat' / 'Scripts'

DEFAULTS = {'staggerWindow': 1.5, 'recoverBuffer': 0.5, 'knockWindow': 3.0,
            'attackers': 1, 'ready': 1, 'comboBackoff': 1.5}


def load_policy(**overrides):
    """Returns (lua runtime, policy instance) for a cfg table built from DEFAULTS plus overrides."""
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(f'package.path = "{SCRIPTS.as_posix()}/?.lua;" .. package.path')
    policy = lua.eval('(require("policy"))')
    cfg = lua.table_from({**DEFAULTS, **overrides})
    return lua, policy.new(cfg)


class LoadTest(unittest.TestCase):
    def test_policy_module_loads(self):
        lua, p = load_policy()
        self.assertEqual(lupa.lua_type(p), 'table')

    def test_lua_syntax(self):
        files = sorted(SCRIPTS.glob('*.lua'))
        self.assertTrue(files)
        for f in files:
            with self.subTest(f.name):
                ast.parse(f.read_text(encoding='utf-8'))
