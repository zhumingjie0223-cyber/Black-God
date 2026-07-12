# router.py(v1 分档路由)纯逻辑单元测试
# minis CLI 调用全部打桩,不依赖真实网关。
# 跑法: cd server/shenshu && python3 -m unittest test_router -v
import unittest
from unittest import mock

import router
import router_v2
from router import (
    Complexity,
    EMERGENCY_FALLBACK,
    ROUTING_TABLE,
    apply_route_to_session,
    build_advisors_for,
    get_route,
    route_task,
    score_complexity,
    _write_session_model,
)


class TestScoreComplexity(unittest.TestCase):
    def test_keyword_priority_high_over_low(self):
        # 同时含"架构设计"(MAX)与"改一下"(LOW),高档优先
        self.assertEqual(score_complexity("帮我改一下这个架构设计"), Complexity.MAX)

    def test_keyword_hits(self):
        # "修个错字"含 LOW 词"修个"与 TRIVIAL 词"错字",按"宁高不低"命中更高的 LOW
        self.assertEqual(score_complexity("修个错字"), Complexity.LOW)
        self.assertEqual(score_complexity("格式化代码"), Complexity.TRIVIAL)  # 纯 TRIVIAL
        self.assertEqual(score_complexity("重构并发逻辑"), Complexity.HIGH)

    def test_heuristic_by_steps_files(self):
        self.assertEqual(score_complexity("做点事", estimated_steps=8), Complexity.MAX)
        self.assertEqual(score_complexity("做点事", file_count=3), Complexity.HIGH)
        self.assertEqual(score_complexity("做点事", estimated_steps=2), Complexity.MEDIUM)
        self.assertEqual(score_complexity("做点事", estimated_steps=1, file_count=1), Complexity.LOW)

    def test_empty_text_does_not_crash(self):
        """空描述/None 不再 .lower() 崩溃,退回启发式。"""
        self.assertEqual(score_complexity("", estimated_steps=8), Complexity.MAX)
        self.assertEqual(score_complexity(None, estimated_steps=1, file_count=1), Complexity.LOW)
        # 纯空白 + 默认 steps=1/files=1 → 启发式落 LOW
        self.assertEqual(score_complexity("   "), Complexity.LOW)


class TestGetRoute(unittest.TestCase):
    def test_all_tiers_mapped(self):
        for c in Complexity:
            self.assertIs(get_route(c), ROUTING_TABLE[c])


class TestWriteSessionModel(unittest.TestCase):
    def test_success(self):
        ok = mock.Mock(returncode=0, stdout='{"ok": true}', stderr="")
        with mock.patch.object(router.subprocess, "run", return_value=ok):
            success, err = _write_session_model("session.primaryModel", "e-1")
        self.assertTrue(success)
        self.assertIsNone(err)

    def test_nonzero_returncode_is_failure(self):
        """returncode 非零即失败,即便 stdout 恰好像成功(原实现的漏判)。"""
        bad = mock.Mock(returncode=1, stdout='{"ok": true}', stderr="boom")
        with mock.patch.object(router.subprocess, "run", return_value=bad):
            success, err = _write_session_model("session.primaryModel", "e-1")
        self.assertFalse(success)
        self.assertIn("boom", err)

    def test_non_json_output_is_failure(self):
        weird = mock.Mock(returncode=0, stdout="not json", stderr="")
        with mock.patch.object(router.subprocess, "run", return_value=weird):
            success, err = _write_session_model("session.subModel", "e-2")
        self.assertFalse(success)
        self.assertIn("非JSON", err)

    def test_timeout(self):
        import subprocess as sp
        with mock.patch.object(router.subprocess, "run",
                               side_effect=sp.TimeoutExpired("minis-config", 35)):
            success, err = _write_session_model("session.subModel", "e-3")
        self.assertFalse(success)
        self.assertIn("超时", err)


class TestApplyRouteToSession(unittest.TestCase):
    def setUp(self):
        router_v2._MODEL_ENTRY_CACHE.clear()

    def test_happy_path(self):
        route = ROUTING_TABLE[Complexity.MEDIUM]
        with mock.patch.object(router, "_resolve_entry_id", side_effect=["e-p", "e-s"]), \
             mock.patch.object(router, "_write_session_model", return_value=(True, None)) as w:
            res = apply_route_to_session(route)
        self.assertTrue(res["applied"])
        self.assertTrue(res["primary_write"] and res["sub_write"])
        # 两次写入分别落在 primaryModel / subModel 键上
        keys = [c.args[0] for c in w.call_args_list]
        self.assertEqual(keys, ["session.primaryModel", "session.subModel"])

    def test_missing_model_triggers_emergency_fallback(self):
        """核心接线测试:模型解析不到 → 自动降级到 EMERGENCY_FALLBACK 再试。"""
        route = ROUTING_TABLE[Complexity.HIGH]

        def resolve(provider, model):
            # 原路由 Primary 解析失败;兜底路由两个都成功
            if provider == EMERGENCY_FALLBACK.primary_provider:
                return "fb-p"
            if provider == EMERGENCY_FALLBACK.sub_provider:
                return "fb-s"
            return None  # 原路由解析不到

        with mock.patch.object(router, "_resolve_entry_id", side_effect=resolve), \
             mock.patch.object(router, "_write_session_model", return_value=(True, None)):
            res = apply_route_to_session(route)
        self.assertTrue(res.get("fell_back_to_emergency"))
        self.assertIn("解析失败", res["fallback_reason"])
        self.assertEqual(res["route_label"], EMERGENCY_FALLBACK.label)
        self.assertTrue(res["applied"])

    def test_fallback_itself_fails_no_infinite_recursion(self):
        """兜底路由自己也解析不到时,如实报错,绝不无限递归。"""
        route = ROUTING_TABLE[Complexity.MAX]
        resolver = mock.Mock(return_value=None)  # 全世界模型都解析不到
        with mock.patch.object(router, "_resolve_entry_id", resolver), \
             mock.patch.object(router, "_write_session_model", return_value=(True, None)):
            res = apply_route_to_session(route)
        self.assertFalse(res["applied"])
        self.assertIn("找不到模型", res["error"])
        # 试过兜底(标记在)但兜底也没成(applied=False)——这两条信息组合才完整
        self.assertTrue(res.get("fell_back_to_emergency"))
        # 递归有界的硬证明:只两层(外层 primary+sub 2 次 + 兜底层 2 次),共 4 次解析
        self.assertEqual(resolver.call_count, 4)


class TestBuildAdvisors(unittest.TestCase):
    def test_max_gets_two_lower_tiers(self):
        advisors = build_advisors_for(Complexity.MAX)
        self.assertEqual(len(advisors), 2)  # HIGH + MEDIUM
        providers = {a.provider for a in advisors}
        self.assertIn(ROUTING_TABLE[Complexity.HIGH].primary_provider, providers)

    def test_trivial_never_empty(self):
        # 最低档没有更低档可取,兜到至少一个,不能返回空团
        self.assertGreaterEqual(len(build_advisors_for(Complexity.TRIVIAL)), 1)


class TestRouteTaskIntegration(unittest.TestCase):
    def test_blocked_command_skips_all_writes(self):
        """高危命令拦截:一次模型解析、一次配置写入都不许发生。"""
        with mock.patch.object(router, "_resolve_entry_id") as r, \
             mock.patch.object(router, "_write_session_model") as w, \
             mock.patch.object(router, "run_advisory_panel") as panel:
            res = route_task("清理环境", command="rm -rf /", target_path="/")
        self.assertTrue(res["blocked"])
        r.assert_not_called()
        w.assert_not_called()
        panel.assert_not_called()

    def test_safe_command_proceeds_to_route(self):
        with mock.patch.object(router, "_resolve_entry_id", return_value="e"), \
             mock.patch.object(router, "_write_session_model", return_value=(True, None)):
            res = route_task("跑个 ls", command="ls -la", advisory=False)
        self.assertNotIn("blocked", res)
        self.assertTrue(res["route"]["applied"])

    def test_history_summary_wrapped(self):
        with mock.patch.object(router, "_resolve_entry_id", return_value="e"), \
             mock.patch.object(router, "_write_session_model", return_value=(True, None)):
            res = route_task("继续", history_summary="旧任务:清日志", advisory=False)
        self.assertIn("context", res)
        self.assertTrue(router_v2.is_compacted_summary(res["context"]))

    def test_advisory_auto_on_for_high(self):
        fake_panel = [router_v2.AdvisoryResult(
            slot=router_v2.AdvisorSlot("P", "m"), output_text="意见", ok=True)]
        with mock.patch.object(router, "_resolve_entry_id", return_value="e"), \
             mock.patch.object(router, "_write_session_model", return_value=(True, None)), \
             mock.patch.object(router, "run_advisory_panel", return_value=fake_panel) as panel, \
             mock.patch.object(router, "aggregate_advisory",
                               return_value={"final_ok": True}) as agg:
            route_task("重构整个并发模块", estimated_steps=6, file_count=4)
            panel.assert_called_once()
            agg.assert_called_once()

    def test_advisory_off_for_low(self):
        with mock.patch.object(router, "_resolve_entry_id", return_value="e"), \
             mock.patch.object(router, "_write_session_model", return_value=(True, None)), \
             mock.patch.object(router, "run_advisory_panel") as panel:
            route_task("修个错字")
            panel.assert_not_called()


if __name__ == "__main__":
    unittest.main()
