"""枢语执行方言v2；与task_bridge.js同构。仅编译，不执行输入。"""
import json
import re
TASK_VERSION = 2
TASK_MAX_ACTIONS = 8
_MAPPING = {
    '计算': {'tool': 'calc', 'keys': ['expression']}, 'calc': {'tool': 'calc', 'keys': ['expression']},
    '枢语': {'tool': 'shuyu', 'keys': ['operation', 'input']}, 'shuyu': {'tool': 'shuyu', 'keys': ['operation', 'input']},
    '执行': {'tool': 'shell_execute', 'keys': ['command']}, 'shell': {'tool': 'shell_execute', 'keys': ['command']},
    '规划': {'tool': 'plan', 'keys': ['title']}, 'plan': {'tool': 'plan', 'keys': ['title']},
    '核对': {'tool': 'verify', 'keys': ['criterion']}, 'verify': {'tool': 'verify', 'keys': ['criterion']},
    '检索': {'tool': 'shuyu', 'keys': ['input'], 'preset': {'operation': '检索'}},
    'search': {'tool': 'shuyu', 'keys': ['input'], 'preset': {'operation': '检索'}},
    '邻近': {'tool': 'shuyu', 'keys': ['input'], 'preset': {'operation': '邻近'}},
    'near': {'tool': 'shuyu', 'keys': ['input'], 'preset': {'operation': '邻近'}},
    '时间': {'tool': 'clock', 'keys': ['timezone']}, 'clock': {'tool': 'clock', 'keys': ['timezone']},
    '一息': {'tool': 'shuyu', 'keys': ['input'], 'preset': {'operation': '一息'}},
    'pulse': {'tool': 'shuyu', 'keys': ['input'], 'preset': {'operation': '一息'}},
    '余息': {'tool': 'shuyu', 'keys': ['input'], 'preset': {'operation': '余息'}},
    'trail': {'tool': 'shuyu', 'keys': ['input'], 'preset': {'operation': '余息'}},
    '回息': {'tool': 'shuyu', 'keys': ['input'], 'preset': {'operation': '回息'}},
    'echo': {'tool': 'shuyu', 'keys': ['input'], 'preset': {'operation': '回息'}},
    '摇息': {'tool': 'shuyu', 'keys': ['input'], 'preset': {'operation': '摇息'}},
    'sway': {'tool': 'shuyu', 'keys': ['input'], 'preset': {'operation': '摇息'}},
    '落息': {'tool': 'shuyu', 'keys': ['input'], 'preset': {'operation': '落息'}},
    'land': {'tool': 'shuyu', 'keys': ['input'], 'preset': {'operation': '落息'}},
    '起息': {'tool': 'shuyu', 'keys': ['input'], 'preset': {'operation': '起息'}},
    'stir': {'tool': 'shuyu', 'keys': ['input'], 'preset': {'operation': '起息'}},
    '栖息': {'tool': 'shuyu', 'keys': ['input'], 'preset': {'operation': '栖息'}},
    'perch': {'tool': 'shuyu', 'keys': ['input'], 'preset': {'operation': '栖息'}},
    '转息': {'tool': 'shuyu', 'keys': ['input'], 'preset': {'operation': '转息'}},
    'turn': {'tool': 'shuyu', 'keys': ['input'], 'preset': {'operation': '转息'}},
    '顾息': {'tool': 'shuyu', 'keys': ['input'], 'preset': {'operation': '顾息'}},
    'gaze': {'tool': 'shuyu', 'keys': ['input'], 'preset': {'operation': '顾息'}},
    '倾息': {'tool': 'shuyu', 'keys': ['input'], 'preset': {'operation': '倾息'}},
    'incline': {'tool': 'shuyu', 'keys': ['input'], 'preset': {'operation': '倾息'}},
    '贴息': {'tool': 'shuyu', 'keys': ['input'], 'preset': {'operation': '贴息'}},
    'nestle': {'tool': 'shuyu', 'keys': ['input'], 'preset': {'operation': '贴息'}},
}
def compile_task(source):
    if not isinstance(source, str) or len(source.encode('utf-16-le')) // 2 > 8192:
        raise ValueError('枢语程序为空或超过8192字符')
    lines = [s.strip() for s in source.split('\n') if s.strip() and not s.strip().startswith('--')]
    if not 1 <= len(lines) <= TASK_MAX_ACTIONS:
        raise ValueError('每个枢语程序需要1至8条执行语句')
    actions = []
    for index, line in enumerate(lines):
        head = re.match(r'^(?:行[：:]|do:)\s*([^\s(]+)\(', line)
        if not head or head[1] not in _MAPPING:
            raise ValueError('不是已支持的执行语句')
        quoted, escaped, end = False, False, -1
        for i in range(head.end(), len(line)):
            c = line[i]
            if escaped:
                escaped = False
                continue
            if quoted and c == '\\':
                escaped = True
                continue
            if c == '"':
                quoted = not quoted
                continue
            if not quoted and c == ')':
                end = i
                break
        if end < 0 or quoted:
            raise ValueError('括号或字符串未闭合')
        args = json.loads('[' + line[head.end():end] + ']')
        spec = _MAPPING[head[1]]
        if len(args) != len(spec['keys']) or any(not isinstance(x, str) or not x.strip() or len(x.encode('utf-16-le')) // 2 > 4096 for x in args):
            raise ValueError('参数数量或类型错误')
        suffix = line[end + 1:].strip()
        expected = None
        if suffix:
            if not suffix.startswith('→'):
                raise ValueError('行末尾无效')
            expected = json.loads(suffix[1:].strip())
            if not isinstance(expected, str) or len(expected.encode('utf-16-le')) // 2 > 4096:
                raise ValueError('验收结果必须为有限长度字符串')
        arguments = dict(spec.get('preset') or {})
        arguments.update(zip(spec['keys'], args))
        if spec['tool'] == 'shell_execute':
            arguments['timeout'] = '10'
        actions.append(dict(id=f's{index + 1}', tool=spec['tool'], arguments=arguments, expected=expected))
    return dict(version=TASK_VERSION, actions=actions)

def describe_plan(program):
    if not isinstance(program, dict) or not isinstance(program.get('actions'), list):
        raise ValueError('不是已编译的枢语程序')
    out = []
    for action in program['actions']:
        args = action.get('arguments') or {}
        title = args.get('title') or args.get('criterion') or args.get('expression') or args.get('command') or args.get('input') or args.get('timezone') or action.get('tool')
        out.append(dict(id=action.get('id'), tool=action.get('tool'), title=title))
    return out

def primes(value):
    if not isinstance(value, str) or not re.fullmatch(r'[0-9]+', value) or int(value) > 10000:
        raise ValueError('质数范围必须为0至10000整数')
    n = int(value)
    if n < 2:
        return []
    marked = bytearray(n + 1)
    out = []
    for i in range(2, n + 1):
        if marked[i]:
            continue
        out.append(i)
        start = i * i
        if start > n:
            continue
        marked[start:n + 1:i] = b'\x01' * (((n - start) // i) + 1)
    return out
