# Black God Architecture Document

**Version:** 1.0  
**Last Updated:** 2026-06-28  
**Purpose:** Internal architecture review and external code audit

---

## 1. Product Positioning

**Black God** is a **private multi-device execution center**.

It is **not** a platform chat box. It connects user-controlled devices (phone, computer, server), APIs, tools, memory, and workflows into a unified execution system.

### Core Value Proposition

- **User-owned memory, tools, and execution**
- **Local-first privacy**: configs, keys, memory stored locally by default
- **Not locked to any platform**: users bring their own APIs, providers, tools
- **Real execution**: understands goals → calls tools → verifies results → learns from experience
- **Private deployment**: public demo for showcase, full private/enterprise versions for real use

---

## 2. System Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    User Interface                       │
│  (PWA: HTML/CSS/JS, offline-first, haptic feedback)    │
└────────────────┬────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────┐
│                  Agent Kernel (Core)                    │
│  ┌──────────────┬──────────────┬──────────────────┐    │
│  │ Dialog Loop  │ Task Router  │ Privacy Guard    │    │
│  └──────────────┴──────────────┴──────────────────┘    │
└────────────────┬────────────────────────────────────────┘
                 │
      ┌──────────┼──────────┬─────────────┬──────────┐
      │          │           │             │          │
      ▼          ▼           ▼             ▼          ▼
┌─────────┐ ┌────────┐ ┌─────────┐ ┌──────────┐ ┌────────┐
│Provider │ │ Memory │ │  Tools  │ │ Executor │ │ Skills │
│   Hub   │ │ System │ │ (15+)   │ │  Engine  │ │ (150+) │
└─────────┘ └────────┘ └─────────┘ └──────────┘ └────────┘
      │          │           │             │          │
      └──────────┴───────────┴─────────────┴──────────┘
                             │
                             ▼
              ┌──────────────────────────┐
              │  External Resources      │
              │  - User's API providers  │
              │  - Local files/tools     │
              │  - Remote servers        │
              └──────────────────────────┘
```

---

## 3. Core Modules

### 3.1 Agent Kernel

**Location:** `server/agent_kernel_v4.py`

**Responsibilities:**
- Receive user messages
- Multi-turn dialog loop with reasoning
- Task decomposition and orchestration
- Call tools, memory, providers
- Return structured responses

**Key Flow:**
```
User Input → Intent Recognition → Task Planning → Tool Calling → 
Result Verification → Memory Update → Response Generation
```

**Privacy features:**
- PII detection and masking
- Consent-based profile collection
- Local-first memory storage

---

### 3.2 Provider Hub

**Location:** `server/core/provider_registry.py`, `server/core/secret_store.py`

**Purpose:** Multi-provider API management system. Users configure their own API endpoints (OpenAI, Anthropic, custom gateways) without platform lock-in.

**Features:**
- **Provider registration**: label, type, base_url, model, priority
- **Secret storage**: API keys obfuscated locally, never uploaded
- **Default provider**: fallback and quality-based routing
- **Cost cascade**: prefer local cache → rule-based → tools → external API (future)

**API Endpoints:**
```
GET  /api/providers          - List all providers (keys masked)
POST /api/providers/save     - Save/update provider config
POST /api/providers/test     - Test provider connectivity
POST /api/providers/default  - Set default provider
```

**Security:**
- Keys obfuscated with XOR + base64 (not encryption, just anti-shoulder-surfing)
- File permission: chmod 600
- No keys in logs, responses, or git history

---

### 3.3 Memory System

**Location:** `server/memory/` (schema: `user_profile_schema.sql`)

**Structure:**
- **Short-term:** Current conversation context
- **Working memory:** Active tasks, recent interactions
- **Long-term:** User profile, project knowledge, learned patterns

**Storage:**
- SQLite (local), optionally synced to user's private server
- Markdown logs for human readability
- Embeddings for semantic search (optional)

**Privacy:**
- Consent-based: only store what user explicitly allows
- Local-first: stays on user's device by default
- Export/delete: user owns and controls all memory data

---

### 3.4 Tools & Executor

**Built-in Tools (15+):**
- File operations (read, write, search)
- Web browsing (navigate, screenshot, extract)
- Code execution (sandboxed Python, shell)
- Search (web, local, semantic)
- Calendar, reminders, device control (iOS/Android)

**Executor Engine:**
- Async task queue
- Tool call validation
- Result verification
- Retry and fallback logic

**Safety:**
- Sandboxed execution for code/shell
- User confirmation for destructive actions
- Rate limiting and timeout

---

### 3.5 Skills System

**Location:** `server/skills/` (150+ skills)

**Purpose:** Domain-specific capabilities loaded on-demand.

**Examples:**
- `web-search`: Multi-engine search orchestration
- `app-reverse-engineering`: APK/IPA analysis
- `ui-master`: Professional UI/UX design
- `project-retrospective`: Project state reconstruction

**Skill lifecycle:**
- Load on first mention (lazy loading)
- Merge into agent kernel context
- Persist learned patterns as new skills

---

### 3.6 Privacy Guard

**Location:** `server/core/privacy_guard.py`

**Features:**
- **PII detection**: email, phone, SSN, credit card, IP address
- **Consent flow**: explicit user permission before storing sensitive data
- **Data minimization**: only collect necessary information
- **Audit log**: track what was accessed, by whom, when

**Compliance:**
- GDPR-ready (data portability, right to erasure)
- Local-first by default
- No telemetry without consent

---

## 4. API Endpoints

### 4.1 Chat & Dialog

```
POST /api/chat
Request:
{
  "message": "user input",
  "session_id": "optional",
  "context": {}
}

Response:
{
  "reply": "agent response",
  "actions": [...],
  "memory_updated": true
}
```

---

### 4.2 Provider Management

```
GET /api/providers
Response:
{
  "providers": [
    {
      "id": "my_claude",
      "label": "Claude Max",
      "base_url": "https://api.anthropic.com",
      "token": "sk-ant-****xyz",  // masked
      "model": "claude-opus-4",
      "priority": 90,
      "enabled": true
    }
  ],
  "default": "my_claude"
}
```

```
POST /api/providers/save
Request:
{
  "id": "my_gpt",
  "config": {
    "label": "GPT-5.5",
    "type": "openai",
    "base_url": "https://api.openai.com/v1",
    "token": "sk-...",
    "model": "gpt-5.5",
    "priority": 80,
    "enabled": true
  }
}

Response:
{
  "ok": true,
  "id": "my_gpt"
}
```

```
POST /api/providers/test
Request: { "id": "my_gpt" }
Response: { "ok": true, "status": "connected" }
```

```
POST /api/providers/default
Request: { "id": "my_gpt" }
Response: { "ok": true, "default": "my_gpt" }
```

---

### 4.3 Memory

```
GET /api/memory?query=...
Response:
{
  "results": [
    { "type": "profile", "content": "..." },
    { "type": "project", "content": "..." }
  ]
}
```

```
POST /api/memory
Request:
{
  "type": "note",
  "content": "...",
  "tags": ["work", "important"]
}
```

---

### 4.4 Task Execution

```
POST /api/tasks
Request:
{
  "task": "analyze APK file",
  "params": { "file_path": "..." }
}

Response:
{
  "task_id": "...",
  "status": "running"
}
```

```
GET /api/tasks/{task_id}
Response:
{
  "status": "completed",
  "result": {...}
}
```

---

## 5. Frontend (PWA)

**Location:** `web/index.html`

**Tech:** Vanilla HTML/CSS/JS (no framework), offline-first, installable

**Features:**
- Service worker for offline capability
- Push notifications (via Web Push API)
- Haptic feedback (iOS/Android)
- iOS safe area support
- Dark mode

**UI Highlights:**
- Minimalist, high-contrast design
- Brand: metallic silver, cold tone (not warm/friendly, but precise/reliable)
- Real-time typing indicators
- Voice input support

---

## 6. Deployment Architecture

### Public Demo
- **Platform:** Cloudflare Workers
- **URL:** `https://blackgod-demo.jjiebbay.workers.dev` (example)
- **Purpose:** Showcase product direction, not full features
- **Data:** Ephemeral, no persistent storage

### Private Version
- **Platform:** User's own server (Linux, Docker, or bare metal)
- **Features:** Full Provider Hub, Memory, Tools, Skills
- **Data:** All local, user owns and controls

### Enterprise Version
- **Platform:** Private cloud / on-premises
- **Features:** Multi-user, role-based access, audit logs, SSO
- **Compliance:** GDPR, HIPAA-ready

---

## 7. Security & Privacy Principles

### Data Flow
```
User Input → Local Processing (priority) → External API (only if needed) → 
Local Storage → Never uploaded without explicit consent
```

### Key Security Measures
- **No default telemetry**: all analytics opt-in
- **Keys never logged**: provider tokens obfuscated, not in logs/responses
- **Sandboxed execution**: code/shell tools run in isolated environment
- **User confirmation**: destructive actions require explicit approval
- **Audit trail**: every sensitive operation logged locally

### Threat Model
- **Not protected against:** Physical device theft, malware on user's machine
- **Protected against:** Shoulder surfing, accidental key leakage in logs, unauthorized API access

---

## 8. Technology Stack

### Backend
- **Language:** Python 3.11+
- **Framework:** Custom HTTP server (http.server base, asyncio for concurrency)
- **Database:** SQLite (local memory)
- **Dependencies:** Minimal (requests, sqlite3, standard library)

### Frontend
- **Language:** HTML5, CSS3, JavaScript (ES6+)
- **Framework:** None (vanilla for performance and control)
- **PWA:** Service Worker, Web App Manifest
- **Push:** Web Push API (VAPID)

### Infrastructure
- **Public Demo:** Cloudflare Workers (serverless edge)
- **Private Deploy:** Linux server (systemd service)
- **MCP Connector:** Cloudflare Workers (for external integrations)

---

## 9. Roadmap & Known Limitations

### In Progress (P0)
- ✅ Provider Hub UI and API
- ✅ Secret storage and key masking
- ✅ Privacy Guard baseline
- ⏳ Cost cascade engine (multi-level model routing)
- ⏳ MCP connector for external integrations

### Planned (P1)
- Multi-device sync (phone ↔ computer ↔ server)
- Real-time collaboration (multiple users on same task)
- Advanced reasoning (chain-of-thought, self-critique)
- Expanded tool library (50+ tools)
- Skill marketplace (community-contributed skills)

### Known Limitations
- **Not end-to-end encrypted** (keys obfuscated, not encrypted)
- **No built-in auth** (assumes trusted local environment)
- **SQLite not for high concurrency** (single-user optimized)

---

## 10. Code Review Priorities

When reviewing this codebase, focus on:

1. **Provider/API key handling**: Are keys properly masked in logs/responses?
2. **Privacy Guard completeness**: Are all PII types covered?
3. **Task execution safety**: Is sandboxing robust?
4. **Memory consent flow**: Is user consent clear and enforceable?
5. **Public/private split**: Is closed-core strategy clearly documented?
6. **Error handling**: Are edge cases (network failure, malformed input) handled?
7. **Performance**: Can it handle 100+ skills without slowdown?
8. **Test coverage**: Are critical paths tested?

---

## 11. Architecture Principles

1. **Local-first**: Process locally before calling external APIs
2. **User-owned**: Memory, keys, and execution logs belong to the user
3. **Platform-agnostic**: Not locked to any model provider or cloud service
4. **Privacy by design**: Minimal data collection, explicit consent
5. **Extensible**: Skills and tools can be added without core changes
6. **Transparent**: User can inspect memory, logs, and decisions

---

## 12. Glossary

- **Agent Kernel**: The core reasoning and orchestration engine
- **Provider**: An external API endpoint (e.g., OpenAI, Anthropic, custom)
- **Skill**: A domain-specific capability (e.g., web-search, APK analysis)
- **Tool**: A primitive action (e.g., file read, web navigate)
- **Memory**: User profile, conversation history, learned patterns
- **Privacy Guard**: PII detection and consent enforcement module
- **MCP**: Model Context Protocol (standard for external integrations)

---

**End of Architecture Document**

For code review, start with:
- `server/agent_kernel_v4.py` (core loop)
- `server/core/provider_registry.py` (provider management)
- `server/core/secret_store.py` (key storage)
- `server/core/privacy_guard.py` (PII detection)
- `web/index.html` (frontend entry point)

Questions? Open an issue or contact the team.
