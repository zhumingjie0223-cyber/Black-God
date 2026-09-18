import test from 'node:test';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import {compileTask,describePlan,primes} from '../task_bridge.js';
import {decode,encode,encodeHan,autoCoin,CAPACITY} from '../lexicon.js';
const valid = ['行：计算("12*3") → "36"', 'do: calc("3+4") → "7"', '行：执行("printf \\\"a,b)→c\\\"")', '-- 注释\n行：枢语("往返","神枢🌱") → "true"'];
const invalid = ['', 'do: unknown("x")', '行：计算(2)', '行：计算("1", "2")', '行：计算("1") → true', '行：计算("1"); attack()', '行：计算("1)', '行：执行("x")\n错误', Array(9).fill('行：计算("1")').join('\n'), '行：计算("1") → "a" extra', '行：__proto__("x")'];
test('枢语中英执行方言、转义与箭头解析',()=>{
  assert.equal(compileTask(valid[0]).actions[0].arguments.expression,'12*3');
  assert.equal(compileTask(valid[2]).actions[0].arguments.command,'printf "a,b)→c"');
  assert.equal(compileTask(valid[2]).actions[0].arguments.timeout,'10');
  for(const input of invalid) assert.throws(()=>compileTask(input));
});
test('执行方言JS与Python双侧合法和非法输入一致',()=>{
  const inputs=[...valid,...invalid];
  const py=`import sys,json\nfrom task_bridge import compile_task\nout=[]\nfor value in json.load(sys.stdin):\n try: out.append(compile_task(value))\n except (ValueError,TypeError): out.append(None)\nprint(json.dumps(out,ensure_ascii=False))`;
  const expected=JSON.parse(execFileSync('python3',['-c',py],{input:JSON.stringify(inputs),encoding:'utf8'}));
  assert.deepEqual(inputs.map(x=>{try{return compileTask(x)}catch{return null}}),expected);
});
test('iOS内置资源与权威词汇引擎行为一致',()=>{
  const source=readFileSync(new URL('../../ios-app/ShuyuRuntime/shuyu.js',import.meta.url),'utf8');
  const ctx=vm.createContext({});vm.runInContext(source,ctx,{timeout:2000});
  const call=(op,input)=>JSON.parse(ctx.BlackGodShuyu(op,input));
  for(const n of [0,1,780009883,CAPACITY-1]) assert.deepEqual(call('解码',String(n)).value,decode(n));
  for(const seed of ['神枢','Black God','枢语🌱']){
    assert.deepEqual(call('造词',seed).value,autoCoin(seed));
    const w=autoCoin(seed); assert.equal(call('汉译编号',w.汉).value,encodeHan(w.汉));assert.equal(call('拉丁编号',w.词).value,encode(w.词));
    assert.equal(call('往返',seed).value,true);
  }
  for(const input of valid) assert.deepEqual(call('编译',input).value,compileTask(input));
  assert.equal(call('解码','NaN').ok,false);assert.equal(call('unknown','').ok,false);
});

test('标准质数原语两侧一致并拒绝越界',()=>{
  for(const input of ['0','1','2','10','20','997']) {
    const py=execFileSync('python3',['-c','import sys,json; from task_bridge import primes; print(json.dumps(primes(sys.argv[1])))',input],{encoding:'utf8'});
    assert.deepEqual(primes(input),JSON.parse(py));
  }
  for(const input of ['10001','-1','1.5','NaN',true]) assert.throws(()=>primes(input));
});
test('规划与核对编译为有界工具，八步内合法，九步拒绝',()=>{
  const program=compileTask('行：规划("拆目标")\n行：检索("锚点")\n行：核对("结果可检查")');
  assert.equal(program.version,2);
  assert.equal(program.actions[0].id,'s1');
  assert.equal(program.actions[0].tool,'plan');
  assert.equal(program.actions[1].arguments.operation,'检索');
  assert.equal(program.actions[1].arguments.input,'锚点');
  assert.equal(program.actions[2].tool,'verify');
  assert.deepEqual(describePlan(program).map(x=>x.title),['拆目标','锚点','结果可检查']);
  const eight=Array.from({length:8},(_,i)=>`行：计算("${i+1}")`).join('\n');
  assert.equal(compileTask(eight).actions.length,8);
  assert.throws(()=>compileTask(eight+'\n行：计算("9")'));
});
test('邻近、时间与一息编译为有界工具，规划标题用时区',()=>{
  const program=compileTask('行：邻近("奥形凝起")\n行：时间("Asia/Shanghai")\n行：一息("1700000000")\n行：余息("1700000000")\n行：回息("1700000000")\n行：摇息("1700000000")');
  assert.equal(program.actions[0].arguments.operation,'邻近');
  assert.equal(program.actions[0].arguments.input,'奥形凝起');
  assert.equal(program.actions[1].tool,'clock');
  assert.equal(program.actions[1].arguments.timezone,'Asia/Shanghai');
  assert.equal(program.actions[2].arguments.operation,'一息');
  assert.equal(program.actions[2].arguments.input,'1700000000');
  assert.equal(program.actions[3].arguments.operation,'余息');
  assert.equal(program.actions[4].arguments.operation,'回息');
  assert.equal(program.actions[5].arguments.operation,'摇息');
  assert.deepEqual(describePlan(program).map(x=>x.title),['奥形凝起','Asia/Shanghai','1700000000','1700000000','1700000000','1700000000']);
});
test('规划描述 JS 与 Python 一致',()=>{
  const source='行：规划("先算")\n行：计算("1+1") → "2"';
  const py=`import json,sys; from task_bridge import compile_task,describe_plan; p=compile_task(sys.stdin.read()); print(json.dumps({"program":p,"plan":describe_plan(p)},ensure_ascii=False))`;
  const expected=JSON.parse(execFileSync('python3',['-c',py],{input:source,encoding:'utf8'}));
  const program=compileTask(source);
  assert.deepEqual(program,expected.program);
  assert.deepEqual(describePlan(program),expected.plan);
});
