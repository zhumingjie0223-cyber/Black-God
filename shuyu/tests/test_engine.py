# 枢语引擎测试（Python 侧）— 容量/往返/纯净度/追加式铁律
# 运行: python3 -m unittest discover -s tests -v
import os
import re
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import shuyu_engine as e

CAP_EXPECTED = 1040 * 180 * 80 * 64 * 8  # 7,667,712,000


def _sample_ids(seed, n):
    """确定性伪随机采样（线性同余），保证测试可复现"""
    x = seed
    out = []
    for _ in range(n):
        x = (6364136223846793005 * x + 1442695040888963407) % (1 << 64)
        out.append(x % CAP_EXPECTED)
    return out


class TestCapacity(unittest.TestCase):
    def test_capacity(self):
        self.assertEqual(e.CAP, CAP_EXPECTED)

    def test_axis_sizes(self):
        self.assertEqual((e.NC, e.NM, e.NS, e.NK, e.NP), (1040, 180, 80, 64, 8))


class TestDecode(unittest.TestCase):
    def test_boundaries(self):
        first = e.decode(0)
        self.assertEqual(first["词"], "Ao-cor-is·qi")
        self.assertEqual(first["汉"], "奥形凝起")
        e.decode(CAP_EXPECTED - 1)  # 不抛错即通过
        with self.assertRaises(ValueError):
            e.decode(-1)
        with self.assertRaises(ValueError):
            e.decode(CAP_EXPECTED)

    def test_pure_chinese(self):
        pure = re.compile(r"^[㐀-鿿]+$")
        for i in [0, CAP_EXPECTED - 1] + _sample_ids(42, 300):
            han = e.decode(i)["汉"]
            self.assertRegex(han, pure, f"编号 {i} 汉译不纯: {han}")


class TestRoundtrip(unittest.TestCase):
    def test_decode_encode(self):
        for i in [0, 1, 2949119999, 2949120000, CAP_EXPECTED - 1] + _sample_ids(20260712, 500):
            word = e.decode(i)["词"]
            self.assertEqual(e.encode(word), i, f"编号 {i} 往返失败: {word}")

    def test_encode_invalid(self):
        for bad in ["", "不是词", "Ao-cor", "Zzz-cor-is·qi"]:
            self.assertEqual(e.encode(bad), -1)


class TestRobustness(unittest.TestCase):
    """健壮性与单射性回归（2026-09 补）

    背景：消费副本 web/nexus-do/lexicon.js 早就硬化过畸形输入，权威源头
    （本文件与 lexicon.js）却一直没跟上，三侧错误处理各走各的。漏网原因是
    老测试只喂合法编号，从不测非法输入。这一组专门守住这条线。
    """

    def test_decode_type_guard(self):
        # nan 与任何数比大小都是 False，会直接穿过 n<0 or n>=CAP 这道区间检查
        for bad in [float("nan"), 1.5, None, "100", True, b"1", []]:
            with self.assertRaises(TypeError, msg=f"decode({bad!r}) 应抛 TypeError"):
                e.decode(bad)
        # 越界仍然是 ValueError，两类错误不许混
        with self.assertRaises(ValueError):
            e.decode(-1)
        with self.assertRaises(ValueError):
            e.decode(CAP_EXPECTED)

    def test_encode_injective(self):
        """decode 产不出的畸形词形一律 -1，否则会冒领合法编号"""
        malformed = [
            "Ao-cor-is-·qi",       # 显式空标段：曾经返回 0，和 3 段词形撞号
            "Ao-cor-is·qi·qi",     # 多写一个相位分隔符
            "Ao-cor-is-gal-p·qi",  # 5 段，超出「核-映-态-标」上限
            "Ao-cor·qi",           # 只有 2 段
            "Ao-cor-is-gal",       # 缺相位
            "-cor-is·qi",          # 核轴为空
            "Ao-cor-is-XX·qi",     # 标轴词根不存在
        ]
        for bad in malformed:
            self.assertEqual(e.encode(bad), -1, f"畸形词「{bad}」不该被判为合法")

    def test_empty_scalar_single_form(self):
        """空标轴只有 3 段词形一种写法，编号 0 不被畸形词冒领"""
        self.assertEqual(e.decode(0)["词"], "Ao-cor-is·qi")
        self.assertEqual(e.encode("Ao-cor-is·qi"), 0)
        self.assertEqual(e.encode("Ao-cor-is-·qi"), -1)

    def test_encode_non_string(self):
        """非字符串入参不许抛，按非法词返回 -1"""
        for bad in [None, 123, [], {}]:
            self.assertEqual(e.encode(bad), -1)


class TestAppendOnly(unittest.TestCase):
    """追加式铁律：老编号一个不许动"""

    def test_first_20_families_frozen(self):
        frozen = ["Ao", "Kha", "Lum", "Xun", "Zet", "Vea", "Nix", "Ohm", "Psi", "Shu",
                  "Gen", "Evo", "Lev", "Hid", "Ent", "Thr", "Sta", "Prj", "Msh", "Log"]
        self.assertEqual([b[0] for b in e._CORE_BASE[:20]], frozen)

    def test_v4_anchor_words(self):
        self.assertEqual(e.decode(2949119999)["词"], "Logxi-fncp-sta9-flxh·ying")
        self.assertEqual(e.decode(2949120000)["词"], "Aur-cor-is·qi")

    def test_layers_cover_all_families(self):
        self.assertEqual(len(e._LAYERS), len(e._CORE_BASE))
        self.assertEqual(e.decode(2949120000)["层"], "显照")
        self.assertEqual(e.decode(CAP_EXPECTED - 1)["层"], "冰川")


if __name__ == "__main__":
    unittest.main()


# ══════════════════════════════════════════════════════════════
# v4.1 新能力（2026-09-05）：汉译反向寻址 / 语义寻址 / 造词族对等 / CLI
# ══════════════════════════════════════════════════════════════

class TestDecodeShape(unittest.TestCase):
    def test_fields(self):
        d = e.decode(888888888)
        self.assertEqual(d["id"], 888888888)
        self.assertEqual(d["词"], "Nix-teks-ia1-h·qi")
        self.assertEqual(d["根"], ["Nix", "teks", "ia1", "h", "qi"])
        self.assertEqual(d["坐标"], {"c": 120, "m": 101, "s": 31, "k": 7, "p": 0})
        self.assertEqual(d["层"], "毁灭")
        self.assertIn("seed", d)  # 历史字段只增不删
        self.assertEqual(e.decode_full(888888888), d)

    def test_empty_scalar_root_is_null_mark(self):
        self.assertEqual(e.decode(0)["根"][3], "∅")
        self.assertEqual(e.decode(0)["坐标"], {"c": 0, "m": 0, "s": 0, "k": 0, "p": 0})

    def test_layer_by_index_equals_legacy(self):
        """层名改按下标取，必须与旧的 startswith 匹配完全一致"""
        for c in range(e.NC):
            self.assertEqual(e.decode(e._id_of(c, 0, 0, 0, 0))["层"], e._layer_of(e.CORES[c][0]))


class TestAxisCompleteness(unittest.TestCase):
    def test_axes(self):
        self.assertEqual(e.AXES, {"核": 1040, "映": 180, "态": 80, "标": 64, "相": 8})

    def test_every_root_reachable_and_roundtrips(self):
        ids = []
        ids += [e._id_of(c, c % e.NM, c % e.NS, c % e.NK, c % e.NP) for c in range(e.NC)]
        ids += [e._id_of(m % e.NC, m, 0, 0, 0) for m in range(e.NM)]
        ids += [e._id_of(0, 0, s, s % e.NK, 0) for s in range(e.NS)]
        ids += [e._id_of(1, 1, 1, k, 1) for k in range(e.NK)]
        ids += [e._id_of(0, 0, 0, 0, p) for p in range(e.NP)]
        self.assertEqual(len(ids), 1040 + 180 + 80 + 64 + 8)
        for i in ids:
            w = e.decode(i)
            self.assertEqual(e.encode(w["词"]), i, f"编号 {i} 拉丁往返失败")
            self.assertEqual(e.encode_han(w["汉"]), i, f"编号 {i} 汉译往返失败: {w['汉']}")

    def test_axis_roots_unique(self):
        for name, ax in [("核", e.CORES), ("映", e.MANIS), ("态", e.STATS), ("标", e.SCALS), ("相", e.PHASES)]:
            lats = [x[0] for x in ax]
            hans = [x[1] for x in ax]
            self.assertEqual(len(lats), len(set(lats)), f"{name}轴拉丁根重复")
            self.assertEqual(len(hans), len(set(hans)), f"{name}轴汉译重复")

    def test_han_prefix_lemma(self):
        """汉译唯一可解码的结构引理：各轴后缀字与下一轴首字零交集。词根表追加破坏它时这里当场红。"""
        first = lambda ax: {x[1][0] for x in ax if x[1]}
        self.assertFalse(set(e._HAN_TONE) - {""} & first(e.MANIS), "阶字不得是映轴首字")
        self.assertFalse(set(e._HAN_AURA) - {""} & first(e.STATS), "相字不得是态轴首字")
        self.assertFalse(set(e._HAN_FREQ) - {""} & (first(e.SCALS) | first(e.PHASES)), "频字不得是标/相轴首字")
        self.assertFalse(set(e._HAN_SCAL) - {""} & first(e.PHASES), "标位字不得是相轴首字")
        self.assertFalse(first(e.SCALS) & first(e.PHASES), "标轴首字不得是相轴首字")


class TestEncodeHan(unittest.TestCase):
    def test_roundtrip(self):
        for i in [0, 1, 2949119999, 2949120000, CAP_EXPECTED - 1] + _sample_ids(20260905, 3000):
            han = e.decode(i)["汉"]
            self.assertEqual(e.encode_han(han), i, f"编号 {i} 汉译往返失败: {han}")

    def test_malformed(self):
        self.assertEqual(e.encode_han("奥形凝起"), 0)
        for bad in ["", "奥", "奥形凝", "奥形凝起起", "奥形凝甲起", "甲形凝起", "奥形凝上上起",
                    "奥形凝起X", "Ao-cor-is·qi", "不是词", None, 123, [], {}]:
            self.assertEqual(e.encode_han(bad), -1, f"畸形汉译「{bad!r}」不该被判为合法")

    def test_same_word_two_forms_same_id(self):
        for i in _sample_ids(4444, 300):
            w = e.decode(i)
            self.assertEqual(e.encode_han(w["汉"]), e.encode(w["词"]))


class TestSearchCompose(unittest.TestCase):
    def test_search(self):
        self.assertEqual(e.search("毁灭"), [{"轴": "核", "下标": 120, "拉丁": "Nix", "汉": "尼", "义": "毁灭·重组·破局"}])
        self.assertEqual([h["轴"] for h in e.search("gal")], ["映", "标"])
        self.assertEqual([h["汉"] for h in e.search("GAL", "标")], ["时光"])
        self.assertEqual([f'{h["轴"]}:{h["拉丁"]}' for h in e.search("熵")], ["核:Ent", "映:flx", "标:flx"])
        self.assertEqual(e.search("光")[0]["拉丁"], "ryl")
        self.assertEqual(e.search("光")[0]["轴"], "映")
        for empty in ["", "   ", None, "绝不存在的词根"]:
            self.assertEqual(e.search(empty), [])

    def test_compose_equivalent_forms(self):
        a = e.compose({"核": "毁灭", "映": "光", "态": "爆", "标": "溯", "相": "起"})
        self.assertEqual(a["汉"], "尼光爆溯起")
        self.assertEqual(a["id"], 885744896)
        for spec in [{"核": "尼", "映": "光", "态": "爆", "标": "溯", "相": "起"},
                     {"核": "Nix", "映": "ryl", "态": "ex", "标": "rev", "相": "qi"},
                     {"c": 120, "m": 24, "s": 50, "k": 32, "p": 0},
                     {"核": "120", "映": "24", "态": "50", "标": "32", "相": "0"}]:
            self.assertEqual(e.compose(spec)["id"], a["id"], spec)
        self.assertEqual(e.compose({})["id"], 0)
        self.assertEqual(e.compose({"相": "映"})["id"], 7)
        self.assertEqual(e.compose({"核": "Aoa"})["汉"], "奥甲形凝起")
        self.assertEqual(e.compose({"核": "奥甲"})["坐标"]["c"], 1)

    def test_compose_rejects(self):
        for bad in [{"核": "绝不存在"}, {"核": 1040}, {"映": -1}, {"核": True}, {"天": 1}, {"核": {}}, None, "x"]:
            with self.assertRaises(ValueError, msg=f"compose({bad!r}) 应抛 ValueError"):
                e.compose(bad)

    def test_analogy_identity_and_inverse(self):
        origin = e.decode(0)
        self.assertEqual(e.analogy(origin["汉"], origin["汉"], origin["汉"])["id"], origin["id"])
        a, b, c = e.decode(120), e.decode(240), e.decode(7)
        d = e.analogy(a["词"], b["汉"], c["id"])
        self.assertEqual(e.analogy(b["汉"], a["词"], d["汉"])["id"], c["id"])
        with self.assertRaises(ValueError):
            e.analogy("绝不存在", origin["汉"], origin["汉"])

    def test_near_neighbors_are_l1_and_exclude_self(self):
        origin = e.near(0)
        self.assertEqual(len(origin), 5)
        self.assertTrue(all(item["距"] == 1 and item["id"] != 0 for item in origin))
        self.assertEqual([item["轴"] for item in origin], ["核", "映", "态", "标", "相"])
        mid = e.decode(888888888)
        neighbors = e.near(mid["汉"], 8)
        self.assertEqual(len(neighbors), 8)
        self.assertTrue(all(item["id"] != mid["id"] for item in neighbors))
        with self.assertRaises(ValueError):
            e.near("绝不存在")

    def test_pulse_breathes_one_axis_without_wrap(self):
        night = e.pulse(0, 1700000000)
        self.assertEqual(night["息"], "夜")
        self.assertEqual(night["时"], 22)
        self.assertEqual(night["分"], 13)
        self.assertEqual(night["轴"], "态")
        self.assertEqual(night["向"], 1)
        self.assertTrue(night["动"])
        self.assertEqual(night["种"]["id"], 0)
        self.assertNotEqual(night["id"], 0)
        edge = e.decode(CAP_EXPECTED - 1)
        stay = e.pulse(edge["汉"], 0)
        self.assertFalse(stay["动"])
        self.assertEqual(stay["id"], edge["id"])
        with self.assertRaises(ValueError):
            e.pulse(0, -1)
        with self.assertRaises(ValueError):
            e.pulse("绝不存在", 0)

    def test_trail_walks_without_wrap(self):
        walk = e.trail(0, 1700000000, 3)
        self.assertEqual(walk["步"], 3)
        self.assertEqual(len(walk["迹"]), 3)
        self.assertEqual(walk["种"]["id"], 0)
        self.assertEqual(walk["迹"][0]["id"], e.pulse(0, 1700000000)["id"])
        self.assertEqual(walk["迹"][1]["id"], e.pulse(walk["迹"][0]["id"], 1700000060)["id"])
        self.assertEqual(walk["id"], walk["迹"][2]["id"])
        edge = e.decode(CAP_EXPECTED - 1)
        stay = e.trail(edge["汉"], 0, 2)
        self.assertTrue(all(step["动"] is False for step in stay["迹"]))
        self.assertEqual(stay["id"], edge["id"])
        clipped = e.trail(0, 4102444800, 4)
        self.assertEqual(clipped["步"], 1)
        with self.assertRaises(ValueError):
            e.trail(0, 1700000000, 1)
        with self.assertRaises(ValueError):
            e.trail(0, -1, 3)

    def test_echo_rebounds_last_step_without_wrap(self):
        walk = e.trail(0, 1700000000, 3)
        rebound = e.echo(0, 1700000000, 3)
        self.assertEqual(rebound["步"], 3)
        self.assertEqual(len(rebound["迹"]), 3)
        self.assertEqual(rebound["种"]["id"], 0)
        self.assertEqual(rebound["轴"], walk["迹"][2]["轴"])
        self.assertEqual(rebound["向"], -walk["迹"][2]["向"])
        self.assertTrue(rebound["回"])
        self.assertNotEqual(rebound["id"], walk["id"])
        edge = e.decode(CAP_EXPECTED - 1)
        stay = e.echo(edge["汉"], 0, 2)
        self.assertTrue(stay["回"])
        self.assertNotEqual(stay["id"], edge["id"])
        with self.assertRaises(ValueError):
            e.echo(0, 1700000000, 1)
        with self.assertRaises(ValueError):
            e.echo(0, -1, 3)

    def test_sway_oscillates_without_wrap(self):
        rest = e.echo(0, 1700000000, 3)
        last = rest["迹"][-1]
        lean = e.sway(0, 1700000000, 3)
        self.assertTrue(lean["摇"])
        self.assertEqual(lean["侧"], 1)
        self.assertEqual(lean["id"], last["id"])
        self.assertEqual(lean["摆"]["id"], rest["id"])
        settled = e.sway(0, 1700000060, 3)
        self.assertTrue(settled["摇"])
        self.assertEqual(settled["侧"], 0)
        self.assertEqual(settled["id"], e.echo(0, 1700000060, 3)["id"])
        edge = e.decode(CAP_EXPECTED - 1)
        stay = e.sway(edge["汉"], 0, 2)
        self.assertTrue(stay["摇"])
        self.assertEqual(stay["侧"], 0)
        with self.assertRaises(ValueError):
            e.sway(0, 1700000000, 1)
        with self.assertRaises(ValueError):
            e.sway(0, -1, 3)

    def test_land_settles_without_wrap(self):
        rest = e.echo(0, 0, 3)
        last = rest["迹"][-1]
        air = e.land(0, 0, 3)
        self.assertFalse(air["落"])
        self.assertEqual(air["侧"], 1)
        self.assertEqual(air["id"], last["id"])
        self.assertEqual(air["着"]["id"], rest["id"])
        down = e.land(0, 60, 3)
        self.assertTrue(down["落"])
        self.assertEqual(down["侧"], 0)
        self.assertEqual(down["id"], e.echo(0, 60, 3)["id"])
        edge = e.decode(CAP_EXPECTED - 1)
        stay_air = e.land(edge["汉"], 0, 2)
        self.assertFalse(stay_air["落"])
        self.assertEqual(stay_air["侧"], 1)
        stay_down = e.land(edge["汉"], 60, 2)
        self.assertTrue(stay_down["落"])
        self.assertEqual(stay_down["侧"], 0)
        with self.assertRaises(ValueError):
            e.land(0, 1700000000, 1)
        with self.assertRaises(ValueError):
            e.land(0, -1, 3)

    def test_stir_rises_without_wrap(self):
        air = e.stir(0, 0, 3)
        down = e.land(0, 60, 3)
        neighbors = e.near(down["id"], 16)
        rose = e.stir(0, 60, 3)
        self.assertFalse(air["起"])
        self.assertEqual(air["id"], e.land(0, 0, 3)["id"])
        self.assertEqual(air["由"]["id"], air["id"])
        self.assertTrue(rose["起"])
        self.assertTrue(rose["落"])
        self.assertEqual(rose["由"]["id"], down["id"])
        self.assertEqual(rose["id"], neighbors[(60 // 480) % len(neighbors)]["id"])
        self.assertNotEqual(rose["id"], down["id"])
        edge = e.decode(CAP_EXPECTED - 1)
        stay_air = e.stir(edge["汉"], 0, 2)
        self.assertFalse(stay_air["起"])
        stay_down = e.stir(edge["汉"], 60, 2)
        self.assertTrue(stay_down["起"])
        self.assertNotEqual(stay_down["id"], e.land(edge["汉"], 60, 2)["id"])
        with self.assertRaises(ValueError):
            e.stir(0, 1700000000, 1)
        with self.assertRaises(ValueError):
            e.stir(0, -1, 3)


class TestCoinFamily(unittest.TestCase):
    def test_auto_coin_deterministic_and_known_values(self):
        self.assertEqual(e.auto_coin("神枢")["id"], 780009883)   # 与 JS autoCoin('神枢') 同值
        self.assertEqual(e.auto_coin("神枢"), e.auto_coin("神枢"))
        self.assertLess(e.auto_coin("").get("id"), 2 ** 32)  # uint32 上限（已知限制，与 JS 同）

    def test_coin_from_coord_clamp(self):
        self.assertEqual(e.coin_from_coord({"c": 0, "m": 0, "s": 0, "k": 0, "p": 0})["id"], 0)
        self.assertEqual(e.coin_from_coord({"c": -5, "m": 99999, "s": -1, "k": 99999, "p": 99999})["坐标"],
                         {"c": 0, "m": 179, "s": 0, "k": 63, "p": 7})
        self.assertEqual(e.coin_from_coord({})["id"], 0)
        self.assertEqual(e.coin_from_coord({"c": 3.7})["坐标"]["c"], 3)

    def test_coin_word_layer(self):
        import random
        rng = random.Random(1)
        for _ in range(20):
            self.assertEqual(e.coin_word("毁灭", rng)["层"], "毁灭")
        w = e.coin_word("不存在的层", random.Random(2))
        self.assertTrue(0 <= w["id"] < CAP_EXPECTED)

    def test_coin_from_state_layers(self):
        cases = [({"心绪": 0.9}, "情感"), ({"心绪": 0.1}, "熵"), ({"miss_you": 0.9, "心绪": 0.1}, "映"),
                 ({"心绪": 0.5}, "枢"), ({}, "枢"), (None, "枢")]
        for soul, layer in cases:
            w = e.coin_from_state(soul, 7)
            self.assertEqual(w["层意图"], layer)
            self.assertEqual(w["id"], e.auto_coin(f"7|{layer}")["id"])
        self.assertEqual(e.coin_from_state({"心绪": 0.9})["层"], "情感")


class TestCLI(unittest.TestCase):
    """CLI 子进程测试：命令行是权哥直接摸得到的界面，不许假"""

    @classmethod
    def run_cli(cls, *args):
        import subprocess
        root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        p = subprocess.run([sys.executable, os.path.join(root, "shuyu_engine.py"), *args],
                           capture_output=True, text=True, encoding="utf-8")
        return p.returncode, p.stdout

    def _json_tail(self, out):
        import json
        return json.loads(out.split("\n", 1)[1])

    def test_count(self):
        rc, out = self.run_cli("--count")
        self.assertEqual(rc, 0)
        self.assertIn("7,667,712,000", out)

    def test_id_word_han(self):
        rc, out = self.run_cli("--id", "888888888")
        self.assertEqual(self._json_tail(out)["汉"], "尼异朱极一外起")
        rc, out = self.run_cli("--word", "Nix-teks-ia1-h·qi")
        self.assertEqual(self._json_tail(out)["id"], 888888888)
        rc, out = self.run_cli("--han", "尼异朱极一外起")
        self.assertEqual(self._json_tail(out)["id"], 888888888)
        rc, out = self.run_cli("--han", "不是词")
        self.assertEqual(self._json_tail(out), {"han": "不是词", "id": -1, "verify": None})

    def test_search_compose_coin(self):
        rc, out = self.run_cli("--search", "毁灭")
        self.assertEqual(self._json_tail(out)["hits"][0]["拉丁"], "Nix")
        rc, out = self.run_cli("--compose", "核=毁灭,映=光,态=爆,标=溯,相=起")
        self.assertEqual(rc, 0)
        self.assertEqual(self._json_tail(out)["汉"], "尼光爆溯起")
        rc, out = self.run_cli("--compose", "核=绝不存在")
        self.assertEqual(rc, 2)
        self.assertIn("核轴找不到", out)
        rc, out = self.run_cli("--coin", "神枢")
        self.assertEqual(self._json_tail(out)["id"], 780009883)
        rc, out = self.run_cli("--pulse", "0", "--at", "1700000000")
        self.assertEqual(rc, 0)
        self.assertEqual(self._json_tail(out)["息"], "夜")
        self.assertEqual(self._json_tail(out)["轴"], "态")
        rc, out = self.run_cli("--trail", "0", "--at", "1700000000", "--n", "3")
        self.assertEqual(rc, 0)
        self.assertEqual(self._json_tail(out)["步"], 3)
        self.assertEqual(len(self._json_tail(out)["迹"]), 3)
        rc, out = self.run_cli("--echo", "0", "--at", "1700000000", "--n", "3")
        self.assertEqual(rc, 0)
        self.assertTrue(self._json_tail(out)["回"])
        self.assertEqual(self._json_tail(out)["步"], 3)
        rc, out = self.run_cli("--sway", "0", "--at", "1700000000", "--n", "3")
        self.assertEqual(rc, 0)
        self.assertTrue(self._json_tail(out)["摇"])
        self.assertEqual(self._json_tail(out)["侧"], 1)
        rc, out = self.run_cli("--land", "0", "--at", "0", "--n", "3")
        self.assertEqual(rc, 0)
        self.assertFalse(self._json_tail(out)["落"])
        self.assertEqual(self._json_tail(out)["侧"], 1)
