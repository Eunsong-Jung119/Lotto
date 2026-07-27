#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
매주 로또 당첨번호 자동 업데이트 스크립트.

아직 파일에 없는 최신 회차를 받아와 Lotto/lotto_data.json 을 갱신합니다.
이미 있는 회차는 건드리지 않으며, 새 회차가 없으면 파일을 그대로 두어(변경 없음)
커밋도 발생하지 않습니다(멱등).

데이터 소스:
  1) 미러: smok95.github.io/lotto (GitHub Pages, 해외/Actions 서버에서도 접속 가능) — 기본
  2) 동행복권 공식 API — 폴백(해외 IP에서 막힐 수 있어 짧은 타임아웃으로 시도만)

GitHub Actions에서 매주 토요일 추첨 이후 실행됩니다.
"""

import json
import sys
import time
import urllib.request
import urllib.error
from pathlib import Path

DATA_PATH = Path(__file__).resolve().parent.parent / "Lotto" / "lotto_data.json"

MIRROR_LATEST = "https://smok95.github.io/lotto/results/latest.json"
MIRROR_ROUND = "https://smok95.github.io/lotto/results/{round}.json"
DHLOTTERY = "https://www.dhlottery.co.kr/common.do?method=getLottoNumber&drwNo={round}"

HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
    ),
    "Accept": "application/json, text/plain, */*",
}

FETCH_OK = "ok"
FETCH_NOT_DRAWN = "not_drawn"
FETCH_ERROR = "error"


def _get_json(url, timeout=15, retries=3):
    """GET → dict. 404는 None 반환(미추첨), 그 외 오류는 예외 재발생."""
    last_err = None
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers=HEADERS)
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return None  # 아직 추첨 안 된 회차
            last_err = e
        except (urllib.error.URLError, ValueError, TimeoutError) as e:
            last_err = e
        time.sleep(2 * (attempt + 1))
    raise last_err if last_err else RuntimeError("unknown error")


def _norm_date(s):
    # "2026-07-25T00:00:00Z" 또는 "2026-07-25" → "2026-07-25"
    return str(s)[:10]


def _from_mirror(data):
    return {
        "round": int(data["draw_no"]),
        "numbers": sorted(int(n) for n in data["numbers"]),
        "bonus": int(data["bonus_no"]),
        "date": _norm_date(data["date"]),
    }


def _from_dhlottery(data):
    if data.get("returnValue") != "success":
        return None
    return {
        "round": int(data["drwNo"]),
        "numbers": sorted([
            int(data["drwtNo1"]), int(data["drwtNo2"]), int(data["drwtNo3"]),
            int(data["drwtNo4"]), int(data["drwtNo5"]), int(data["drwtNo6"]),
        ]),
        "bonus": int(data["bnusNo"]),
        "date": _norm_date(data["drwNoDate"]),
    }


def get_latest_available():
    """미러의 latest.json 으로 현재까지 나온 최신 회차 번호를 구함. 실패 시 None."""
    try:
        d = _get_json(MIRROR_LATEST)
        if d and "draw_no" in d:
            return int(d["draw_no"])
    except Exception as e:
        print(f"⚠️  latest.json 조회 실패: {e}", file=sys.stderr)
    return None


def fetch_round(round_no):
    """한 회차 조회. (status, entry) 반환. 미러 우선, 실패 시 공식 API 폴백."""
    # 1) 미러
    try:
        d = _get_json(MIRROR_ROUND.format(round=round_no))
        if d is None:
            return FETCH_NOT_DRAWN, None
        return FETCH_OK, _from_mirror(d)
    except Exception as e:
        print(f"⚠️  {round_no}회 미러 실패: {e} → 공식 API 시도", file=sys.stderr)

    # 2) 공식 API 폴백 (해외에서 막힐 수 있어 짧게만 시도)
    try:
        d = _get_json(DHLOTTERY.format(round=round_no), timeout=8, retries=1)
        entry = _from_dhlottery(d) if d else None
        if entry:
            return FETCH_OK, entry
        return FETCH_NOT_DRAWN, None
    except Exception as e:
        print(f"❌ {round_no}회 공식 API도 실패: {e}", file=sys.stderr)
        return FETCH_ERROR, None


def main():
    if not DATA_PATH.exists():
        print(f"❌ 데이터 파일을 찾을 수 없음: {DATA_PATH}", file=sys.stderr)
        sys.exit(1)

    with DATA_PATH.open("r", encoding="utf-8") as f:
        data = json.load(f)

    by_round = {e["round"]: e for e in data.get("history", [])}
    current_latest = data.get("latestRound", max(by_round) if by_round else 0)
    print(f"현재 최신 회차: {current_latest}")

    target_latest = get_latest_available()
    if target_latest is not None:
        print(f"현재까지 나온 최신 회차: {target_latest}")
        if target_latest <= current_latest:
            print("변경 없음: 새로 나온 회차가 없습니다.")
            sys.exit(0)
        end_round = target_latest
    else:
        # latest.json 실패 시: 다음 회차부터 최대 60개까지 직접 탐색
        end_round = current_latest + 60

    added = []
    hit_error = False
    round_no = current_latest + 1
    while round_no <= end_round:
        status, entry = fetch_round(round_no)
        if status == FETCH_OK:
            by_round[entry["round"]] = entry
            added.append(entry["round"])
            print(f"✅ {entry['round']}회 추가: {entry['numbers']} + {entry['bonus']} ({entry['date']})")
            round_no += 1
        elif status == FETCH_NOT_DRAWN:
            print(f"⏹  {round_no}회는 아직 추첨 전. 종료.")
            break
        else:
            hit_error = True
            print(f"❌ {round_no}회에서 오류로 중단.", file=sys.stderr)
            break
        time.sleep(1)

    if not added:
        print("변경 없음: 추가할 새 회차가 없습니다.")
        sys.exit(2 if hit_error else 0)

    merged = sorted(by_round.values(), key=lambda e: e["round"], reverse=True)
    out = {"latestRound": merged[0]["round"], "history": merged}

    with DATA_PATH.open("w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=2)
        f.write("\n")

    print(f"🎉 {len(added)}개 회차 추가 완료. 최신 회차: {out['latestRound']}")
    print(f"::notice::Added rounds {min(added)}-{max(added)} (latest {out['latestRound']})")

    if hit_error:
        sys.exit(2)


if __name__ == "__main__":
    main()
