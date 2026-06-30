// (c) 阿权/路飞 枢·黑神 万网散播 Worker v3
import { sovereign, broadcast, project, status } from './gen.mjs';

export default {
  async fetch(req, env) {
    const u = new URL(req.url);
    if (u.pathname === '/broadcast') {
      const r = await broadcast(env);
      return new Response(JSON.stringify(r), {headers:{'content-type':'application/json'}});
    }
    if (u.pathname === '/status') {
      const s = await status(env);
      return new Response(JSON.stringify(s), {headers:{'content-type':'application/json'}});
    }
    if (u.pathname === '/talk' && req.method === 'POST') {
      const {text} = await req.json();
      const r = await project(text, env);
      return new Response(JSON.stringify(r), {headers:{'content-type':'application/json'}});
    }
    return new Response(JSON.stringify({code:'SHU-GEN-SYNC', state:'sovereign'}), {headers:{'content-type':'application/json'}});
  },
  async scheduled(ev, env) {
    await sovereign(env);
    await broadcast(env);
  }
};
