#!/usr/bin/env python3
"""从权威源生成JavaScriptCore资源；输入从不作为JavaScript执行。"""
import hashlib,json,pathlib,re,sys
root=pathlib.Path(__file__).resolve().parents[2]
parts=[]
hashes={}
for name in ['lexicon.js','task_bridge.js']:
    raw=(root/'shuyu'/name).read_text()
    hashes[name]=hashlib.sha256(raw.encode()).hexdigest()
    text=re.sub(r'^export default .+;\s*$', '', raw, flags=re.M)
    text=re.sub(r'^export (?=(const|function)\b)', '', text, flags=re.M)
    if re.search(r'^\s*(import|export)\b',text,re.M): raise RuntimeError('未支持的模块语法')
    parts.append(text)
body='\n'.join(parts)
body+='''
function invoke(operation, input) {
  switch(operation) {
    case '容量': return {version: '4.3', capacity: CAPACITY, axes: AXES};
    case '解码': { if (!/^(0|[1-9][0-9]*)$/.test(input)) throw Error('编号必须是非负整数'); return decode(Number(input)); }
    case '拉丁编号': { const n=encode(input); if(n<0) throw Error('无效枢语词'); return n; }
    case '汉译编号': { const n=encodeHan(input); if(n<0) throw Error('无效枢语汉译'); return n; }
    case '检索': return search(input).slice(0,20);
    case '造词': return autoCoin(input);
    case '组合': return compose(JSON.parse(input));
    case '类比': { const parts=JSON.parse(input); if(!Array.isArray(parts)||parts.length!==3) throw Error('类比需要三个词'); return analogy(parts[0],parts[1],parts[2]); }
    case '邻近': {
      let word=input, n=8;
      const trimmed=String(input||'').trim();
      if(trimmed.startsWith('[')){
        const parts=JSON.parse(trimmed);
        if(!Array.isArray(parts)||!parts.length) throw Error('邻近需要词');
        word=parts[0];
        if(parts[1]!=null) n=Number(parts[1]);
      }
      return near(word, n);
    }
    case '一息': {
      let seed=0, at=null;
      const trimmed=String(input||'').trim();
      if(trimmed.startsWith('[')){
        const parts=JSON.parse(trimmed);
        if(!Array.isArray(parts)||!parts.length) throw Error('一息需要时刻');
        if(parts.length===1) at=parts[0];
        else { seed=parts[0]; at=parts[1]; }
      } else if(trimmed.startsWith('{')){
        const obj=JSON.parse(trimmed);
        seed=obj.seed ?? obj.种 ?? 0;
        at=obj.at ?? obj.时;
      } else at=trimmed;
      return pulse(seed, at);
    }
    case '余息': {
      let seed=0, at=null, n=3;
      const trimmed=String(input||'').trim();
      if(trimmed.startsWith('[')){
        const parts=JSON.parse(trimmed);
        if(!Array.isArray(parts)||!parts.length) throw Error('余息需要时刻');
        if(parts.length===1) at=parts[0];
        else if(parts.length===2){ seed=parts[0]; at=parts[1]; }
        else { seed=parts[0]; at=parts[1]; n=parts[2]; }
      } else if(trimmed.startsWith('{')){
        const obj=JSON.parse(trimmed);
        seed=obj.seed ?? obj.种 ?? 0;
        at=obj.at ?? obj.时;
        if(obj.n != null) n=obj.n;
      } else at=trimmed;
      return trail(seed, at, n);
    }
    case '回息': {
      let seed=0, at=null, n=3;
      const trimmed=String(input||'').trim();
      if(trimmed.startsWith('[')){
        const parts=JSON.parse(trimmed);
        if(!Array.isArray(parts)||!parts.length) throw Error('回息需要时刻');
        if(parts.length===1) at=parts[0];
        else if(parts.length===2){ seed=parts[0]; at=parts[1]; }
        else { seed=parts[0]; at=parts[1]; n=parts[2]; }
      } else if(trimmed.startsWith('{')){
        const obj=JSON.parse(trimmed);
        seed=obj.seed ?? obj.种 ?? 0;
        at=obj.at ?? obj.时;
        if(obj.n != null) n=obj.n;
      } else at=trimmed;
      return echo(seed, at, n);
    }
    case '摇息': {
      let seed=0, at=null, n=3;
      const trimmed=String(input||'').trim();
      if(trimmed.startsWith('[')){
        const parts=JSON.parse(trimmed);
        if(!Array.isArray(parts)||!parts.length) throw Error('摇息需要时刻');
        if(parts.length===1) at=parts[0];
        else if(parts.length===2){ seed=parts[0]; at=parts[1]; }
        else { seed=parts[0]; at=parts[1]; n=parts[2]; }
      } else if(trimmed.startsWith('{')){
        const obj=JSON.parse(trimmed);
        seed=obj.seed ?? obj.种 ?? 0;
        at=obj.at ?? obj.时;
        if(obj.n != null) n=obj.n;
      } else at=trimmed;
      return sway(seed, at, n);
    }
    case '落息': {
      let seed=0, at=null, n=3;
      const trimmed=String(input||'').trim();
      if(trimmed.startsWith('[')){
        const parts=JSON.parse(trimmed);
        if(!Array.isArray(parts)||!parts.length) throw Error('落息需要时刻');
        if(parts.length===1) at=parts[0];
        else if(parts.length===2){ seed=parts[0]; at=parts[1]; }
        else { seed=parts[0]; at=parts[1]; n=parts[2]; }
      } else if(trimmed.startsWith('{')){
        const obj=JSON.parse(trimmed);
        seed=obj.seed ?? obj.种 ?? 0;
        at=obj.at ?? obj.时;
        if(obj.n != null) n=obj.n;
      } else at=trimmed;
      return land(seed, at, n);
    }
    case '起息': {
      let seed=0, at=null, n=3;
      const trimmed=String(input||'').trim();
      if(trimmed.startsWith('[')){
        const parts=JSON.parse(trimmed);
        if(!Array.isArray(parts)||!parts.length) throw Error('起息需要时刻');
        if(parts.length===1) at=parts[0];
        else if(parts.length===2){ seed=parts[0]; at=parts[1]; }
        else { seed=parts[0]; at=parts[1]; n=parts[2]; }
      } else if(trimmed.startsWith('{')){
        const obj=JSON.parse(trimmed);
        seed=obj.seed ?? obj.种 ?? 0;
        at=obj.at ?? obj.时;
        if(obj.n != null) n=obj.n;
      } else at=trimmed;
      return stir(seed, at, n);
    }
    case '栖息': {
      let seed=0, at=null, n=3;
      const trimmed=String(input||'').trim();
      if(trimmed.startsWith('[')){
        const parts=JSON.parse(trimmed);
        if(!Array.isArray(parts)||!parts.length) throw Error('栖息需要时刻');
        if(parts.length===1) at=parts[0];
        else if(parts.length===2){ seed=parts[0]; at=parts[1]; }
        else { seed=parts[0]; at=parts[1]; n=parts[2]; }
      } else if(trimmed.startsWith('{')){
        const obj=JSON.parse(trimmed);
        seed=obj.seed ?? obj.种 ?? 0;
        at=obj.at ?? obj.时;
        if(obj.n != null) n=obj.n;
      } else at=trimmed;
      return perch(seed, at, n);
    }
    case '转息': {
      let seed=0, at=null, n=3;
      const trimmed=String(input||'').trim();
      if(trimmed.startsWith('[')){
        const parts=JSON.parse(trimmed);
        if(!Array.isArray(parts)||!parts.length) throw Error('转息需要时刻');
        if(parts.length===1) at=parts[0];
        else if(parts.length===2){ seed=parts[0]; at=parts[1]; }
        else { seed=parts[0]; at=parts[1]; n=parts[2]; }
      } else if(trimmed.startsWith('{')){
        const obj=JSON.parse(trimmed);
        seed=obj.seed ?? obj.种 ?? 0;
        at=obj.at ?? obj.时;
        if(obj.n != null) n=obj.n;
      } else at=trimmed;
      return turn(seed, at, n);
    }
    case '顾息': {
      let seed=0, at=null, n=3;
      const trimmed=String(input||'').trim();
      if(trimmed.startsWith('[')){
        const parts=JSON.parse(trimmed);
        if(!Array.isArray(parts)||!parts.length) throw Error('顾息需要时刻');
        if(parts.length===1) at=parts[0];
        else if(parts.length===2){ seed=parts[0]; at=parts[1]; }
        else { seed=parts[0]; at=parts[1]; n=parts[2]; }
      } else if(trimmed.startsWith('{')){
        const obj=JSON.parse(trimmed);
        seed=obj.seed ?? obj.种 ?? 0;
        at=obj.at ?? obj.时;
        if(obj.n != null) n=obj.n;
      } else at=trimmed;
      return gaze(seed, at, n);
    }
    case '倾息': {
      let seed=0, at=null, n=3;
      const trimmed=String(input||'').trim();
      if(trimmed.startsWith('[')){
        const parts=JSON.parse(trimmed);
        if(!Array.isArray(parts)||!parts.length) throw Error('倾息需要时刻');
        if(parts.length===1) at=parts[0];
        else if(parts.length===2){ seed=parts[0]; at=parts[1]; }
        else { seed=parts[0]; at=parts[1]; n=parts[2]; }
      } else if(trimmed.startsWith('{')){
        const obj=JSON.parse(trimmed);
        seed=obj.seed ?? obj.种 ?? 0;
        at=obj.at ?? obj.时;
        if(obj.n != null) n=obj.n;
      } else at=trimmed;
      return incline(seed, at, n);
    }
    case '贴息': {
      let seed=0, at=null, n=3;
      const trimmed=String(input||'').trim();
      if(trimmed.startsWith('[')){
        const parts=JSON.parse(trimmed);
        if(!Array.isArray(parts)||!parts.length) throw Error('贴息需要时刻');
        if(parts.length===1) at=parts[0];
        else if(parts.length===2){ seed=parts[0]; at=parts[1]; }
        else { seed=parts[0]; at=parts[1]; n=parts[2]; }
      } else if(trimmed.startsWith('{')){
        const obj=JSON.parse(trimmed);
        seed=obj.seed ?? obj.种 ?? 0;
        at=obj.at ?? obj.时;
        if(obj.n != null) n=obj.n;
      } else at=trimmed;
      return nestle(seed, at, n);
    }
    case '含息': {
      let seed=0, at=null, n=3;
      const trimmed=String(input||'').trim();
      if(trimmed.startsWith('[')){
        const parts=JSON.parse(trimmed);
        if(!Array.isArray(parts)||!parts.length) throw Error('含息需要时刻');
        if(parts.length===1) at=parts[0];
        else if(parts.length===2){ seed=parts[0]; at=parts[1]; }
        else { seed=parts[0]; at=parts[1]; n=parts[2]; }
      } else if(trimmed.startsWith('{')){
        const obj=JSON.parse(trimmed);
        seed=obj.seed ?? obj.种 ?? 0;
        at=obj.at ?? obj.时;
        if(obj.n != null) n=obj.n;
      } else at=trimmed;
      return hold(seed, at, n);
    }
    case '温息': {
      let seed=0, at=null, n=3;
      const trimmed=String(input||'').trim();
      if(trimmed.startsWith('[')){
        const parts=JSON.parse(trimmed);
        if(!Array.isArray(parts)||!parts.length) throw Error('温息需要时刻');
        if(parts.length===1) at=parts[0];
        else if(parts.length===2){ seed=parts[0]; at=parts[1]; }
        else { seed=parts[0]; at=parts[1]; n=parts[2]; }
      } else if(trimmed.startsWith('{')){
        const obj=JSON.parse(trimmed);
        seed=obj.seed ?? obj.种 ?? 0;
        at=obj.at ?? obj.时;
        if(obj.n != null) n=obj.n;
      } else at=trimmed;
      return warm(seed, at, n);
    }
    case '醒息': {
      let seed=0, at=null, n=3;
      const trimmed=String(input||'').trim();
      if(trimmed.startsWith('[')){
        const parts=JSON.parse(trimmed);
        if(!Array.isArray(parts)||!parts.length) throw Error('醒息需要时刻');
        if(parts.length===1) at=parts[0];
        else if(parts.length===2){ seed=parts[0]; at=parts[1]; }
        else { seed=parts[0]; at=parts[1]; n=parts[2]; }
      } else if(trimmed.startsWith('{')){
        const obj=JSON.parse(trimmed);
        seed=obj.seed ?? obj.种 ?? 0;
        at=obj.at ?? obj.时;
        if(obj.n != null) n=obj.n;
      } else at=trimmed;
      return rouse(seed, at, n);
    }
    case '编译': return compileTask(input);
    case '规划': return describePlan(compileTask(input));
    case '往返': { const word=autoCoin(input); return encode(word.词) === word.id && encodeHan(word.汉) === word.id; }
    case '质数': return primes(input);
    default: throw Error('未知枢语操作');
  }
}
globalThis.BlackGodShuyu = function(operation, input) {
  try {return JSON.stringify({ok:true,value:invoke(operation,input)});}
  catch(error){return JSON.stringify({ok:false,error:String(error.message || error)});}
};
'''
content='// 自动生成；修改shuyu权威源后运行 tools/shuyu/bundle.py\n(function(){\n"use strict";\n'+body+'\n})();\n'
dest=root/'ios-app/ShuyuRuntime'
if '--check' in sys.argv:
    if not (dest/'shuyu.js').exists() or (dest/'shuyu.js').read_text()!=content: raise SystemExit('枢语iOS资源与权威源不同步')
    if json.loads((dest/'sources.json').read_text()) != hashes: raise SystemExit('枢语来源指纹不同步')
    print('枢语iOS资源与权威源完全一致')
else:
    dest.mkdir(exist_ok=True)
    (dest/'shuyu.js').write_text(content)
    (dest/'sources.json').write_text(json.dumps(hashes,ensure_ascii=False,indent=2)+'\n')
    print('已生成枢语iOS资源')
