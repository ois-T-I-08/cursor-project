#!/usr/bin/env python3
"""Convert paimon-moe banners.js + Amber EN catalogs → gacha_banner_history.json."""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BANNERS_JS = ROOT / "tool" / "paimon_banners.js"
AVATARS_EN = ROOT / "tool" / "amber_avatars_en.json"
WEAPONS_EN = ROOT / "tool" / "amber_weapons_en.json"
OUT = ROOT / "assets" / "config" / "gacha_banner_history.json"


def slugify(name: str) -> str:
    s = name.lower().strip()
    s = s.replace("'", "").replace("'", "")
    s = re.sub(r"[^a-z0-9]+", "_", s)
    return s.strip("_")


def load_name_to_id(path: Path) -> dict[str, str]:
    data = json.loads(path.read_text(encoding="utf-8"))
    items = data.get("data", {}).get("items", data.get("items", {}))
    mapping: dict[str, str] = {}
    for key, item in items.items():
        cid = str(item.get("id", key))
        name = str(item.get("name", "")).strip()
        if not name:
            continue
        mapping[slugify(name)] = cid
        # also key itself if numeric
        mapping[slugify(cid)] = cid
    return mapping


def extract_array_body(src: str, key: str) -> str:
    m = re.search(rf"{key}\s*:\s*\[", src)
    if not m:
        return "[]"
    i = m.end() - 1
    depth = 0
    start = i
    for j in range(i, len(src)):
        ch = src[j]
        if ch == "[":
            depth += 1
        elif ch == "]":
            depth -= 1
            if depth == 0:
                return src[start : j + 1]
    raise RuntimeError(f"unclosed array for {key}")


def parse_banner_objects(js_array: str) -> list[dict]:
    """Extract banner objects from a JS array, ignoring commented lines."""
    lines = []
    for line in js_array.splitlines():
        if re.match(r"^\s*//", line):
            continue
        lines.append(line)
    text = "\n".join(lines)

    objects: list[dict] = []
    for m in re.finditer(r"\{([^{}]+)\}", text, flags=re.S):
        block = m.group(0)
        if "start:" not in block or "name:" not in block:
            continue
        name = _js_string_field(block, "name")
        start = _js_string_field(block, "start")
        end = _js_string_field(block, "end")
        if not name or not start or not end:
            continue
        version = _js_string_field(block, "version") or ""
        featured = _js_string_array_field(block, "featured")
        featured_rare = _js_string_array_field(block, "featuredRare")
        objects.append(
            {
                "name": name,
                "start": start,
                "end": end,
                "version": version,
                "featured": featured,
                "featuredRare": featured_rare,
            }
        )
    return objects


def _js_string_field(block: str, key: str) -> str | None:
    m = re.search(
        rf"{key}\s*:\s*(?:'([^']*)'|\"((?:\\.|[^\"])*)\")",
        block,
    )
    if not m:
        return None
    return m.group(1) if m.group(1) is not None else m.group(2)


def _js_string_array_field(block: str, key: str) -> list[str]:
    m = re.search(rf"{key}\s*:\s*\[([^\]]*)\]", block, flags=re.S)
    if not m:
        return []
    return re.findall(r"['\"]([^'\"]+)['\"]", m.group(1))


def js_array_to_json(js_array: str) -> list:
    return parse_banner_objects(js_array)


def parse_dt(s: str) -> str:
    # paimon times are Asia/Shanghai wall clock without offset
    s = s.strip()
    if re.match(r"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$", s):
        return s.replace(" ", "T") + "+08:00"
    return s


def resolve_ids(slugs: list, mapping: dict[str, str]) -> list[str]:
    out: list[str] = []
    for slug in slugs:
        key = slugify(str(slug))
        cid = mapping.get(key)
        if cid:
            out.append(cid)
            continue
        # try without common prefixes/suffixes
        alt = key.replace("arataki_", "").replace("_shogun", "")
        cid = mapping.get(alt)
        if cid:
            out.append(cid)
            continue
        # keep slug as unresolved token (UI may still show text)
        out.append(str(slug))
    return out


def convert_section(
    items: list,
    type_name: str,
    char_map: dict[str, str],
    weapon_map: dict[str, str],
) -> list[dict]:
    banners: list[dict] = []
    for idx, item in enumerate(items):
        if not isinstance(item, dict):
            continue
        # skip commented-out style empties
        name = str(item.get("name", "")).strip()
        if not name:
            continue
        start = item.get("start")
        end = item.get("end")
        if not start or not end:
            continue
        version = str(item.get("version", "")).strip()
        featured = item.get("featured") or []
        featured_rare = item.get("featuredRare") or []
        bid = f"{type_name}-{version or 'x'}-{idx}"

        if type_name == "weapon":
            featured5 = []
            featured4 = []
            weapons = resolve_ids(list(featured) + list(featured_rare), weapon_map)
            # split 5* vs 4* roughly: first two featured often 5*
            featured_weapons = resolve_ids(list(featured), weapon_map)
            featured_weapons4 = resolve_ids(list(featured_rare), weapon_map)
            weapons = featured_weapons + featured_weapons4
        else:
            featured5 = resolve_ids(list(featured), char_map)
            featured4 = resolve_ids(list(featured_rare), char_map)
            weapons = []

        banners.append(
            {
                "id": bid,
                "type": type_name if type_name != "chronicled" else "chronicled",
                "name": name,
                "version": version,
                "start": parse_dt(str(start)),
                "end": parse_dt(str(end)),
                "featured5Ids": featured5,
                "featured4Ids": featured4,
                "featuredWeaponIds": weapons,
            }
        )
    return banners


def main() -> None:
    src = BANNERS_JS.read_text(encoding="utf-8")
    char_map = load_name_to_id(AVATARS_EN)
    weapon_map = load_name_to_id(WEAPONS_EN)

    # Extra aliases for paimon slugs that differ from Amber EN names
    aliases = {
        "raiden": "raiden_shogun",
        "itto": "arataki_itto",
        "tartaglia": "tartaglia",
        "childe": "tartaglia",
        "ayaka": "kamisato_ayaka",
        "ayato": "kamisato_ayato",
        "kazuha": "kaedehara_kazuha",
        "sara": "kujou_sara",
        "kokomi": "sangonomiya_kokomi",
        "yun_jin": "yun_jin",
        "yae": "yae_miko",
        "heizou": "shikanoin_heizou",
        "shinobu": "kuki_shinobu",
        "traveler_anemo": "traveler",
    }
    for alias, target in aliases.items():
        if target in char_map:
            char_map[alias] = char_map[target]
        # also map alias directly if amber has it
        if alias in char_map:
            continue

    characters = js_array_to_json(extract_array_body(src, "characters"))
    weapons = js_array_to_json(extract_array_body(src, "weapons"))
    chronicled = js_array_to_json(extract_array_body(src, "chronicled"))

    banners: list[dict] = []
    banners += convert_section(characters, "character", char_map, weapon_map)
    # Detect character2: paimon puts dual banners in characters with same window;
    # keep type character for all character event entries from paimon.
    banners += convert_section(weapons, "weapon", char_map, weapon_map)
    banners += convert_section(chronicled, "chronicled", char_map, weapon_map)

    payload = {
        "version": 1,
        "description": "PU banner history seed (from paimon-moe banners.js + Amber EN IDs). Live calendar overlays current.",
        "banners": banners,
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {len(banners)} banners → {OUT}")


if __name__ == "__main__":
    main()
