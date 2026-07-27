#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
매주 로또 당첨번호 자동 업데이트 스크립트.

동행복권 공식 API(getLottoNumber)에서 아직 파일에 없는 최신 회차를 받아와
Lotto/lotto_data.json 을 갱신합니다. 이미 있는 회차는 건드리지 않으며,
새 회차가 없으면 파일을 그대로 두어(변경 없음) 커밋도 발생하지 않습니다.

GitHub Actions에서 매주 토요일 추첨 이후 실행됩니다.
"""

import json
import sys
import time
import urllib.request
import urllib.error
from pathlib import Path

# 리포 루트 기준 JSON 경로
DATA_PATH = Path(__file__).resolve().parent.parent / "Lotto" / "lotto_data.json"

API_URL = "https://www.dhlottery.co.kr/common.do?method=getLottoNumber&drwNo={round}"

HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
    ),
    "Referer": "https://www.dhlottery.co.kr/",
    "Accept": "application/json, text/plain, */*",
}

# 새 회차 하나도 없어도 실패로 보지 않도록, "미추첨"과 "네트워크 오류"를 구분
FETCH_OK = "ok"
FETCH_NOT_DRAWN = "not_drawn"
FETCH_ERROR = "error"


def fetch_round(round_no, retries=3, timeout=15):
    """한 회차를 조회. (status, entry) 반환."""
    last_err = None
    for attempt in range(retries):
        try:
            req = urllib.request.Request(API_URL.format(round=round_no), headers=HEADERS)
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                raw = resp.read().decode("utf-8")
            data = json.loads(raw)
            if data.get("returnValue") != "success":
                # 아직 추첨되지 않은 회차
                return FETCH_NOT_DRAWN, None
            entry = {
                "round": int(data["drwNo"]),
                "numbers": [
                    int(data["drwtNo1"]), int(data["drwtNo2"]), int(data["drwtNo3"]),
                    int(data["drwtNo4"]), int(data["drwtNo5"]), int(data["drwtNo6"]),
                ],
                "bonus": int(data["bnusNo"]),
                "date": str(data["drwNoDate"]),
            }
            return FETCH_OK, entry
        except (urllib.error.URLError, urllib.error.HTTPError, ValueError, KeyError) as e:
            last_err = e
            time.sleep(2 * (attempt + 1))
    print(f"⚠️  {round_no}회 조회 실패: {last_err}", file=sys.stderr)
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

    added = []
    hit_error = False
    round_no = current_latest + 1
    # 안전장치: 한 번에 최대 60회차까지만 시도(밀린 데이터 대량 백필도 커버)
    max_probe = current_latest + 60

    while round_no <= max_probe:
        status, entry = fetch_round(round_no)
        if status == FETCH_OK:
            by_round[entry["round"]] = entry
            added.append(entry["round"])
            print(f"✅ {entry['round']}회 추가: {entry['numbers']} + {entry['bonus']} ({entry['date']})")
            round_no += 1
        elif status == FETCH_NOT_DRAWN:
            # 이 회차가 아직 안 나왔으면 이후 회차도 없음 → 종료
            print(f"⏹  {round_no}회는 아직 추첨 전. 종료.")
            break
        else:  # FETCH_ERROR
            hit_error = True
            print(f"❌ {round_no}회에서 네트워크 오류로 중단.", file=sys.stderr)
            break
        time.sleep(1)

    if not added:
        print("변경 없음: 추가할 새 회차가 없습니다.")
        # 새 회차가 "없어서" 안 나온 건 정상 종료. 단, 네트워크 오류였다면 실패로 처리.
        sys.exit(2 if hit_error else 0)

    merged = sorted(by_round.values(), key=lambda e: e["round"], reverse=True)
    out = {"latestRound": merged[0]["round"], "history": merged}

    with DATA_PATH.open("w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=2)
        f.write("\n")

    print(f"🎉 {len(added)}개 회차 추가 완료. 최신 회차: {out['latestRound']}")
    # GitHub Actions 요약/커밋 메시지에 쓰도록 출력
    print(f"::notice::Added rounds {min(added)}-{max(added)} (latest {out['latestRound']})")

    # 네트워크 오류가 중간에 있었지만 일부는 성공한 경우에도 커밋은 하되, 실패 신호는 남김
    if hit_error:
        sys.exit(2)


if __name__ == "__main__":
    main()
