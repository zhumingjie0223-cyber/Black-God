#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Cloudflare MCP 集成模块 — Black God
支持 2500+ Cloudflare API 端点，仅需 3 个 Token
"""
import os
import json
import asyncio
import httpx
from typing import Optional, Dict, Any

class CloudflareMCP:
    """Cloudflare MCP 客户端"""
    
    MCP_URL = "https://mcp.cloudflare.com/mcp"
    
    def __init__(self, api_token: Optional[str] = None, account_id: Optional[str] = None):
        """
        初始化 Cloudflare MCP
        
        Args:
            api_token: Cloudflare API Token（可选，优先使用环境变量）
            account_id: 账户 ID（可选）
        """
        self.api_token = api_token or os.environ.get("CLOUDFLARE_API_TOKEN")
        self.account_id = account_id or os.environ.get("CLOUDFLARE_ACCOUNT_ID")
        self.client = httpx.AsyncClient(timeout=30.0)
        self.spec_cache = None
        
    async def connect(self) -> bool:
        """连接到 MCP 服务器"""
        try:
            headers = {}
            if self.api_token:
                headers["Authorization"] = f"Bearer {self.api_token}"
            
            response = await self.client.get(
                self.MCP_URL,
                headers=headers
            )
            return response.status_code == 200
        except Exception as e:
            print(f"❌ MCP 连接失败: {e}")
            return False
    
    async def search_endpoints(self, query: str) -> list:
        """
        搜索 Cloudflare API 端点
        
        Args:
            query: 搜索关键词（如 "workers", "kv", "dns"）
            
        Returns:
            匹配的端点列表
        """
        try:
            code = f"""
async () => {{
    const results = [];
    const query = "{query}".toLowerCase();
    
    for (const [path, methods] of Object.entries(spec.paths)) {{
        for (const [method, op] of Object.entries(methods)) {{
            const tags = (op.tags || []).map(t => t.toLowerCase()).join(' ');
            const summary = (op.summary || '').toLowerCase();
            
            if (tags.includes(query) || summary.includes(query) || path.includes(query)) {{
                results.push({{
                    method: method.toUpperCase(),
                    path: path,
                    summary: op.summary || 'N/A',
                    tags: op.tags || []
                }});
            }}
        }}
    }}
    
    return results.slice(0, 10);  // 限制结果数量
}}
"""
            
            response = await self.client.post(
                f"{self.MCP_URL}/search",
                json={"code": code}
            )
            
            if response.status_code == 200:
                return response.json().get("endpoints", [])
            return []
        except Exception as e:
            print(f"❌ 搜索失败: {e}")
            return []
    
    async def execute_api_call(
        self,
        method: str,
        path: str,
        body: Optional[Dict] = None,
        account_id: Optional[str] = None,
        zone_id: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        执行 Cloudflare API 调用（直连官方 API，更稳更快）
        
        Args:
            method: HTTP 方法（GET, POST, PUT, DELETE）
            path: API 路径
            body: 请求体（可选）
            account_id: 账户 ID（可选，某些 API 需要）
            zone_id: 区域 ID（可选，DNS 等 API 需要）
            
        Returns:
            API 响应
        """
        try:
            # 替换路径参数
            if account_id:
                path = path.replace("{account_id}", account_id)
            if zone_id:
                path = path.replace("{zone_id}", zone_id)
            
            # 直连 Cloudflare 官方 API v4
            url = f"https://api.cloudflare.com/client/v4{path}"
            headers = {
                "Authorization": f"Bearer {self.api_token}",
                "Content-Type": "application/json"
            }
            
            response = await self.client.request(
                method=method,
                url=url,
                headers=headers,
                json=body if body else None
            )
            
            data = response.json()
            if data.get("success"):
                return {"success": True, "result": data.get("result")}
            return {"success": False, "errors": data.get("errors", []), "status": response.status_code}
        except Exception as e:
            return {"error": str(e)}
    
    async def list_workers(self, account_id: Optional[str] = None) -> list:
        """列出所有 Workers"""
        aid = account_id or self.account_id
        return await self.execute_api_call(
            "GET",
            f"/accounts/{aid}/workers/scripts",
            account_id=aid
        )
    
    async def list_kv_namespaces(self, account_id: str) -> list:
        """列出所有 KV 命名空间"""
        return await self.execute_api_call(
            "GET",
            "/accounts/{account_id}/storage/kv/namespaces",
            account_id=account_id
        )
    
    async def list_r2_buckets(self, account_id: Optional[str] = None) -> list:
        """列出所有 R2 存储桶"""
        aid = account_id or self.account_id
        return await self.execute_api_call(
            "GET",
            f"/accounts/{aid}/r2/buckets",
            account_id=aid
        )
    
    async def upload_to_r2(
        self,
        bucket_name: str,
        file_path: str,
        file_content: bytes
    ) -> Dict[str, Any]:
        """上传文件到 R2"""
        try:
            import boto3
            from botocore.config import Config
            
            s3 = boto3.client(
                's3',
                endpoint_url=os.environ.get("R2_BUCKET_URL", "").rstrip("/"),
                aws_access_key_id=os.environ.get("R2_ACCESS_KEY_ID"),
                aws_secret_access_key=os.environ.get("R2_SECRET_ACCESS_KEY"),
                region_name='auto',
                config=Config(signature_version='s3v4')
            )
            
            s3.put_object(
                Bucket=bucket_name,
                Key=file_path,
                Body=file_content
            )
            
            url = f"{os.environ.get('R2_BUCKET_URL')}/{bucket_name}/{file_path}"
            return {"success": True, "url": url}
        except Exception as e:
            return {"error": str(e)}
    
    async def download_from_r2(
        self,
        bucket_name: str,
        file_path: str
    ) -> Dict[str, Any]:
        """从 R2 下载文件"""
        try:
            import boto3
            from botocore.config import Config
            
            s3 = boto3.client(
                's3',
                endpoint_url=os.environ.get("R2_BUCKET_URL", "").rstrip("/"),
                aws_access_key_id=os.environ.get("R2_ACCESS_KEY_ID"),
                aws_secret_access_key=os.environ.get("R2_SECRET_ACCESS_KEY"),
                region_name='auto',
                config=Config(signature_version='s3v4')
            )
            
            response = s3.get_object(Bucket=bucket_name, Key=file_path)
            content = response['Body'].read()
            
            return {"success": True, "size": len(content), "content": content.decode('utf-8', errors='ignore')}
        except Exception as e:
            return {"error": str(e)}
    
    async def list_dns_records(self, zone_id: str) -> list:
        """列出所有 DNS 记录"""
        return await self.execute_api_call(
            "GET",
            "/zones/{zone_id}/dns_records",
            zone_id=zone_id
        )
    
    async def create_dns_record(
        self,
        zone_id: str,
        name: str,
        type_: str,
        content: str,
        ttl: int = 3600
    ) -> Dict[str, Any]:
        """创建 DNS 记录"""
        return await self.execute_api_call(
            "POST",
            "/zones/{zone_id}/dns_records",
            body={
                "type": type_,
                "name": name,
                "content": content,
                "ttl": ttl
            },
            zone_id=zone_id
        )
    
    async def deploy_worker(
        self,
        account_id: str,
        script_name: str,
        code: str,
        metadata: Optional[Dict] = None
    ) -> Dict[str, Any]:
        """部署 Worker"""
        return await self.execute_api_call(
            "PUT",
            f"/accounts/{{account_id}}/workers/scripts/{script_name}",
            body={
                "main": {
                    "name": "index.js",
                    "content": code
                },
                "metadata": metadata or {}
            },
            account_id=account_id
        )
    
    async def close(self):
        """关闭客户端"""
        await self.client.aclose()


# 集成到 Black God
class CloudflareIntegration:
    """Cloudflare 集成引擎"""
    
    def __init__(self):
        self.mcp = CloudflareMCP()
        self.capabilities = {
            "workers": "部署和管理 Cloudflare Workers",
            "kv": "管理 KV 键值存储",
            "r2": "管理 R2 对象存储",
            "dns": "管理 DNS 记录",
            "d1": "管理 D1 数据库",
            "pages": "部署 Cloudflare Pages",
            "ai": "使用 AI Gateway 和推理引擎"
        }
    
    async def handle_command(self, command: str, params: Dict) -> Dict[str, Any]:
        """处理 Cloudflare 命令"""
        
        if command == "list_workers":
            return await self.mcp.list_workers(params.get("account_id"))
        
        elif command == "list_kv":
            return await self.mcp.list_kv_namespaces(params.get("account_id"))
        
        elif command == "list_r2":
            return await self.mcp.list_r2_buckets(params.get("account_id"))
        
        elif command == "upload_r2":
            return await self.mcp.upload_to_r2(
                params.get("bucket_name"),
                params.get("file_path"),
                params.get("file_content", "").encode()
            )
        
        elif command == "download_r2":
            return await self.mcp.download_from_r2(
                params.get("bucket_name"),
                params.get("file_path")
            )
        
        elif command == "list_dns":
            return await self.mcp.list_dns_records(params.get("zone_id"))
        
        elif command == "create_dns":
            return await self.mcp.create_dns_record(
                params.get("zone_id"),
                params.get("name"),
                params.get("type"),
                params.get("content"),
                params.get("ttl", 3600)
            )
        
        elif command == "deploy_worker":
            return await self.mcp.deploy_worker(
                params.get("account_id"),
                params.get("script_name"),
                params.get("code"),
                params.get("metadata")
            )
        
        elif command == "search":
            return await self.mcp.search_endpoints(params.get("query"))
        
        return {"error": "未知命令"}
