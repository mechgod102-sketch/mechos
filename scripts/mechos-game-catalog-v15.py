#!/usr/bin/env python3
"""MechOS Hotfix 15 native game-search backend.

Returns normalized JSON for the Unified Store UI. Search/catalog presentation
stays inside MechOS; official provider clients still own sign-in, purchases,
licenses and downloads.
"""
from __future__ import annotations

import json
import sys
from urllib.parse import urlencode
from urllib.request import Request, urlopen

BASE = "https://www.cheapshark.com/api/1.0"
UA = "MechOS-Unified-Store/0.3.0-hotfix.15"


def get_json(path: str, params: dict | None = None):
    url = BASE + path
    if params:
        url += "?" + urlencode(params)
    req = Request(url, headers={"User-Agent": UA, "Accept": "application/json"})
    with urlopen(req, timeout=12) as response:
        return json.loads(response.read().decode("utf-8"))


def provider_key(name: str) -> str:
    n = name.casefold()
    if "steam" in n:
        return "steam"
    if "epic" in n:
        return "epic"
    if "gog" in n:
        return "gog"
    if "amazon" in n:
        return "amazon"
    return "other"


def search(query: str, selected: str = "all") -> list[dict]:
    query = query.strip()
    if not query:
        return []

    stores_raw = get_json("/stores")
    stores = {
        str(row.get("storeID", "")): {
            "name": str(row.get("storeName", "Store")),
            "key": provider_key(str(row.get("storeName", ""))),
        }
        for row in stores_raw
    }

    deals = get_json(
        "/deals",
        {
            "title": query,
            "pageSize": 60,
            "sortBy": "Title",
            "desc": 0,
        },
    )

    selected = selected.strip().casefold() or "all"
    grouped: dict[str, dict] = {}
    for deal in deals:
        sid = str(deal.get("storeID", ""))
        store = stores.get(sid, {"name": "Store", "key": "other"})
        key = store["key"]
        if selected != "all" and key != selected:
            continue

        title = str(deal.get("title", "Game")).strip() or "Game"
        steam_app_id = str(deal.get("steamAppID") or "").strip()
        group_key = (steam_app_id or title.casefold())
        try:
            sale = float(deal.get("salePrice", "0") or 0)
        except Exception:
            sale = 0.0
        try:
            normal = float(deal.get("normalPrice", "0") or 0)
        except Exception:
            normal = sale

        item = grouped.setdefault(
            group_key,
            {
                "title": title,
                "steam_app_id": steam_app_id,
                "thumb": str(deal.get("thumb") or ""),
                "best_price": sale,
                "normal_price": normal,
                "rating": str(deal.get("steamRatingPercent") or ""),
                "providers": [],
            },
        )
        if sale and (not item["best_price"] or sale < item["best_price"]):
            item["best_price"] = sale
            item["normal_price"] = normal
        pname = store["name"]
        if pname not in item["providers"]:
            item["providers"].append(pname)

    rows = list(grouped.values())
    rows.sort(key=lambda x: (x["title"].casefold(), x["best_price"] or 999999))
    return rows[:30]


def main() -> int:
    if len(sys.argv) < 2:
        print("Usage: mechos-game-catalog-v15 <query> [all|steam|epic|gog|amazon]", file=sys.stderr)
        return 2
    query = sys.argv[1]
    selected = sys.argv[2] if len(sys.argv) >= 3 else "all"
    try:
        payload = {
            "schema": 1,
            "query": query,
            "provider": selected,
            "results": search(query, selected),
        }
        print(json.dumps(payload, ensure_ascii=False))
        return 0
    except Exception as exc:
        print(json.dumps({"schema": 1, "query": query, "provider": selected, "results": [], "error": str(exc)}))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
