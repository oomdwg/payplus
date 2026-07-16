from flask import Flask, request, jsonify
from flask import send_file
from flask_cors import CORS
from curl_cffi import requests as cf_requests
import httpx
import calendar
import json
import os
import uuid
from datetime import datetime





app = Flask(__name__)
CORS(app)

TOKEN_STORE = {}

COUNTRY_CURRENCY = {
    'PH': 'PHP', 'US': 'USD', 'GB': 'GBP', 'JP': 'JPY',
    'SG': 'SGD', 'AU': 'AUD', 'CA': 'CAD',
    'DE': 'EUR', 'FR': 'EUR', 'IN': 'INR', 'BR': 'BRL',
    'MX': 'MXN', 'KR': 'KRW', 'TW': 'TWD', 'HK': 'HKD',
    'TR': 'TRY',
}

COUNTRY_INFO = {
    'PH': '菲律宾比索（菲律宾）', 'US': '美元（美国）',
    'GB': '英镑（英国）',         'JP': '日元（日本）',
    'SG': '新加坡元（新加坡）',   'AU': '澳大利亚元（澳大利亚）',
    'CA': '加拿大元（加拿大）',   'DE': '欧元（德国）',
    'FR': '欧元（法国）',         'IN': '印度卢比（印度）',
    'BR': '巴西雷亚尔（巴西）',   'MX': '墨西哥比索（墨西哥）',
    'KR': '韩元（韩国）',         'TW': '新台币（台湾）',
    'HK': '港币（香港）',         'TR': '土耳其里拉（土耳其）',
}

HEADERS_BASE = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Origin': 'https://chatgpt.com',
    'Referer': 'https://chatgpt.com/',
}



def make_headers(access_token, session_token=None, extra=None):
    h = {**HEADERS_BASE, 'Authorization': f'Bearer {access_token}'}
    if session_token:
        h['Cookie'] = f'__Secure-next-auth.session-token={session_token}'
    if extra:
        h.update(extra)
    return h

def get_subscription_info(access_token, session_token, token_data):
    """调 OpenAI 接口获取订阅信息"""
    url = 'https://chatgpt.com/backend-api/accounts/check/v4-2023-04-27'
    res = cf_requests.get(url, headers=make_headers(access_token, session_token), timeout=20, impersonate='chrome116')

    if res.status_code != 200:
        return None

    raw = res.json()
    account_id = token_data.get('account', {}).get('id', '')
    accounts = raw.get('accounts', {})
    account_obj = accounts.get(account_id) or (list(accounts.values())[0] if accounts else {})

    entitlement = account_obj.get('entitlement', {})
    account_info = account_obj.get('account', {})

    is_active = entitlement.get('has_active_subscription', False)
    plan_type = account_info.get('plan_type') or token_data.get('account', {}).get('planType', 'free')

    raw_expire = entitlement.get('expires_at', '')
    start_str = expire_str = '-'

    try:
        dt_expire = datetime.fromisoformat(raw_expire.replace('Z', '+00:00'))
        expire_str = dt_expire.strftime('%Y-%m-%d %H:%M:%S')
        year, month = dt_expire.year, dt_expire.month
        new_month = month - 1 if month > 1 else 12
        new_year = year if month > 1 else year - 1
        import calendar as cal
        day = min(dt_expire.day, cal.monthrange(new_year, new_month)[1])
        start_str = dt_expire.replace(year=new_year, month=new_month, day=day).strftime('%Y-%m-%d %H:%M:%S')
    except:
        pass

    # 邮箱从 token_data 里取
    email = token_data.get('user', {}).get('email', '-')

    return {
        'email':         email,
        'account_type':  plan_type if is_active else 'free',
        'start_time':    start_str if is_active else '-',
        'expire_time':   expire_str if is_active else '-',
        'currency':      entitlement.get('billing_currency', '-'),
        'payment_cycle': entitlement.get('billing_period', 'monthly'),
        'auto_renew':    False,
        'is_delinquent': entitlement.get('is_delinquent', False),
        'payChannelType': 1,
        'seats_used':    1,
        'seats_total':   1,
        'expires_at':    raw_expire or None,
    }


@app.route('/')
def index():
    # 增加一个 '..' 代表退回上一级目录（根目录）
    return send_file(os.path.join(os.path.dirname(__file__), '..', 'index.html'))

# ── 1. 登录 + 获取账户信息 ──
@app.route('/api/subscription/info', methods=['POST'])
def api_info():
    try:
        body = request.json or {}
        token_data = body.get('token', {})
        if isinstance(token_data, str):
            token_data = json.loads(token_data)

        access_token  = token_data.get('accessToken', '')
        session_token = token_data.get('sessionToken', '')

        if not access_token:
            return jsonify({'code': 401, 'message': '缺少 Token'})

        uid = str(uuid.uuid4())
        TOKEN_STORE[uid] = {
            'access_token':  access_token,
            'session_token': session_token,
            'token_data':    token_data,
        }

        info = get_subscription_info(access_token, session_token, token_data)
        if not info:
            return jsonify({'code': 500, 'message': '获取账户信息失败'})

        return jsonify({'code': 200, 'message': '获取订阅信息成功', 'data': info, 'uid': uid})

    except Exception as e:
        import traceback; traceback.print_exc()
        return jsonify({'code': 500, 'message': str(e)[:200]})


# ── 2. 生成短链（转发给 gptserve） ──
@app.route('/api/payment/link', methods=['POST'])
def api_payment_link():
    try:
        body = request.json or {}
        resp = httpx.post(
            'https://gptserve.freespaces.app/api/payment/link',
            json=body,
            headers={
                'Content-Type': 'application/json',
                'Referer': 'https://gptaide.freespaces.app/',
                'Origin': 'https://gptaide.freespaces.app',
            },
            timeout=30
        )
        return jsonify(resp.json())

    except Exception as e:
        import traceback; traceback.print_exc()
        return jsonify({'code': 500, 'message': str(e)[:200]})


# ── 3. 取消/开启自动续费 ──
@app.route('/api/set_renew', methods=['POST'])
def api_set_renew():
    try:
        body = request.json or {}
        uid = body.get('uid')
        will_renew = body.get('will_renew', False)

        if not uid or uid not in TOKEN_STORE:
            return jsonify({'code': 401, 'message': '未登录'})

        at = TOKEN_STORE[uid]['access_token']
        st = TOKEN_STORE[uid]['session_token']
        headers = make_headers(at, st, {'Content-Type': 'application/json'})

        # 先试 PATCH，失败再试 POST
        res = cf_requests.patch(
            'https://chatgpt.com/backend-api/subscription',
            headers=headers, json={'will_renew': will_renew},
            timeout=20, impersonate='chrome116'
        )
        if res.status_code not in (200, 204):
            res = cf_requests.post(
                'https://chatgpt.com/backend-api/subscription/patch',
                headers=headers, json={'will_renew': will_renew},
                timeout=20, impersonate='chrome116'
            )

        if res.status_code in (200, 204):
            return jsonify({'code': 200, 'message': f'已{"开启" if will_renew else "关闭"}自动续费'})
        return jsonify({'code': res.status_code, 'message': f'操作失败: {res.text[:100]}'})

    except Exception as e:
        import traceback; traceback.print_exc()
        return jsonify({'code': 500, 'message': str(e)[:200]})


# ── 4. 获取账单门户链接 ──
@app.route('/api/get_billing', methods=['POST'])
def api_get_billing():
    try:
        body = request.json or {}
        uid = body.get('uid')
        token_data = body.get('token')

        # === 尝试在内存中恢复登录状态 ===
        if uid and uid not in TOKEN_STORE and isinstance(token_data, dict):
            try:
                at_val = token_data.get('accessToken') or token_data.get('access_token')
                st_val = token_data.get('sessionToken') or token_data.get('session_token')
                
                if at_val and st_val:
                    TOKEN_STORE[uid] = {
                        'access_token': at_val,
                        'session_token': st_val
                    }
                    print(f"[自动重登] 成功恢复 uid: {uid} 到内存")
            except Exception as e_restore:
                print(f"[自动重登异常]: {e_restore}")

        if not uid or uid not in TOKEN_STORE:
            return jsonify({'code': 401, 'message': '未登录'})

        at = TOKEN_STORE[uid]['access_token']
        st = TOKEN_STORE[uid]['session_token']

        # 👇 【核心修改】将 .post 改为 .get，去掉了 json 载荷，保持 headers 不变
        res = cf_requests.get(
            'https://chatgpt.com/backend-api/payments/customer_portal',
            headers=make_headers(at, st),
            timeout=20, 
            impersonate='chrome116'
        )

        if res.status_code == 200:
            return jsonify({'code': 200, 'message': '获取成功', 'data': {'url': res.json().get('url', '')}})
        
        # 针对 401/403/405 等常见失效状态码给予友好提示
        if res.status_code in [401, 403, 405]:
            return jsonify({'code': 401, 'message': f'获取失败: Token 已失效(状态码 {res.status_code})，请重新登录。'})
            
        return jsonify({'code': res.status_code, 'message': f'获取失败: {res.text[:100]}'})

    except Exception as e:
        import traceback; traceback.print_exc()
        return jsonify({'code': 500, 'message': str(e)[:200]})
        
        
        
# ── 5. 登出 ──
@app.route('/api/logout', methods=['POST'])
def api_logout():
    uid = (request.json or {}).get('uid')
    if uid in TOKEN_STORE:
        del TOKEN_STORE[uid]
    return jsonify({'code': 200, 'message': '已登出'})


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)
