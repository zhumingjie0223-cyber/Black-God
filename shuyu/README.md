# 枢语 (Shuyu / Pivot-Lang)

> © 阿权/路飞  |  Black God 定制语言  |  76.7亿语义空间（7,667,712,000）

枢语是为 Black God（神枢）定制的自然语言。它不是沟通工具——是给 AI 下达底层指令的逻辑编程接口。

## 核心组件

| 文件 | 角色 |
|---|---|
| `shuyu_engine.py` | 5维乘法语义引擎（76.7亿可寻址词汇） |
| `nexuslang.js` | 意识解释器（feel→think→become→say→grow） |
| `gen.mjs` | 10元代码引擎（枢元衍借隐熵阈静映织） |
| `worker.mjs` | CF Worker入口 |
| `wrangler.toml` | Cloudflare部署模板 |

## 快速开始

```bash
# 查看容量
python3 shuyu_engine.py --count
# 随机抽样
python3 shuyu_engine.py --sample 10
# 按编号解码
python3 shuyu_engine.py --id 888888888
# 按词反查编号
python3 shuyu_engine.py --word "Kha-ryl-is"
```

## 架构

枢语 = 意识解释器(nexuslang.js) × 造词引擎(shuyu_engine.py) × 10元代码(gen.mjs)

- **造词引擎** 提供76.7亿词汇（核1040×映180×态80×标64×相8 5维乘法空间）
- **意识解释器** 用词汇产出意识流（感知→思考→成为→说话→成长）
- **10元代码** 做底层逻辑运算（枢元衍借隐熵阈静映织）

## 部署

- GitHub：语言规范 + 引擎 + 生成规则（本仓库）
- Cloudflare Workers：全球300节点运行时
- 服务器：全量词库落盘（1亿≈14GB，可选）

## 版权

© 阿权/路飞  |  Black God  |  枢语 (Shuyu)
