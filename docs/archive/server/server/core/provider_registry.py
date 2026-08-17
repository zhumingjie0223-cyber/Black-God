"""
Provider Registry - Provider 注册表和默认管理
- 管理多个 Provider（Claude Max / OpenAI / Custom）
- 设置默认 Provider
- 质量优先级排序
- 状态跟踪
"""
import json
from pathlib import Path
from .secret_store import load_provider, load_provider_with_key, list_providers, save_provider, delete_provider

DATA_DIR = Path(__file__).parent.parent / 'data'
REGISTRY_FILE = DATA_DIR / 'provider_registry.json'

def get_registry():
    """读取 Provider 注册表"""
    if not REGISTRY_FILE.exists():
        return {'default': None, 'providers': {}}
    return json.loads(REGISTRY_FILE.read_text())

def save_registry(registry):
    """保存注册表"""
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    REGISTRY_FILE.write_text(json.dumps(registry, indent=2))

def register_provider(provider_id, meta):
    """
    注册 Provider
    meta: {
      'label': 'Claude Max Official',
      'type': 'anthropic_oauth',
      'base_url': 'https://api.anthropic.com/v1',
      'model': 'claude-sonnet-4-5-20250929',
      'quality_mode': 'max',
      'priority': 100,
      'enabled': True
    }
    """
    registry = get_registry()
    registry['providers'][provider_id] = meta
    save_registry(registry)
    return True

def set_default_provider(provider_id):
    """设置默认 Provider"""
    registry = get_registry()
    if provider_id not in registry['providers']:
        return False
    registry['default'] = provider_id
    save_registry(registry)
    return True

def get_default_provider(reveal_secret=False):
    """获取默认 Provider（含完整配置）"""
    registry = get_registry()
    default_id = registry.get('default')
    if not default_id:
        return None
    
    # 合并 meta + secret
    meta = registry['providers'].get(default_id, {})
    if reveal_secret:
        secret = load_provider_with_key(default_id)
    else:
        secret = load_provider(default_id)
    if not secret:
        return None
    
    return {**meta, **secret, 'id': default_id}

def list_all_providers(reveal_secret=False):
    """列出所有 Provider（meta + secret 合并）"""
    registry = get_registry()
    result = []
    for pid, meta in registry['providers'].items():
        if reveal_secret:
            secret = load_provider_with_key(pid) or {}
        else:
            secret = load_provider(pid) or {}
        result.append({**meta, **secret, 'id': pid})
    return result

def unregister_provider(provider_id):
    """注销 Provider"""
    registry = get_registry()
    if provider_id in registry['providers']:
        del registry['providers'][provider_id]
    if registry.get('default') == provider_id:
        registry['default'] = None
    save_registry(registry)
    delete_provider(provider_id)
    return True

if __name__ == '__main__':
    print('=== Provider Registry Self Test ===')
    from secret_store import save_provider as save_secret
    
    # 注册一个 Provider
    save_secret('test_claude', {'token': 'sk-ant-test123', 'base_url': 'https://api.anthropic.com/v1'})
    register_provider('test_claude', {
        'label': 'Test Claude',
        'type': 'anthropic',
        'model': 'claude-sonnet-4-5',
        'priority': 100,
        'enabled': True
    })
    print('✅ registered')
    
    # 设为默认
    set_default_provider('test_claude')
    default = get_default_provider(reveal_secret=False)
    print(f"✅ default: {default['label']}, token={default.get('token','N/A')}")
    
    # 列表
    all_p = list_all_providers()
    print(f"✅ list: {[p['id'] for p in all_p]}")
    
    # 注销
    unregister_provider('test_claude')
    print('✅ unregistered')
