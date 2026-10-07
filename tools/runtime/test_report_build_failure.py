"""验证公开诊断不泄漏自由文本，并执行真实流程脚本的退出状态边界。"""
from pathlib import Path
import os
import re
import subprocess
import tempfile
import textwrap
import unittest

from report_build_failure import ROOT, locked_file_names, summarize


class PublicFailureReportTests(unittest.TestCase):
    def test_nested_download_error_keeps_cause_and_locked_file(self):
        file_name = sorted(locked_file_names())[0]
        log = ("锁定下载失败：" + file_name + "；HTTP 404\n"
               "urllib.error.HTTPError: HTTP Error 404: Not Found\n"
               "subprocess.CalledProcessError: Command secret failed.\n")
        report = summarize(log, 2, locked_file_names())
        self.assertIn("HTTP=404", report)
        self.assertIn("文件=" + file_name, report)
        self.assertIn("脚本=prepare_image.py", report)
        self.assertNotIn("secret", report)

    def test_free_text_urls_environment_and_unknown_files_stay_private(self):
        secret = "test-secret-that-must-stay-private"
        log = (f"代理=https://user:{secret}@example.com/?token={secret}\n"
               f"锁定下载失败：{secret}.apk；HTTP 403\n"
               f"RuntimeError: {secret} %0A::error::injected\n")
        report = summarize(log, 2, locked_file_names())
        self.assertIn("HTTP=403", report)
        for forbidden in [secret, "https", "token", "%0A", "injected", "文件="]:
            self.assertNotIn(forbidden, report)

    def test_unknown_error_does_not_quote_tail(self):
        report = summarize("build failed with test-secret-and-private-host", 7, set())
        self.assertIn("类别=未知生成错误", report)
        self.assertNotIn("test-secret", report)
        self.assertNotIn("private-host", report)

    def test_known_missing_tool_is_reported_without_path(self):
        report = summarize('File "/private/user/tools/runtime/build.py", line 17\n'
                           "FileNotFoundError: [Errno 2] missing '/private/token/xcrun'\n", 2, set())
        self.assertIn("脚本=build.py", report)
        self.assertIn("工具=xcrun", report)
        self.assertNotIn("private", report)
        self.assertNotIn("token", report)

    def test_checksum_error_does_not_quote_file_or_secret(self):
        report = summarize("ValueError: Cached checksum mismatch: test-secret\n", 2, set())
        self.assertIn("类别=缓存校验失败", report)
        self.assertNotIn("test-secret", report)

    def test_zero_exit_emits_no_error_even_with_error_words(self):
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / "generation.log"
            log.write_text("HTTP Error 404 was a previous example\n")
            result = subprocess.run(["python3", str(ROOT / "tools/runtime/report_build_failure.py"), str(log), "0"],
                                    capture_output=True, text=True, check=True)
            self.assertEqual(result.stdout, "")


class GenerationStepExitTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        workflow = (ROOT / ".github/workflows/build.yml").read_text()
        match = re.search(r"(?m)^    - name: 生成工程与运行镜像\n      run: \|\n((?:        [^\n]*\n|[ \t]*\n)+)", workflow)
        if not match:
            raise AssertionError("找不到实际生成流程脚本")
        cls.script = textwrap.dedent(match[1])

    def execute_step(self, make_code, capture_fails=False, diagnostic_fails=False):
        with tempfile.TemporaryDirectory(prefix="black-god-generation-test-") as directory:
            scratch = Path(directory)
            binaries = scratch / "bin"
            binaries.mkdir()
            make = binaries / "make"
            make.write_text("#!/usr/bin/env bash\nprintf '%s\\n' 'unknown build error test-secret'\nexit " + str(make_code) + "\n")
            make.chmod(0o755)
            if diagnostic_fails:
                python = binaries / "python3"
                python.write_text("#!/usr/bin/env bash\nexit 29\n")
                python.chmod(0o755)
            env = dict(os.environ)
            env["PATH"] = str(binaries) + os.pathsep + env["PATH"]
            env["RUNNER_TEMP"] = str(scratch / "missing-directory") if capture_fails else str(scratch)
            result = subprocess.run(["bash", "-c", self.script], cwd=ROOT, env=env,
                                    capture_output=True, text=True, timeout=10)
            annotations = [line for line in result.stdout.splitlines() if line.startswith("::error")]
            self.assertTrue(all("test-secret" not in line for line in annotations))
            return result.returncode, annotations

    def test_success_has_no_failure_annotation(self):
        status, annotations = self.execute_step(0)
        self.assertEqual(status, 0)
        self.assertEqual(annotations, [])

    def test_make_failure_preserves_actual_exit(self):
        status, annotations = self.execute_step(7)
        self.assertEqual(status, 7)
        self.assertEqual(len(annotations), 1)

    def test_failed_log_capture_cannot_report_success(self):
        status, annotations = self.execute_step(0, capture_fails=True)
        self.assertNotEqual(status, 0)
        self.assertEqual(len(annotations), 1)

    def test_make_failure_wins_over_log_capture_failure(self):
        status, _ = self.execute_step(7, capture_fails=True)
        self.assertEqual(status, 7)

    def test_diagnostic_failure_does_not_mask_make_failure(self):
        status, _ = self.execute_step(7, diagnostic_fails=True)
        self.assertEqual(status, 7)


if __name__ == "__main__":
    unittest.main()
