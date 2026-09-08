import unittest
from task_bridge import compile_task, primes
class TaskBridgeTests(unittest.TestCase):
    def test_chinese_and_legacy_aliases(self):
        self.assertEqual(compile_task('行：计算("12*3") → "36"'),compile_task('do: calc("12*3") → "36"'))
    def test_escaped_quotes_and_arrows_are_data(self):
        action=compile_task('行：执行("printf \\\"a,b)→c\\\"")')['actions'][0]
        self.assertEqual(action['arguments']['command'],'printf "a,b)→c"')
        self.assertEqual(action['arguments']['timeout'],'10')
    def test_refuses_partial_program_unknown_and_excess(self):
        for source in ['', '行：计算(1)', '行：未知("x")', '行：计算("1")\n无效', '\n'.join(['行：计算("1")']*5), '行：计算("1") → true']:
            with self.subTest(source=source), self.assertRaises(ValueError): compile_task(source)

    def test_primes_boundary_and_exact_results(self):
        self.assertEqual(primes('0'),[])
        self.assertEqual(primes('20'),[2,3,5,7,11,13,17,19])
        for value in ['10001','-1','1.5',True]:
            with self.assertRaises(ValueError): primes(value)
