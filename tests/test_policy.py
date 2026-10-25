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


class PolicyCase(unittest.TestCase):
    def setUp(self):
        self.lua, self.p = load_policy()

    def hit(self, t, who, reaction='none', ranged=False):
        self.p.hit(self.p, t, who, reaction, ranged)

    def may_hit(self, t, who, ranged=False):
        return self.p.mayHit(self.p, t, who, ranged)

    def roles(self, t, *enemies):
        """enemies: (id, dist[, ranged[, targetsPlayer]]) -> {id: role} (only ids policy returned)."""
        rows = []
        for e in enemies:
            e = (*e, False, True)[:4] if len(e) == 2 else (*e, True)[:4] if len(e) == 3 else e
            rows.append(self.lua.table_from({'id': e[0], 'dist': e[1], 'ranged': e[2], 'targetsPlayer': e[3]}))
        res = self.p.roles(self.p, t, self.lua.table_from(rows))
        return dict(res.items())


class WindowTest(PolicyCase):
    def test_stagger_opens_window(self):
        self.hit(0.0, 'A', 'stagger')
        self.assertEqual(self.p.protection(self.p, 1.0), 'stagger')
        self.assertFalse(self.p.mayStagger(self.p, 1.0))
        self.assertIsNone(self.p.protection(self.p, 1.6))
        self.assertTrue(self.p.mayStagger(self.p, 1.6))

    def test_no_window_without_reaction(self):
        self.hit(0.0, 'A')
        self.assertIsNone(self.p.protection(self.p, 0.1))
        self.assertTrue(self.may_hit(0.2, 'A'))

    def test_causer_gets_one_followup(self):
        self.hit(0.0, 'A', 'stagger')
        self.assertTrue(self.may_hit(0.5, 'A'))
        self.hit(0.5, 'A')
        self.assertFalse(self.may_hit(0.8, 'A'))

    def test_causer_locked_until_recovered(self):
        self.hit(0.0, 'A', 'stagger')
        self.hit(0.5, 'A')
        self.assertEqual(self.roles(1.9, ('A', 100)), {'A': 'wait'})
        self.assertEqual(self.roles(2.1, ('A', 100)), {'A': 'attack'})

    def test_causer_without_followup_locked_after_window(self):
        self.hit(0.0, 'A', 'stagger')
        self.assertEqual(self.roles(1.0, ('A', 100)), {'A': 'attack'})
        self.assertEqual(self.roles(1.7, ('A', 100)), {'A': 'wait'})
        self.assertEqual(self.roles(2.1, ('A', 100)), {'A': 'attack'})

    def test_other_enemy_one_hit_in_window(self):
        self.hit(0.0, 'A', 'stagger')
        self.assertTrue(self.may_hit(0.3, 'B'))
        self.hit(0.3, 'B')
        self.assertFalse(self.may_hit(0.6, 'B'))
        self.assertTrue(self.may_hit(1.6, 'B'))

    def test_exhausted_enemy_does_not_attack_until_window_ends(self):
        self.hit(0.0, 'A', 'stagger')
        self.hit(0.3, 'B')
        self.assertNotEqual(self.roles(1.0, ('B', 100))['B'], 'attack')
        self.assertEqual(self.roles(1.6, ('B', 100))['B'], 'attack')

    def test_ranged_not_budgeted(self):
        self.hit(0.0, 'A', 'stagger')
        self.hit(0.2, 'R', ranged=True)
        self.hit(0.4, 'R', ranged=True)
        self.assertTrue(self.may_hit(0.6, 'R', ranged=True))

    def test_locked_causer_cannot_hit_after_window(self):
        self.hit(0.0, 'A', 'stagger')
        self.hit(0.5, 'A')
        self.assertFalse(self.may_hit(1.7, 'A'))
        self.assertTrue(self.may_hit(2.1, 'A'))

    def test_causer_without_followup_cannot_hit_after_window(self):
        self.hit(0.0, 'A', 'stagger')
        self.assertFalse(self.may_hit(1.7, 'A'))

    def test_locked_attacker_does_not_reopen_window(self):
        self.hit(0.0, 'A', 'stagger')
        self.hit(0.5, 'A')
        self.hit(1.7, 'A', 'stagger')
        self.assertIsNone(self.p.protection(self.p, 1.8))
        self.assertFalse(self.may_hit(1.9, 'A'))

    def test_reaction_inside_window_does_not_extend_it(self):
        self.hit(0.0, 'A', 'stagger')
        self.hit(1.0, 'B', 'stagger')
        self.assertIsNone(self.p.protection(self.p, 1.6))

    def test_knock_window(self):
        self.hit(0.0, 'A', 'knock')
        self.assertEqual(self.p.protection(self.p, 2.9), 'knock')
        self.assertFalse(self.p.mayStagger(self.p, 2.9))
        self.assertIsNone(self.p.protection(self.p, 3.1))
        self.assertTrue(self.may_hit(1.0, 'A'))
        self.hit(1.0, 'A')
        self.assertFalse(self.may_hit(1.5, 'A'))
        self.assertEqual(self.roles(3.4, ('A', 100)), {'A': 'wait'})
        self.assertEqual(self.roles(3.6, ('A', 100)), {'A': 'attack'})


class RolesTest(PolicyCase):
    def test_roles_by_distance(self):
        self.assertEqual(self.roles(0.0, ('A', 300), ('B', 100), ('C', 200)), {'B': 'attack', 'C': 'ready', 'A': 'wait'})

    def test_attack_slot_is_sticky(self):
        self.roles(0.0, ('A', 100), ('B', 200))
        self.assertEqual(self.roles(0.1, ('A', 200), ('B', 100)), {'A': 'attack', 'B': 'ready'})

    def test_slot_freed_when_holder_locked(self):
        self.roles(0.0, ('A', 100), ('B', 200))
        self.hit(0.1, 'A', 'stagger')
        self.hit(0.4, 'A')
        self.assertEqual(self.roles(0.5, ('A', 100), ('B', 200)), {'A': 'wait', 'B': 'attack'})

    def test_single_enemy_attacks(self):
        self.assertEqual(self.roles(0.0, ('A', 500)), {'A': 'attack'})

    def test_roles_ignore_non_player_targets(self):
        self.assertEqual(self.roles(0.0, ('G', 100, False, False), ('A', 300)), {'A': 'attack'})

    def test_ranged_is_free(self):
        self.assertEqual(self.roles(0.0, ('R', 50, True), ('A', 300)), {'R': 'free', 'A': 'attack'})

    def test_config_attackers_two(self):
        self.lua, self.p = load_policy(attackers=2, ready=0)
        self.assertEqual(self.roles(0.0, ('A', 100), ('B', 200), ('C', 300)), {'A': 'attack', 'B': 'attack', 'C': 'wait'})

    def test_combo_backoff(self):
        self.roles(0.0, ('A', 100))
        self.p.comboEnded(self.p, 0.0, 'A')
        self.assertEqual(self.roles(1.4, ('A', 100)), {'A': 'wait'})
        self.assertEqual(self.roles(1.6, ('A', 100)), {'A': 'attack'})

    def test_forget_releases_lock(self):
        self.hit(0.0, 'A', 'stagger')
        self.hit(0.5, 'A')
        self.p.forget(self.p, 'A')
        self.assertEqual(self.roles(0.6, ('A', 100)), {'A': 'attack'})

    def test_absent_holder_loses_slot(self):
        self.roles(0.0, ('A', 100), ('B', 200))
        self.assertEqual(self.roles(0.1, ('B', 200)), {'B': 'attack'})
        self.assertEqual(self.roles(0.2, ('A', 100), ('B', 200)), {'B': 'attack', 'A': 'ready'})

    def test_reset_clears_everything(self):
        self.roles(0.0, ('A', 100))
        self.hit(0.0, 'A', 'stagger')
        self.hit(0.2, 'A')
        self.p.reset(self.p)
        self.assertIsNone(self.p.protection(self.p, 0.3))
        self.assertTrue(self.may_hit(0.3, 'A'))
        self.assertEqual(self.roles(0.3, ('B', 100), ('A', 200)), {'B': 'attack', 'A': 'ready'})


class HelpersTest(PolicyCase):
    def test_combo_end_starts_backoff(self):
        self.roles(0.0, ('A', 100))
        self.p.observe(self.p, 0.0, 'A', 3, False)
        self.p.observe(self.p, 0.1, 'A', 0, True)
        self.assertEqual(self.roles(1.0, ('A', 100)), {'A': 'attack'})
        self.p.observe(self.p, 2.0, 'A', 0, False)
        self.assertEqual(self.roles(3.4, ('A', 100)), {'A': 'wait'})
        self.assertEqual(self.roles(3.6, ('A', 100)), {'A': 'attack'})

    def test_simple_attacks_no_backoff(self):
        self.p.observe(self.p, 0.0, 'A', 1, True)
        self.p.observe(self.p, 0.5, 'A', 2, False)
        self.assertEqual(self.roles(0.6, ('A', 100)), {'A': 'attack'})
