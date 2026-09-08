"""枢语执行方言v1；与task_bridge.js同构。仅编译，不执行输入。"""
import json
import re
TASK_VERSION = 1
_MAPPING = {
    '计算': ('calc', ['expression']), 'calc': ('calc', ['expression']),
    '枢语': ('shuyu', ['operation', 'input']), 'shuyu': ('shuyu', ['operation', 'input']),
    '执行': ('shell_execute', ['command']), 'shell': ('shell_execute', ['command']),
}
def compile_task(source):
    if not isinstance(source, str) or len(source.encode('utf-16-le')) // 2 > 8192:
        raise ValueError('枢语程序为空或超过8192字符')
    lines = [s.strip() for s in source.split('\n') if s.strip() and not s.strip().startswith('--')]
    if not 1 <= len(lines) <= 4:
        raise ValueError('每个枢语程序需要1至4条执行语句')
    actions = []
    for line in lines:
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
        tool, keys = _MAPPING[head[1]]
        if len(args) != len(keys) or any(not isinstance(x, str) or not x.strip() or len(x.encode('utf-16-le')) // 2 > 4096 for x in args):
            raise ValueError('参数数量或类型错误')
        suffix = line[end + 1:].strip()
        expected = None
        if suffix:
            if not suffix.startswith('→'):
                raise ValueError('行末尾无效')
            expected = json.loads(suffix[1:].strip())
            if not isinstance(expected, str) or len(expected.encode('utf-16-le')) // 2 > 4096:
                raise ValueError('验收结果必须为有限长度字符串')
        arguments = dict(zip(keys, args))
        if tool == 'shell_execute':
            arguments['timeout'] = '10'
        actions.append(dict(tool=tool, arguments=arguments, expected=expected))
    return dict(version=TASK_VERSION, actions=actions)

def primes(value):
    if not isinstance(value, str) or not re.fullmatch(r'[0-9]+', value) or int(value) > 10000:
        raise ValueError('质数范围必须为0至10000整数')
    out = []
    for n in range(2, int(value) + 1):
        d = 2
        while d*d <= n and n % d:
            d += 1
        if d*d > n:
            out.append(n)
    return out
