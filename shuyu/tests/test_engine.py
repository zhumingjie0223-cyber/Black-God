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
