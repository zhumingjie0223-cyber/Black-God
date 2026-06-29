// Black God 888 Cloudflare Worker
// 集成 Claude Opus 4.8 4.7 + Legend Coordinator v2

const ANTHROPIC_API_KEY = "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";
const LEGEND_API_URL = "http://47.236.124.97/v1";
const LEGEND_API_KEY = "sk-local";

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    
    // CORS 处理
    if (request.method === 'OPTIONS') {
      return new Response(null, {
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type, Authorization',
        }
      });
    }

    // 路由：/v1/chat/completions
    if (url.pathname === '/v1/chat/completions') {
      return handleChatCompletion(request);
    }

    // 路由：/health
    if (url.pathname === '/health') {
      return new Response(JSON.stringify({
        status: 'ok',
        service: 'Black God 888',
        models: ['claude-opus-4-8', 'auto'],
        timestamp: new Date().toISOString()
      }), {
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // 默认路由
    return new Response('Black God 888 API - Ready', {
      headers: { 'Content-Type': 'text/plain' }
    });
  }
};

async function handleChatCompletion(request) {
  try {
    const body = await request.json();
    const model = body.model || 'claude-opus-4-8';
    
    // 优先使用 Legend Coordinator（内置 claude-opus-4-8）
    if (model === 'auto' || model.includes('auto')) {
      return await callLegendAPI(body);
    }
    
    // 直接调用 Anthropic
    if (model.includes('claude')) {
      return await callAnthropicAPI(body);
    }

    return new Response(JSON.stringify({
      error: 'Unsupported model',
      supported: ['claude-opus-4-8', 'auto']
    }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' }
    });

  } catch (error) {
    return new Response(JSON.stringify({
      error: error.message
    }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
}

async function callAnthropicAPI(body) {
  const response = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-api-key': ANTHROPIC_API_KEY,
      'anthropic-version': '2023-06-01'
    },
    body: JSON.stringify({
      model: body.model || 'claude-opus-4-20250514',
      max_tokens: body.max_tokens || 4096,
      messages: body.messages
    })
  });

  const data = await response.json();
  
  return new Response(JSON.stringify(data), {
    status: response.status,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*'
    }
  });
}

async function callLegendAPI(body) {
  const response = await fetch(`${LEGEND_API_URL}/chat/completions`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${LEGEND_API_KEY}`
    },
    body: JSON.stringify({
      model: 'auto',
      messages: body.messages,
      max_tokens: body.max_tokens || 4096,
      temperature: body.temperature || 0.7
    })
  });

  const data = await response.json();
  
  return new Response(JSON.stringify(data), {
    status: response.status,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*'
    }
  });
}
