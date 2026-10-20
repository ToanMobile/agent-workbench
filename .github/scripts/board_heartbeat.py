#!/usr/bin/env python3
"""Đánh ⚫ cho board super-board khi watchdog trên máy Mac ngừng cập nhật (GitHub Actions cron, chạy ngoài máy).

Watchdog (.claude/bin/super-board-watchdog.sh) ghi trạng thái board vào mô tả ngắn của Project kèm
"cập nhật HH:MM dd/MM" (giờ +07), nhịp 5 phút. Máy ngủ/tắt/mất mạng thì không gì ghi được và board vẫn hiện
🟢 (20/10 09:00 → 12:33). Cron này đọc giờ đó; board đang 🟢/🟠 mà cũ hơn BOARD_STALE_MIN phút thì đổi mô tả thành
"⚫ mất tín hiệu từ …". Board ⏸️/⚪/🔴 giữ nguyên (không có gì đang chạy để mất). Máy thức dậy, watchdog ghi đè lại.

Env: BOARD_PAT (classic PAT, scope `project`; thiếu thì thoát 0 kèm thông báo), BOARD_OWNER, BOARD_PROJECTS
("1 2 3"), BOARD_STALE_MIN (mặc định 20), BOARD_TZ_HOURS (mặc định 7).
Exit: 0 xong · 1 có Project đọc/ghi lỗi (từng Project độc lập, lỗi một cái không bỏ qua cái khác).
"""
from __future__ import annotations

import json
import os
import re
import sys
import urllib.request
from datetime import datetime, timedelta, timezone

STAMP = re.compile(r'\s*·?\s*cập nhật (\d{2}):(\d{2})(?: (\d{2})/(\d{2}))?')
ACTIVE = ('🟢', '🟠')
DARK = '⚫'
MAX_LEN = 300


def stamp_time(desc, now):
    """Giờ "cập nhật" trong mô tả (cùng múi giờ với now), hoặc None. Giờ ở tương lai = hôm qua / năm ngoái."""
    m = STAMP.search(desc or '')
    if not m:
        return None
    hh, mm, dd, mo = m.groups()
    try:
        if dd:
            t = now.replace(month=int(mo), day=int(dd), hour=int(hh), minute=int(mm), second=0, microsecond=0)
            if t > now + timedelta(minutes=5):
                t = t.replace(year=t.year - 1)
        else:
            t = now.replace(hour=int(hh), minute=int(mm), second=0, microsecond=0)
            if t > now + timedelta(minutes=5):
                t -= timedelta(days=1)
    except ValueError:   # 31/02, 29/02 năm thường, 25:00
        return None
    return t


def decide(desc, now, stale_min):
    """Mô tả ⚫ mới khi board đang 🟢/🟠 mà giờ cập nhật cũ hơn stale_min phút; None khi giữ nguyên."""
    if not desc or not desc.startswith(ACTIVE):
        return None
    t = stamp_time(desc, now)
    if t is None or now - t < timedelta(minutes=stale_min):
        return None
    previous = STAMP.sub('', desc).strip()
    return f'{DARK} mất tín hiệu từ {t:%H:%M %d/%m} — máy ngủ/tắt/mất mạng · trước đó: {previous}'[:MAX_LEN]


def graphql(token, query, variables):
    request = urllib.request.Request(
        'https://api.github.com/graphql',
        data=json.dumps({'query': query, 'variables': variables}).encode(),
        headers={'Authorization': f'bearer {token}', 'Content-Type': 'application/json'})
    with urllib.request.urlopen(request, timeout=15) as response:
        payload = json.load(response)
    if payload.get('errors'):
        raise RuntimeError(json.dumps(payload['errors'])[:300])
    return payload['data']


def main():
    token = os.environ.get('BOARD_PAT', '').strip()
    if not token:
        print('::notice::BOARD_PAT secret is not set — board heartbeat skipped (set a classic PAT with scope `project`).')
        return 0
    owner = os.environ.get('BOARD_OWNER', 'ToanMobile')
    numbers = [int(n) for n in os.environ.get('BOARD_PROJECTS', '').split() if n.isdigit()]
    stale_min = int(os.environ.get('BOARD_STALE_MIN', '20'))
    now = datetime.now(timezone(timedelta(hours=int(os.environ.get('BOARD_TZ_HOURS', '7')))))
    failed = 0
    for number in numbers:
        try:
            project = graphql(token, 'query($o:String!,$n:Int!){user(login:$o){projectV2(number:$n){id shortDescription}}}',
                              {'o': owner, 'n': number})['user']['projectV2']
            new = decide(project.get('shortDescription') or '', now, stale_min)
            if new is None:
                # Repo public: log Actions ai cũng đọc được — không in tiêu đề/mô tả của Project private.
                print(f'project {number}: ok')
                continue
            graphql(token, 'mutation($p:ID!,$d:String!){updateProjectV2(input:{projectId:$p,shortDescription:$d}){projectV2{id}}}',
                    {'p': project['id'], 'd': new})
            print(f'::warning::project {number}: marked ⚫ (watchdog silent since {stamp_time(project["shortDescription"], now):%H:%M %d/%m})')
        except Exception as error:   # mạng, quyền PAT, Project không tồn tại: báo rồi làm tiếp Project kế
            failed += 1
            print(f'::error::project {number}: {type(error).__name__}: {str(error)[:200]}')
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
