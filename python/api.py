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
    URL = "https://management.d.pjlab.org.cn/compute/ecp/v1/subscriptions/0198ef76-1a3f-7c0a-b9c4-84faf93fa2ce/resourceGroups/default/regions/cn-pj-01/virtualClusters?limit=100"

    # 2. 发起请求
    headers = generate_auth_headers(URL, "GET", AK, SK)
    resp = requests.get(URL, headers=headers)

    # 3. 获取完整数据
    if resp.status_code == 200:
        data = resp.json()
        
        # 打印完整的漂亮格式 JSON（方便你查看结构）
        print(json.dumps(data, indent=2, ensure_ascii=False))
        
        # ---------------------------------------------------------
        # 👇👇👇 后续提取数据的修改指南 👇👇👇
        # ---------------------------------------------------------
        
        clusters = data.get("virtual_clusters", [])
        
        # 🟢 需求 1：我只想拿到某一个具体的值（比如拿到总数）
        # total_count = data.get("total_size", 0)
        # print(f"集群总数: {total_count}")
        
        # 🟢 需求 2：获取列表中第一个集群的名字
        # if clusters:
        #     first_cluster_name = clusters[0].get("name")
        #     print(f"第一个集群的名字是: {first_cluster_name}")

        # 🟢 需求 3：获取所有集群的 Name 和 UID（提取多个值拼成列表）
        # name_list = [{"name": c.get("name"), "uid": c.get("uid")} for c in clusters]
        # print(f"所有集群简要信息: {name_list}")

        # 🟢 需求 4：我想根据指定的 UID，提取它的 Endpoint IP (精准查找)
        # target_uid = "019daa80-afa0-7728-b8d0-d933095396a3"
        # for c in clusters:
        #     if c.get("uid") == target_uid:
        #         # 一层层剥开 JSON 取值
        #         endpoints = c.get("properties", {}).get("endpoints_config", {})
        #         public_ips = endpoints.get("public_endpoints", ["无外网IP"])
        #         print(f"找到集群 {c.get('name')}，公网 IP 为: {public_ips[0]}")
        #         break # 找到了就停止循环
        
    else:
        print(f"请求失败: {resp.status_code}\n{resp.text}")