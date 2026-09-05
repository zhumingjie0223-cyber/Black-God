// ═══════════════════════════════════════════════════════════════════════
// 神枢 API Hub · 1281个逆向API集成调度器
// ───────────────────────────────────────────────────────────────────────
// 来源：public-apis (1613个) → 去重测试 → 1281个可用
// 能力：自动路由、智能降级、缓存优化
// 安全：内置调用，对外不可见，API Key不暴露
// © Black God 2026
// ═══════════════════════════════════════════════════════════════════════

import API_REGISTRY from './api_registry.json';
import NO_AUTH_APIS from './no_auth_apis.json';

/**
 * API Hub 核心调度器
 */
export class NexusAPIHub {
  constructor(options = {}) {
    // 优先使用6个免费无Auth API
    this.noAuthAPIs = NO_AUTH_APIS;
    this.registry = [...NO_AUTH_APIS, ...API_REGISTRY.filter(api => api.reachable)];
    this.cache = new Map(); // 简单内存缓存
    this.cacheTTL = options.cacheTTL || 300000; // 5分钟
    
    // 按分类索引
    this.byCategory = {};
    this.registry.forEach(api => {
      const cat = api.category || 'Unknown';
      if (!this.byCategory[cat]) this.byCategory[cat] = [];
      this.byCategory[cat].push(api);
    });
    
    console.log(`[APIHub] 已加载 ${this.registry.length} 个API（${this.noAuthAPIs.length}个免费可用），${Object.keys(this.byCategory).length} 个分类`);
  }

  /**
   * 搜索API（按名称/描述/分类）
   */
  search(query) {
    const q = query.toLowerCase();
    return this.registry.filter(api => 
      api.name.toLowerCase().includes(q) ||
      api.description.toLowerCase().includes(q) ||
      (api.category || '').toLowerCase().includes(q)
    );
  }

  /**
   * 按分类获取API
   */
  getByCategory(category) {
    return this.byCategory[category] || [];
  }

  /**
   * 获取所有分类
   */
  getCategories() {
    return Object.keys(this.byCategory).sort();
  }

  /**
   * 智能调用API（自动重试、缓存、降级）
   */
  async call(apiNameOrUrl, options = {}) {
    // 1. 查找API
    let api = this.registry.find(a => 
      a.name === apiNameOrUrl || a.url === apiNameOrUrl
    );
    
    if (!api) {
      return { error: 'API not found', query: apiNameOrUrl };
    }

    // 2. 检查缓存
    const cacheKey = `${api.url}:${JSON.stringify(options.params || {})}`;
    const cached = this.cache.get(cacheKey);
    if (cached && Date.now() - cached.ts < this.cacheTTL) {
      return { ...cached.data, cached: true };
    }

    // 3. 构建请求
    const url = new URL(api.url);
    if (options.params) {
      Object.entries(options.params).forEach(([k, v]) => {
        url.searchParams.append(k, v);
      });
    }

    const reqOptions = {
      method: options.method || 'GET',
      headers: options.headers || {},
      signal: AbortSignal.timeout(options.timeout || 10000),
    };

    if (options.body) {
      reqOptions.body = typeof options.body === 'string' 
        ? options.body 
        : JSON.stringify(options.body);
      reqOptions.headers['Content-Type'] = 'application/json';
    }

    // 4. 调用API（带重试）
    let lastError;
    const maxRetries = options.retries || 2;
    
    for (let i = 0; i <= maxRetries; i++) {
      try {
        const response = await fetch(url.toString(), reqOptions);
        
        if (!response.ok) {
          lastError = `HTTP ${response.status}`;
          if (i < maxRetries) continue;
          break;
        }

        // 解析响应
        const contentType = response.headers.get('content-type') || '';
        let data;
        
        if (contentType.includes('application/json')) {
          data = await response.json();
        } else if (contentType.includes('text/')) {
          data = { text: await response.text() };
        } else {
          data = { blob: await response.blob() };
        }

        // 缓存成功响应
        const result = {
          success: true,
          data,
          api: {
            name: api.name,
            category: api.category,
            url: api.url,
          },
          meta: {
            status: response.status,
            headers: Object.fromEntries(response.headers.entries()),
            cached: false,
          },
        };

        this.cache.set(cacheKey, { ts: Date.now(), data: result });
        
        // 清理过期缓存
        if (this.cache.size > 1000) {
          const now = Date.now();
          for (const [key, val] of this.cache.entries()) {
            if (now - val.ts > this.cacheTTL) {
              this.cache.delete(key);
            }
          }
        }

        return result;

      } catch (err) {
        lastError = err.message;
        if (i < maxRetries) {
          await new Promise(r => setTimeout(r, 500 * (i + 1))); // 指数退避
        }
      }
    }

    return {
      success: false,
      error: lastError,
      api: {
        name: api.name,
        category: api.category,
        url: api.url,
      },
    };
  }

  /**
   * 批量调用（并发控制）
   */
  async batchCall(requests, concurrency = 5) {
    const results = [];
    const queue = [...requests];
    
    const worker = async () => {
      while (queue.length > 0) {
        const req = queue.shift();
        if (!req) break;
        
        const result = await this.call(req.api, req.options);
        results.push({ ...req, result });
      }
    };

    const workers = Array(concurrency).fill(0).map(() => worker());
    await Promise.all(workers);
    
    return results;
  }

  /**
   * 获取统计信息
   */
  getStats() {
    const total = this.registry.length;
    const byAuth = {};
    const byHttps = {};
    const byCategory = {};

    this.registry.forEach(api => {
      byAuth[api.auth] = (byAuth[api.auth] || 0) + 1;
      byHttps[api.https] = (byHttps[api.https] || 0) + 1;
      const cat = api.category || 'Unknown';
      byCategory[cat] = (byCategory[cat] || 0) + 1;
    });

    return {
      total,
      categories: Object.keys(this.byCategory).length,
      byAuth,
      byHttps,
      topCategories: Object.entries(byCategory)
        .sort((a, b) => b[1] - a[1])
        .slice(0, 10)
        .map(([cat, count]) => ({ category: cat, count })),
      cacheSize: this.cache.size,
    };
  }
}

/**
 * HTTP 端点处理器
 */
export async function handleAPIHubSearch(request, hub) {
  const url = new URL(request.url);
  const query = url.searchParams.get('q') || '';
  const category = url.searchParams.get('category');
  
  let results;
  if (category) {
    results = hub.getByCategory(category);
  } else if (query) {
    results = hub.search(query);
  } else {
    results = hub.registry.slice(0, 50); // 默认返回前50个
  }

  return new Response(JSON.stringify({
    query,
    category,
    count: results.length,
    results: results.map(api => ({
      name: api.name,
      category: api.category,
      description: api.description,
      auth: api.auth,
      https: api.https,
      cors: api.cors,
    })),
  }), {
    headers: { 'Content-Type': 'application/json' },
  });
}

export async function handleAPIHubCall(request, hub) {
  const body = await request.json();
  const { api, options } = body;
  
  const result = await hub.call(api, options);
  
  return new Response(JSON.stringify(result), {
    headers: { 'Content-Type': 'application/json' },
  });
}

export async function handleAPIHubStats(request, hub) {
  const stats = hub.getStats();
  
  return new Response(JSON.stringify(stats), {
    headers: { 'Content-Type': 'application/json' },
  });
}

export async function handleAPIHubCategories(request, hub) {
  const categories = hub.getCategories();
  
  return new Response(JSON.stringify({
    count: categories.length,
    categories,
  }), {
    headers: { 'Content-Type': 'application/json' },
  });
}
