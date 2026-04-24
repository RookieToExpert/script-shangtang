import hmac
import hashlib
import base64
import requests
import json
from datetime import datetime, timezone
from urllib.parse import urlparse

def hmac_sha256(secret, message):
    """计算 HMAC-SHA256 签名并返回 Base64 编码字符串"""
    key = secret.encode('utf-8')
    msg = message.encode('utf-8')
    signature = hmac.new(key, msg, digestmod=hashlib.sha256).digest()
    return base64.b64encode(signature).decode('utf-8')

def generate_auth_headers(req_url, method, access_key, secret_key):
    """根据 HTTP Signatures 规范生成鉴权 Headers"""
    now = datetime.now(timezone.utc)
    # 严格遵循文档的 Date 格式
    str_date_now = now.strftime('%a, %d %b %Y %H:%M:%S GMT')

    parsed_url = urlparse(req_url)
    path = parsed_url.path
    if parsed_url.query:
        path += "?" + parsed_url.query
    host = parsed_url.netloc

    # 构造待签名字符串
    str_headers = "date host @request-target"
    str_date = f"date: {str_date_now}"
    str_host = f"host: {host}"
    str_request_target = f"@request-target: {method.lower()} {path}"

    str_sign_content = "\n".join([str_date, str_host, str_request_target])
    str_signature = hmac_sha256(secret_key, str_sign_content)

    str_authorization = (
        f'hmac accesskey="{access_key}", '
        f'algorithm="hmac-sha256", '
        f'headers="{str_headers}", '
        f'signature="{str_signature}"'
    )

    return {
        "Date": str_date_now,
        "Host": host,
        "Authorization": str_authorization,
        "Accept": "application/json"
    }

def main():
    # 1. 凭证信息
    str_ak_id = "019D904314737A4F9B78334BCDC99943"
    str_ak_secret = "019D904314737A3888F45A6B5B36F857"
    target_uid = "019daa80-afa0-7728-b8d0-d933095396a3"

    # 2. 目标 API 地址
    # 建议先去掉复杂的路径过滤，或者尝试增加 limit
    target_url = "https://management.d.pjlab.org.cn/compute/ecp/v1/subscriptions/0198ef76-1a3f-7c0a-b9c4-84faf93fa2ce/resourceGroups/default/regions/cn-pj-01/virtualClusters?limit=100"

    print(f"🚀 正在请求: {target_url}\n")
    headers = generate_auth_headers(target_url, "GET", str_ak_id, str_ak_secret)

    try:
        resp = requests.get(target_url, headers=headers)

        if resp.status_code == 200:
            data = resp.json()
            clusters = data.get("virtual_clusters", [])

            # 增强诊断：打印原始响应的关键结构
            print(f"✅ 鉴权成功！")
            print(f"📊 响应包含 items 数量: {len(clusters)}")

            if len(clusters) == 0:
                print("⚠️ 列表为空。这通常意味着该 Region/Subscription 下没有资源。")
                print("📝 原始响应内容如下（用于排查字段名）:")
                print(json.dumps(data, indent=2, ensure_ascii=False))
            else:
                # 寻找目标 UID
                found = next((c for c in clusters if c.get('uid') == target_uid), None)
                if found:
                    print(f"\n🎯 匹配成功！Name: {found.get('name')}")
                else:
                    print(f"\n❌ 未在当前列表中找到 UID: {target_uid}")
                    print("当前列表中的 UID 如下:")
                    for c in clusters:
                        print(f"- {c.get('name')}: {c.get('uid')}")
        else:
            print(f"❌ 请求失败: {resp.status_code}")
            print(resp.text)

    except Exception as e:
        print(f"🚫 发生异常: {e}")

if __name__ == "__main__":
    main()