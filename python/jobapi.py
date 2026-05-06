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
    # 1. 配置参数
    AK = "019D904314737A4F9B78334BCDC99943"
    SK = "019D904314737A3888F45A6B5B36F857"
    
    # 【修改点 1】: 将路径末尾的 virtualClusters 替换为 jobs (或 volcanoJobs)
    # 如果你想直接通过名字过滤，可以在参数里加上 name (具体看你们 API 的支持情况)
    # URL = "https://management.d.pjlab.org.cn/compute/ecp/v1/subscriptions/0198ef76-1a3f-7c0a-b9c4-84faf93fa2ce/resourceGroups/default/regions/cn-pj-01/jobs?name=muxi-mattersim-tester-lbmfg"
    
    # 这里我们先请求前 100 个任务看看数据结构
    URL = "https://management.d.pjlab.org.cn/compute/ecp/v1/subscriptions/0198ef76-1a3f-7c0a-b9c4-84faf93fa2ce/resourceGroups/default/regions/cn-pj-01/jobs?limit=100"

    # 2. 发起请求
    headers = generate_auth_headers(URL, "GET", AK, SK)
    resp = requests.get(URL, headers=headers)

    # 3. 获取完整数据
    if resp.status_code == 200:
        data = resp.json()
        
        # 打印完整的漂亮格式 JSON，