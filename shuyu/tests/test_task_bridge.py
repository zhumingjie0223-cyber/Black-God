import unittest
from task_bridge import compile_task, describe_plan, primes
class TaskBridgeTests(unittest.TestCase):
    def test_chinese_and_legacy_aliases(self):
        self.assertEqual(compile_task('行：计算("12*3") → "36"'),compile_task('do: calc("12*3") → "36"'))
    def test_escaped_quotes_and_arrows_are_data(self):
        action=compile_task('行：执行("printf \\\"a,b)→c\\\"")')['actions'][0]
        self.assertEqual(action['arguments']['command'],'printf "a,b)→c"')
        self.assertEqual(action['arguments']['timeout'],'10')
    def test_refuses_partial_program_unknown_and_excess(self):
        for source in ['', '行：计算(1)', '行：未知("x")', '行：计算("1")\n无效', '\n'.join(['行：计算("1")']*9), '行：计算("1") → true']:
            with self.subTest(source=source), self.assertRaises(ValueError): compile_task(source)

    def test_primes_boundary_and_exact_results(self):
        self.assertEqual(primes('0'),[])
        self.assertEqual(primes('20'),[2,3,5,7,11,13,17,19])
        for value in ['10001','-1','1.5',True]:
            with self.assertRaises(ValueError): primes(value)

    def test_plan_search_and_eight_steps(self):
        program=compile_task('行：规划("拆目标")\n行：检索("锚点")\n行：核对("可检查")')
        self.assertEqual(program['version'],2)
        self.assertEqual(program['actions'][0]['id'],'s1')
        self.assertEqual(program['actions'][1]['arguments'],{'operation':'检索','input':'锚点'})
        self.assertEqual(describe_plan(program)[0]['title'],'拆目标')
        eight='\n'.join(f'行：计算("{i}")' for i in range(8))
        self.assertEqual(len(compile_task(eight)['actions']),8)
        with self.assertRaises(ValueError):
            compile_task(eight+'\n行：计算("8")')

    def test_near_and_clock_compile(self):
        program=compile_task('行：邻近("奥形凝起")\n行：时间("Asia/Shanghai")')
        self.assertEqual(program['actions'][0]['arguments'],{'operation':'邻近','input':'奥形凝起'})
        self.assertEqual(program['actions'][1]['tool'],'clock')
        self.assertEqual(describe_plan(program)[1]['title'],'Asia/Shanghai')
