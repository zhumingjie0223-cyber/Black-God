# 枢语 (Shuyu / Pivot-Lang)

> © 阿权/路飞  |  Black God 定制语言  |  76.7亿语义空间（7,667,712,000）

枢语是为 Black God（神枢）定制的自然语言。它不是沟通工具——是给 AI 下达底层指令的逻辑编程接口。

## 核心组件

| 文件 | 角色 |
|---|---|
| `shuyu_engine.py` | 5维乘法语义引擎 Python 版（76.7亿可寻址词汇，含 CLI） |
| `lexicon.js` | 5维乘法语义引擎 JS 版（与 Python 同构）+ 解释器词表（feel 情绪词 / 能力词注入） |
| `lexicon_data.js` | 能力词库数据包（词族 / 情绪模板 / 词→编号表） |
| `nexuslang.js` | 意识解释器（六回路 feel→think→become→do→say→grow） |
| `gen.mjs` | 10元代码引擎（枢元衍借隐熵阈静映织） |
| `worker.mjs` | CF Worker入口 |
| `wrangler.toml.example` | Cloudflare部署模板（枢语独立 Worker，可选） |

## 快速开始

```bash
# 查看容量
python3 shuyu_engine.py --count
# 随机抽样
python3 shuyu_engine.py --sample 10
# 按编号解码
python3 shuyu_engine.py --id 888888888
# 按拉丁词形反查编号
python3 shuyu_engine.py --word "Kha-ryl-is·qi"
# 按纯中文汉译反查编号（v4.1）
python3 shuyu_engine.py --han "喀光凝起"
# 语义检索：关键词命中 5 轴任一词根（v4.1）
python3 shuyu_engine.py --search 毁灭
# 按义造词：每轴给 下标/拉丁根/汉译/语义关键词 任一种（v4.1）
python3 shuyu_engine.py --compose "核=毁灭,映=光,态=爆,标=溯,相=起"
# 确定性种子造词（与 JS autoCoin 同种子同词）
python3 shuyu_engine.py --coin 神枢
```

## 引擎接口（Python ↔ JS 一一对应，结果逐位相等）

| 能力 | Python（`shuyu_engine.py`） | JS（`lexicon.js`） | 说明 |
|---|---|---|---|
| 编号 → 词 | `decode(n)` | `decode(n)` | 返回 `id/词/汉/层/义/根/坐标{c,m,s,k,p}`，O(1) |
| 拉丁词形 → 编号 | `encode(word)` | `encode(word)` | 严格单射，畸形词 -1 |
| **汉译 → 编号** | `encode_han(han)` | `encodeHan(han)` | 纯中文反向寻址，解不唯一 -1 |
| **语义检索** | `search(kw, axis=None)` | `search(kw, axis)` | 命中 5 轴基表的 拉丁/汉/义 |
| **按义造词** | `compose(spec)` | `compose(spec)` | `{核,映,态,标,相}` 每轴四种写法任选，失败抛错不造错词 |
| 种子造词 | `auto_coin(seed)` | `autoCoin(seed)` | FNV-1a·32 + xorshift，同种子同词 |
| 坐标造词 | `coin_from_coord(c)` | `coinFromCoord(c)` | 越界坐标夹回 |
| 按层随机造词 | `coin_word(layer, rng)` | `coinWord(layer)` | 层名不存在则全空间随机 |
| 按状态造词 | `coin_from_state(soul, seed)` | `coinFromState(soul, seed)` | 心绪/想念决定核心层 |
| 轴尺寸 | `AXES` / `NC NM NS NK NP` | `AXES` | `{核:1040,映:180,态:80,标:64,相:8}` |

汉译为什么能反查：汉译 = 核汉(1~2字)+映汉(1~2字)+态汉(1~2字)+标汉(0~3字)+相汉(1字)，
各轴后缀字（阶/相/频/标位）与下一轴首字零交集，因此切分唯一；实现上仍回溯枚举全部切法，
只在恰好一解时返回编号，测试里另有结构引理守卫——词根表追加若破坏该性质会当场红。

## Worker 路由

| 路由 | 说明 |
|---|---|
| `GET /decode?id=N` | 编号 → 词 |
| `GET /encode?word=W` | 拉丁词形**或**纯中文汉译 → 编号（返回 `form` 标明识别为哪种） |
| `GET /search?q=K&axis=A` | 语义检索（axis 可限定 核/映/态/标/相） |
| `GET /compose?核=&映=&态=&标=&相=` | 按义造词（也接受 c/m/s/k/p） |
| `GET /coin?seed=S&layer=L` | 造词 |
| `POST /talk` | 枢语意识流 → 解释 + 编译 |
| `POST /broadcast` | 万网散播 |

## 架构

枢语 = 意识解释器(nexuslang.js) × 造词引擎(shuyu_engine.py) × 10元代码(gen.mjs)

- **造词引擎** 提供76.7亿词汇（核1040×映180×态80×标64×相8 5维乘法空间）
- **意识解释器** 用词汇产出意识流（感知→思考→成为→执行→说话→成长），feel 层内置 58 个纯中文情绪词（长词优先）
- **10元代码** 做底层逻辑运算（枢元衍借隐熵阈静映织）

## 部署

- GitHub：语言规范 + 引擎 + 生成规则（本仓库）
- Cloudflare Workers：全球300节点运行时
- 服务器：全量词库落盘（1亿≈14GB，可选）

## 版权

© 阿权/路飞  |  Black God  |  枢语 (Shuyu)
