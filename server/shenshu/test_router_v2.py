# router_v2 纯逻辑单元测试(不依赖 minis CLI,模型调用全部打桩)
# 跑法: cd server/shenshu && python3 -m unittest test_router_v2 -v
import os
import tempfile
import unittest
from unittest import mock

import router_v2 as rv2
from router_v2 import (
    AdvisorSlot,
    AdvisoryResult,
    RiskLevel,
    aggregate_advisory,
    assess_command_risk,
    evaluate_destructive_action,
    is_compacted_summary,
    run_advisory_panel,
    sandbox_probe,
    wrap_compacted_summary,
)


class TestAssessCommandRisk(unittest.TestCase):
    def test_rm_root_variants_are_critical(self):
        """删根的各种旗标写法都必须判 CRITICAL。"""
        for cmd in ["rm -rf /", "rm -fr /", "rm -r -f /", "rm -f -r /",
                    "rm --recursive --force /", "rm -rf //", "rm -rf /*",
                    "rm -rf / --no-preserve-root"]:
            self.assertEqual(assess_command_risk(cmd).level, RiskLevel.CRITICAL, cmd)

    def test_rm_subpath_is_not_critical(self):
        """删子路径不是删根:HIGH 而非 CRITICAL(原正则的核心诉求,不能回归)。"""
        r = assess_command_risk("rm -rf /tmp/build_cache")
        self.assertEqual(r.level, RiskLevel.HIGH)

    def test_force_push_variants(self):
        self.assertEqual(assess_command_risk("git push --force").level, RiskLevel.CRITICAL)
        self.assertEqual(assess_command_risk("git push origin main --force").level,
                         RiskLevel.CRITICAL)  # 带远程/分支的 --force,原正则漏掉的写法
        self.assertEqual(assess_command_risk("git push -f").level, RiskLevel.CRITICAL)
        self.assertEqual(assess_command_risk("git push origin main -f").level, RiskLevel.CRITICAL)
        # --force-with-lease 是安全写法,不得误伤(会落到 MEDIUM 的 "git push" 子串)
        self.assertEqual(assess_command_risk("git push --force-with-lease").level,
                         RiskLevel.MEDIUM)

    def test_sql_case_insensitive(self):
        self.assertEqual(assess_command_risk("DROP TABLE users;").level, RiskLevel.CRITICAL)
        self.assertEqual(assess_command_risk("Truncate Table logs").level, RiskLevel.CRITICAL)

    def test_fork_bomb(self):
        self.assertEqual(assess_command_risk(":(){ :|:& };:").level, RiskLevel.CRITICAL)

    def test_medium_no_confirmation(self):
        r = assess_command_risk("git commit -m 'x'")
        self.assertEqual(r.level, RiskLevel.MEDIUM)
        self.assertFalse(r.requires_confirmation)

    def test_empty_command_is_low(self):
        """空命令/纯空白不再崩溃,判 LOW。"""
        for cmd in ["", "   "]:
            r = assess_command_risk(cmd)
            self.assertEqual(r.level, RiskLevel.LOW)

    def test_normal_command_is_low(self):
        self.assertEqual(assess_command_risk("ls -la && cat a.txt").level, RiskLevel.LOW)


class TestSandboxProbe(unittest.TestCase):
    def test_empty_dir(self):
        with tempfile.TemporaryDirectory() as d:
            p = sandbox_probe(d)
            self.assertTrue(p["probe_ok"] and p["exists"] and p["is_dir"] and p["is_empty"])

    def test_nonempty_dir(self):
        with tempfile.TemporaryDirectory() as d:
            open(os.path.join(d, "x"), "w").close()
            self.assertFalse(sandbox_probe(d)["is_empty"])

    def test_file_and_missing(self):
        with tempfile.NamedTemporaryFile(delete=False) as f:
            path = f.name
        try:
            p = sandbox_probe(path)
            self.assertTrue(p["exists"] and not p["is_dir"] and p["is_empty"])
        finally:
            os.unlink(path)
        p2 = sandbox_probe("/nonexistent/deeply/missing")
        self.assertTrue(p2["probe_ok"])
        self.assertFalse(p2["exists"])

    def test_symlink_flagged(self):
        with tempfile.TemporaryDirectory() as d:
            real = os.path.join(d, "real")
            os.makedirs(real)
            link = os.path.join(d, "link")
            os.symlink(real, link)
            self.assertTrue(sandbox_probe(link)["is_symlink"])

    def test_empty_path_fails_probe(self):
        p = sandbox_probe("")
        self.assertFalse(p["probe_ok"])


class TestEvaluateDestructiveAction(unittest.TestCase):
    def test_critical_never_downgrades(self):
        """安全洞回归测试:rm -rf / 即使'目标为空'也绝不降级、绝不豁免确认。"""
        with tempfile.TemporaryDirectory() as d:
            r = evaluate_destructive_action("rm -rf /", target_path=d)
            self.assertEqual(r["risk_level"], RiskLevel.CRITICAL.value)
            self.assertTrue(r["requires_confirmation"])

    def test_high_with_empty_target_downgrades(self):
        with tempfile.TemporaryDirectory() as d:
            r = evaluate_destructive_action(f"rm -rf {d}", target_path=d)
            self.assertEqual(r["risk_level"], RiskLevel.MEDIUM.value)
            self.assertFalse(r["requires_confirmation"])

    def test_high_with_nonempty_target_stays_high(self):
        with tempfile.TemporaryDirectory() as d:
            open(os.path.join(d, "data"), "w").close()
            r = evaluate_destructive_action(f"rm -rf {d}", target_path=d)
            self.assertEqual(r["risk_level"], RiskLevel.HIGH.value)
            self.assertTrue(r["requires_confirmation"])

    def test_symlink_target_never_downgrades(self):
        """符号链接指向空目录也不降级——链接判空看的不是真身全貌。"""
        with tempfile.TemporaryDirectory() as d:
            real = os.path.join(d, "real")
            os.makedirs(real)
            link = os.path.join(d, "link")
            os.symlink(real, link)
            r = evaluate_destructive_action(f"rm -rf {link}", target_path=link)
            self.assertEqual(r["risk_level"], RiskLevel.HIGH.value)
            self.assertTrue(r["requires_confirmation"])

    def test_low_risk_skips_probe(self):
        r = evaluate_destructive_action("ls", target_path="/tmp")
        self.assertNotIn("probe", r)


class TestAdvisoryPanel(unittest.TestCase):
    def test_empty_advisors_returns_empty(self):
        """空顾问名单直接返回(原实现线程池 max_workers=0 会抛 ValueError)。"""
        self.assertEqual(run_advisory_panel("问题", []), [])

    def test_panel_collects_all_results(self):
        slots = [AdvisorSlot("P1", "m1"), AdvisorSlot("P2", "m2")]
        fake = lambda p, m, s, u, timeout=90: AdvisoryResult(
            slot=AdvisorSlot(p, m), output_text=f"{m}的意见", ok=True)
        with mock.patch.object(rv2, "call_model", side_effect=fake):
            results = run_advisory_panel("问题", slots)
        self.assertEqual(len(results), 2)
        self.assertTrue(all(r.ok for r in results))

    def test_panel_timeout_records_absentees(self):
        """总超时不抛异常:快顾问的结果保留,慢顾问记缺席。"""
        import time as _t

        def slow_then_fast(p, m, s, u, timeout=90):
            if m == "slow":
                _t.sleep(3)
            return AdvisoryResult(slot=AdvisorSlot(p, m), output_text="ok", ok=True)

        slots = [AdvisorSlot("P", "fast"), AdvisorSlot("P", "slow")]
        with mock.patch.object(rv2, "call_model", side_effect=slow_then_fast):
            results = run_advisory_panel("问题", slots, panel_timeout=1.0)
        by_model = {r.slot.model: r for r in results}
        self.assertEqual(len(results), 2)
        self.assertTrue(by_model["fast"].ok)
        self.assertFalse(by_model["slow"].ok)
        self.assertIn("总超时", by_model["slow"].error)

    def test_aggregate_short_circuits_when_all_absent(self):
        """全员缺席必须短路:一次聚合模型调用都不许发出去。"""
        results = [AdvisoryResult(slot=AdvisorSlot("P", "m"), ok=False, error="挂了")]
        with mock.patch.object(rv2, "call_model") as cm:
            out = aggregate_advisory("问题", results, "AGG", "agg-model")
            cm.assert_not_called()
        self.assertFalse(out["final_ok"])
        self.assertEqual(out["advisors_succeeded"], 0)

    def test_aggregate_normal_path(self):
        results = [
            AdvisoryResult(slot=AdvisorSlot("P1", "m1"), output_text="意见A", ok=True),
            AdvisoryResult(slot=AdvisorSlot("P2", "m2"), ok=False, error="缺席"),
        ]
        fake_final = AdvisoryResult(slot=AdvisorSlot("AGG", "agg"),
                                    output_text="最终结论", ok=True)
        with mock.patch.object(rv2, "call_model", return_value=fake_final) as cm:
            out = aggregate_advisory("问题", results, "AGG", "agg-model")
            cm.assert_called_once()
            prompt = cm.call_args.args[3]
            self.assertIn("意见A", prompt)   # 成功意见进聚合提示词
            self.assertIn("缺席", prompt)    # 缺席信息也如实呈报
        self.assertTrue(out["final_ok"])
        self.assertEqual(out["final_decision"], "最终结论")
        self.assertEqual(out["advisors_succeeded"], 1)


class TestCompactionGuard(unittest.TestCase):
    def test_wrap_and_detect(self):
        w = wrap_compacted_summary("旧任务:部署了网关,待办:清日志")
        self.assertTrue(is_compacted_summary(w))
        self.assertIn("旧任务:部署了网关", w)
        self.assertTrue(w.endswith(rv2.COMPACTION_GUARD_SUFFIX))

    def test_wrap_is_idempotent(self):
        """重复包裹必须是幂等的,不许叠出嵌套标记。"""
        w1 = wrap_compacted_summary("摘要内容")
        w2 = wrap_compacted_summary(w1)
        self.assertEqual(w1, w2)

    def test_empty_summary_returns_empty(self):
        self.assertEqual(wrap_compacted_summary(""), "")
        self.assertEqual(wrap_compacted_summary("   "), "")

    def test_is_compacted_none_safe(self):
        self.assertFalse(is_compacted_summary(None))
        self.assertFalse(is_compacted_summary(""))
        self.assertFalse(is_compacted_summary("普通文本"))


class TestResolveEntryIdCache(unittest.TestCase):
    def test_failure_not_cached(self):
        """解析失败不得写缓存毒化后续调用。"""
        rv2._MODEL_ENTRY_CACHE.clear()
        fail = mock.Mock(returncode=1, stdout="", stderr="boom")
        with mock.patch.object(rv2.subprocess, "run", return_value=fail):
            self.assertIsNone(rv2._resolve_entry_id("P", "m"))
        self.assertEqual(rv2._MODEL_ENTRY_CACHE, {})

    def test_success_cached_and_reused(self):
        rv2._MODEL_ENTRY_CACHE.clear()
        payload = ('{"value": "[{\\"provider_label\\": \\"P\\", '
                   '\\"model_id\\": \\"m\\", \\"entry_id\\": \\"e-1\\"}]"}')
        ok = mock.Mock(returncode=0, stdout=payload, stderr="")
        with mock.patch.object(rv2.subprocess, "run", return_value=ok) as sp:
            self.assertEqual(rv2._resolve_entry_id("P", "m"), "e-1")
            self.assertEqual(rv2._resolve_entry_id("P", "m"), "e-1")
            sp.assert_called_once()  # 第二次命中缓存,不再起子进程


if __name__ == "__main__":
    unittest.main()
