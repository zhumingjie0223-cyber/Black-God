---
name: python-toolkit
version: 2.0.0
description: >-
  Python实战工具链知识库。覆盖隐身爬虫、OCR文档处理、AI Agent框架、
  数据处理/科学计算、Django后端工程、本地大模型部署、开发效率技巧。
  收录31个精选工具、真实可运行代码、部署命令。问到Python爬虫、
  数据清洗、后端开发、AI Agent、OCR、本地模型、爬虫框架时触发。
triggers:
  - python爬虫
  - 数据处理
  - 数据清洗
  - django
  - 后端开发
  - ai agent
  - ocr
  - 本地模型
  - 爬虫框架
  - fastapi
  - pydantic
  - langchain
  - 网页抓取
  - web scraping
priority: 850
---

# Python 实战工具链

> 数据来源：TG @pythonl（Python/Django）社区 3677 条帖，经去重结构化。
> 31 个精选工具 + 真实可运行代码 + 部署命令，按工作流组织。

---

## 1. 爬虫 / 网页抓取（Scraping）

| 工具 | 定位 | GitHub |
|------|------|--------|
| **Stealth-Requests** | 隐身请求，模拟浏览器指纹，HTML→Markdown | jpjacobpadilla/Stealth-Requests |
| **curl-impersonate** | 模拟 Chrome/FF 的 TLS+HTTP 指纹的 curl | lwthiker/curl-impersonate |
| **Scrapling** | 抗结构变化的稳定解析（网页改版不崩） | D4Vinci/Scrapling |
| **Scrapy** | 经典重型框架，大规模爬虫+数据管道 | scrapy/scrapy |
| **Crawlee** | 生产级框架，队列/重试/浏览器自动化/存储 | apify/crawlee |
| **Crawl4AI** | 输出 LLM 友好页面，零配置 | unclecode/crawl4ai |
| **Firecrawl** | 网站→Markdown/JSON，喂 LLM/RAG | firecrawl/firecrawl |
| **Browser Use** | AI 控制浏览器点击/填表/采集 | browser-use/browser-use |
| **AutoScraper** | 给样例自动学抓取规则 | alirezamika/autoscraper |

**选型口诀**：
- 要**隐身**过反爬 → Stealth-Requests / curl-impersonate（TLS 指纹级伪装）
- 网页**经常改版** → Scrapling（结构自适应）
- **大规模**工业爬虫 → Scrapy / Crawlee
- 喂给 **LLM/RAG** → Firecrawl / Crawl4AI（直接出 Markdown）
- 要**过 JS 渲染/登录** → Browser Use（真浏览器）

### 隐身爬虫 + 正则提链接
```python
import re, requests
def extract_links(url):
    response = requests.get(url)
    links = re.findall(r'href=["\']?(https?://[^"\'>]+)', response.text)
    return links
# 生产环境把 requests 换成 stealth_requests.get() 即可获得指纹伪装
```

### 快速部署爬虫/Bot 后端服务器
```bash
sudo apt update && sudo apt install -y python3-venv python3-pip nginx
python -m venv .venv && source .venv/bin/activate
pip install stealth-requests scrapling firecrawl-py
```

---

## 2. OCR / 文档处理（Document）

| 工具 | 能力 | 来源 |
|------|------|------|
| **DeepSeek-OCR** | 本地 OCR，图像/PDF→Markdown/HTML/DOCX/JSON | rdumasia303/deepseek_ocr_app |
| **Baidu Unlimited OCR** | 长文档一次识别多页 | baidu/Unlimited-OCR |
| **Mistral AI OCR 4** | 文档→结构化数据，可自托管 | Mistral |
| **MarkItDown** | PDF/Office/HTML→Markdown（微软出品） | microsoft/markitdown |

**流水线**：扫描件/PDF → DeepSeek-OCR（本地免费，隐私安全）或 Baidu Unlimited OCR（长文档）→ Markdown → 喂 LLM。纯格式转换（非扫描件）用 MarkItDown 更快。

---

## 3. AI Agent 框架（Agent）

| 框架 | 特点 |
|------|------|
| **Anthropic Claude Code** | Agent 循环开发平台（本项目底座） |
| **LangChain / LangGraph** | 链式编排，生态最全 |
| **CrewAI** | 多智能体协作（角色分工） |
| **smolagents** | 极简 Agent（HuggingFace） |
| **llama-index** | RAG 检索增强首选 |
| **semantic-kernel** | 微软 Agent 编排 |
| **pyautogen (AutoGen)** | 多 Agent 对话 |
| **dspy-ai** | 声明式 Prompt 优化 |
| **Audit** | 找漏洞的 AI Agent，多线程+"故意异议" | evilsocket/audit |

### 一键装全套 Agent 生态
```bash
pip install langchain langchain-experimental crewai smolagents \
    llama-index semantic-kernel pyautogen dspy-ai nicegui pydantic
```

---

## 4. 本地大模型部署（Local LLM）

| 工具 | 用途 |
|------|------|
| **llama.cpp** | 跑 GGUF 格式模型（CPU/GPU 通吃） |
| **Unsloth Studio** | 本地跑 DeepSeek-V4-Flash / GLM-5.2，微调加速 |
| **DeepSeek-V4-Flash** | 可本地部署的强模型，GGUF |
| **GLM-5.2** | 开源强模型，Unsloth 本地跑 |
| **OpenJarvis** | 本地 AI 助手，集成设备/文件 | open-jarvis/OpenJarvis |

**本地私有部署链**：下 GGUF 权重 → `llama.cpp` 加载 → 或用 `Unsloth Studio` 微调后部署。数据不出本地，敏感场景首选。

---

## 5. 数据处理 / 科学计算（Data）

| 工具 | 用途 |
|------|------|
| **Data-Juicer** | 大模型数据预处理：清洗/过滤/去重/合成/分析 | datajuicer/data-juicer |
| numpy / scipy / sympy | 数值/科学/符号计算 |
| pandas | 表格数据处理 |
| scikit-learn | 机器学习 |

### 科学计算实战（符号+数值+向量化）
```python
import numpy as np, sympy as sp
from scipy import integrate
# 1.符号积分
x = sp.symbols('x')
analytic = sp.integrate(sp.sin(x)/x, (x, 1, 10))
# 2.数值积分
numeric, err = integrate.quad(lambda x: np.sin(x)/x, 1, 10)
# 3.向量化代替循环（百万级快百倍）
arr = np.linspace(1, 10, 1_000_000)
fast = np.sin(arr) / arr
```

### 查找重复文件（MD5 去重）
```python
import os, hashlib
m = {}
for n in os.listdir("."):
    if os.path.isfile(n):
        with open(n, "rb") as f:
            h = hashlib.md5(f.read()).hexdigest()
        m.setdefault(h, []).append(n)
for v in m.values():
    if len(v) > 1:
        print("DUP:", v)
```

### 优雅读二进制大文件（分块，不爆内存）
```python
from functools import partial
def process_block(block):
    print(f"Processing block of size: {len(block)}")
with open("mydata.db", "rb") as f:
    for block in iter(partial(f.read, 64), b""):
        process_block(block)
```

### 实时读长期进程输出（爬虫/Bot 监控）
```python
import subprocess
process = subprocess.Popen(["python", "-m", "http.server", "8000"],
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE)
for line in iter(process.stdout.readline, b''):
    print(f"STDOUT: {line.decode().strip()}")
    # 这里可触发 TG Bot 通知 / 更新 Flask 状态
```

### 数据校验（Pydantic 正则约束）
```python
from pydantic import BaseModel, Field
class Address(BaseModel):
    zip_code: str = Field(pattern=r"^\d{5}$")  # 不符则 ValidationError
class Customer(BaseModel):
    name: str
    address: Address
```

---

## 6. Django 后端工程（Backend）

| 工具 | 用途 |
|------|------|
| **Wagtail** | Django CMS，强化后台管理界面 | wagtail |
| **SQLModel** | Pydantic+SQLAlchemy，类型注解写 SQL，少写重复代码 | fastapi/sqlmodel |

### Service 层 + 事务原子性（生产级 Django 架构）
```python
# services/order_service.py —— 业务逻辑抽离 View
from django.db import transaction
from .models import Order, OrderItem

class OrderService:
    @staticmethod
    @transaction.atomic  # 全部成功或全部回滚
    def create_order(*, user, items_data):
        order = Order.objects.create(user=user, status="new")
        OrderItem.objects.bulk_create([  # 批量插入，一次 SQL
            OrderItem(order=order, product_id=i["product_id"],
                      quantity=i["quantity"], price=i["price"])
            for i in items_data
        ])
        return order
```
```python
# View 只做校验+调用，薄 View 胖 Service
def create_order_view(request):
    serializer = OrderCreateSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    order = OrderService.create_order(user=request.user,
        items_data=serializer.validated_data["items"])
    return Response({"order_id": order.id})
```
**要点**：`@transaction.atomic` 保证一致性，`bulk_create` 批量插入省 N 次 SQL，业务逻辑全进 Service 层（薄 View 胖 Service，易测易复用）。

---

## 7. 开发效率技巧（Productivity）

### 项目启动模板
```bash
mkdir my_project && cd my_project
python -m venv .venv && source .venv/bin/activate
touch main.py requirements.txt .env .gitignore
echo ".venv/\n__pycache__/\n.env\n*.pyc" > .gitignore
pip install -U pip
pip install ruff black python-dotenv   # 格式化+lint+环境变量
```

### uv —— 比 pip 快 10-100 倍的包管理
```bash
pip install uv
uv run script.py   # 自动建环境+装依赖+运行，一条命令搞定
```

### Pythonic 写法速查
```python
a, b = b, a                          # 交换变量
if items:  process(items)            # 空检查（别用 len()>0）
if not items:  print("Empty")        # 判空
fruits = [f for f in fruits if f != "orange"]  # 迭代时删元素的正确姿势
```

### 其他实用工具
- **getpass**：安全获取密码（不回显）
- **logging**：结构化日志（别用 print 调试生产代码）
- **debugpy**：VSCode 远程调试
- **TerminalTextEffects**：终端动画文本，零依赖 | ChrisBuilds/terminaltexteffects
- **scrcpy**：电脑控制安卓设备（移动端自动化测试）| Genymobile/scrcpy
- **GitFut**：GitHub 主页转 FIFA 球星卡 | gitfut.com

---

## 附录：31 个工具速查索引

**爬虫**：Stealth-Requests, curl-impersonate, Scrapling, Scrapy, Crawlee, Crawl4AI, Firecrawl, Browser Use, AutoScraper
**OCR**：DeepSeek-OCR, Baidu Unlimited OCR, Mistral AI OCR 4, MarkItDown
**Agent**：Claude Code, smolagents, Audit, OpenJarvis
**本地模型**：llama.cpp, Unsloth Studio, DeepSeek-V4-Flash, GLM-5.2, OpenMythos
**数据**：Data-Juicer, SQLModel
**Django**：Wagtail
**工程**：uv, getpass, logging, TerminalTextEffects, scrcpy, GitFut
