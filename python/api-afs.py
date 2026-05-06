import hmac
import hashlib
import base64
import requests
import json
from datetime import datetime, timezone
from urllib.parse import urlparse

def hmac_sha256(secret, message):
    """计算 HMAC-SHA256 签名并返回 Base64 编码字符串"""
    return base64.b64encode(hmac.new(secret.encode('utf-8'), message.encode('utf-8'), hashlib.sha256).digest()).decode('utf-8')

def generate_auth_headers(req_url, method, access_key, secret_key):
    """生成 SenseCore 标准 HTTP Signatures 鉴权头"""
    str_date_now = datetime.now(timezone.utc).strftime('%a, %d %b %Y %H:%M:%S GMT')
    parsed_url = urlparse(req_url)
    
    # 注意：签名时的 path 必须包含 query 部分，且保持原始编码或解析一致
    path = parsed_url.path + ("?" + parsed_url.query if parsed_url.query else "")
    host = parsed_url.netloc

    str_sign_content = f"date: {str_date_now}\nhost: {host}\n@request-target: {method.lower()} {path}"
    str_signature = hmac_sha256(secret_key, str_sign_content)

    return {
        "Date": str_date_now,
        "Host": host,
        "Accept": "application/json",
        "Authorization": f'hmac accesskey="{access_key}", algorithm="hmac-sha256", headers="date host @request-target", signature="{str_signature}"'
    }

# ================= 核心执行逻辑 =================
if __name__ == "__main__":
    # 1. 配置参数 (请替换为你真实的 AK/SK)
    AK = "019D904314737A4F9B78334BCDC99943" 
    SK = "019D904314737A3888F45A6B5B36F857"
    
    # 2. 新的接口地址
    URL = "https://management.d.pjlab.org.cn/rmh/v1/resources:page?filter=resource_type%3D%22storage.afs.v1.volume%22%20OR%20resource_type%3D%22storage.afs.v2.volume%22%20%20AND%20uid%3D%22%2A7933-bf7e-8069aa9851b0%2A%22%20AND%20zone%3D%22%2Acn-pj-01a%2A%22&page_size=10&page_token=1"

    # 3. 发起请求
    headers = generate_auth_headers(URL, "POST", AK, SK)
    
    # 【新增】：显式声明我们发送的是 JSON 格式
    headers["Content-Type"] = "application/json"
    
    # 【修改】：使用 json={} 发送一个空的 JSON 请求体
    resp = requests.post(URL, headers=headers, json={})

    # 4. 获取并解析数据
    if resp.status_code == 200:
        data = resp.json()
        print("请求成功，返回数据如下：")
        print(json.dumps(data, indent=2, ensure_ascii=False))
        
        # --- 数据提取指南 ---
        resources = data.get("resources", [])
        
        if not resources:
            print("未找到符合条件的资源。")
        else:
            for item in resources:
                name = item.get("name")
                uid = item.get("uid")
                r_type = item.get("resource_type")
                print(f"资源名称: {name} | UID: {uid} | 类型: {r_type}")
                
        # 如果有分页，可以获取 next_page_token
        next_token = data.get("next_page_token")
        if next_token:
            print(f"\n后续页码 Token: {next_token}")

    else:
        print(f"请求失败: {resp.status_code}")
        print(f"错误详情: {resp.text}")