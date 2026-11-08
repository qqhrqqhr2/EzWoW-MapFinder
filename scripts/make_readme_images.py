#!/usr/bin/env python3
"""Draws the README mock-ups of EzWoW - Map Finder (docs/images/ui_*.png, settings_*.png).

The search panel, its result rows and tooltip, the map pins, the zone level label,
the coordinate bar, the transit icons, the rare alert card and the settings window
are rebuilt from the sizes, coordinates, colours and strings in the addon code
(UI/SearchPanel.lua, UI/OptionsWindow.lua, Modules/*.lua, Core/Init.lua,
Core/Locales.lua) and the bundled data (Database/HunterPets.lua,
Data/ZoneAndGatherData.lua), in game pixels x scale. The map art is a simplified
drawing; quests and character names are made up.

usage: python scripts/make_readme_images.py .
Renders with a local headless Chrome (set CHROME=<path> if it is not found).
"""
import base64
import html
import math
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

PAGE_W = 1600
CALL = "#4bc8e8"

# ---------------------------------------------------------------------------
# Values read from the Lua code and the bundled data
# ---------------------------------------------------------------------------


def read(root, rel):
    return (root / rel).read_text(encoding="utf-8")


def parse_theme(src):
    block = re.search(r"local Theme = \{(.*?)\n\}", src, re.S).group(1)
    return {k: [float(v) for v in body.split(",")] for k, body in re.findall(r"(\w+)\s*=\s*\{\s*([\d.,\s]+)\}", block)}


def parse_db_defaults(src):
    out = {}
    for k, v in re.findall(r"if CONST_DB\.(\w+) == nil then CONST_DB\.\w+ = (true|false|\"\w+\")", src):
        out[k] = True if v == "true" else False if v == "false" else v.strip('"')
    return out


def _strings(block):
    return {k: v.replace('\\"', '"').replace("\\n", "\n")
            for k, v in re.findall(r'^\s*(\w+)\s*=\s*"((?:[^"\\]|\\.)*)"', block, re.M)}


def parse_locales(src):
    en_block = src[src.index("local L_EN = {"):]
    en_block = en_block[:en_block.index("\n}")]
    ko_start = src.index("koKR = setmetatable({")
    ko_block = src[ko_start:src.index("}, { __index", ko_start)]
    en, ko = _strings(en_block), _strings(ko_block)
    for k, v in re.findall(r'^L_EN\.(\w+) = "((?:[^"\\]|\\.)*)"', src, re.M):
        en[k] = v
    for k, v in re.findall(r'^LOCALES\.koKR\.(\w+) = "((?:[^"\\]|\\.)*)"', src, re.M):
        ko[k] = v
    for k, v in en.items():
        ko.setdefault(k, v)
    return {"en": en, "ko": ko}


def parse_options(src):
    """Settings window size, rows (y, key, field) and the backdrop slider of UI/OptionsWindow.lua."""
    src = src[src.index("function SettingsDialog.buildMapFinderSettingsFrame"):]
    size = re.search(r"windowFrame:SetSize\((\d+), (\d+)\)", src)
    saved = int(re.search(r"local LANG_ROWS_SAVED = (\d+)", src).group(1))
    rows = []
    for name, y, field in re.findall(r'windowFrame\.(\w+) = createCheckOptionRow\((-?\d+), "(\w+)"', src):
        rows.append({"name": name, "y": -(int(y) + saved), "field": field})
    labels = dict(re.findall(r"self\.(\w+)\.label:SetText\(L\.(\w+)\)", src))
    ops = {name: op for name, op in re.findall(r"self\.(\w+):SetChecked\(ns\.DB\.\w+ (~= false|== true)\)", src)}
    for r in rows:
        r["label"], r["op"] = labels[r["name"]], ops[r["name"]]
    backdrop_y = -(int(re.search(r"local rowY = (-?\d+) \+ LANG_ROWS_SAVED", src).group(1)) + saved)
    managed_h = int(re.search(r"self:SetHeight\(questElsewhere and (\d+) or (\d+)\)", src).group(1))
    note_y = -(int(re.search(r'questManagedNote:SetPoint\("TOPLEFT", 22, (-?\d+) \+ LANG_ROWS_SAVED - 4\)', src).group(1)) + saved - 4)
    shift = int(re.search(r"self\.PlaceServiceRows\(questElsewhere and (\d+) or 0\)", src).group(1))
    types_w = int(re.search(r"local typesBtn = createStyledActionBtn\((\d+), 20", src).group(1))
    return {"size": (int(size.group(1)), int(size.group(2))), "rows": rows, "backdropY": backdrop_y,
            "managedH": managed_h, "noteY": note_y, "serviceShift": shift, "typesW": types_w}


def parse_version(src):
    m = re.search(r"^## Version:\s*(\S+)", src, re.M)
    return m.group(1) if m else ""


def parse_zone_names(src):
    return {k: {"en": en, "ko": ko} for k, en, ko in
            re.findall(r'^\s*\["([^"]+)"\] = \{ enUS = "([^"]+)", koKR = "([^"]+)"', src, re.M)}


def parse_zone_levels(src):
    block = src[src.index("local ZONE_LEVEL_DATA = {"):]
    block = block[:block.index("\n}")]
    return {int(k): (int(a), int(b), int(c)) for k, a, b, c in re.findall(r"\[(\d+)\] = \{ (\d+), (\d+), (\d+) \}", block)}


def parse_transit(src, map_id):
    block = src[src.index("local TRANSIT_DATA = {"):]
    block = block[block.index(f"[{map_id}] = {{"):]
    block = block[:block.index("\n\t},")]
    return [dict(kind=k, fac=f, x=float(x), y=float(y), ko=ko, en=en) for k, f, x, y, ko, en in
            re.findall(r'kind = "(\w+)",\s*fac = "(\w)", x = ([\d.]+),\s*y = ([\d.]+),.*?ko = "([^"]+)", en = "([^"]+)"', block)]


def parse_faction_colors(src):
    block = re.search(r"local FACTION_COLORS = \{(.*?)\n\}", src, re.S).group(1)
    return {k: [float(v) for v in body.split(",")] for k, body in re.findall(r"(\w)\s*=\s*\{\s*([\d.,\s]+)\}", block)}


def parse_pets(src):
    fams = {int(i): dict(ko=ko, en=en, dietKo=dk, dietEn=de, hp=float(hp), arm=float(arm), dmg=float(dmg)) for i, ko, en, dk, de, hp, arm, dmg in
            re.findall(r'\[(\d+)\] = \{ ko = "([^"]*)", en = "([^"]*)", dietKo = "([^"]*)", dietEn = "([^"]*)", hp = ([\d.]+), arm = ([\d.]+), dmg = ([\d.]+) \}', src)}
    skills = {int(i): dict(ko=ko, en=en, rank=int(r) if r else None) for i, ko, en, r in
              re.findall(r'^\s*\[(\d+)\] = \{ ko = "([^"]*)", en = "([^"]*)"(?:, rank = (\d+))? \}', src, re.M)}
    pets = []
    for m in re.finditer(r'^regPet\((\d+),"([^"]*)","([^"]*)",(\d+),(\d+),(\d+),([\d.]+),(true|false),(true|false),(nil|\{[^}]*\}),"([^"]*)",\{(.*)\}\)\s*$', src, re.M):
        pid, en, ko, fam, lo, hi, spd, rare, elite, sk, zone, spawns = m.groups()
        sp = [(int(a), float(x), float(y)) for a, x, y in re.findall(r"\{-?\d+,(\d+),([\d.]+),([\d.]+)\}", spawns)]
        pets.append(dict(id=int(pid), en=en, ko=ko, fam=int(fam), lo=int(lo), hi=int(hi), spd=float(spd), rare=rare == "true",
                         elite=elite == "true", skills=[int(s) for s in re.findall(r"\d+", sk)] if sk != "nil" else [], zone=zone, spawns=sp))
    return fams, skills, pets


def parse_gather_colors(src):
    return {k.lower(): [float(v) for v in body.split(",")] for k, body in
            re.findall(r"local (HERB|ORE)_COLOR = \{\s*([\d.,\s]+)\}", src)}


def css(c, alpha=None):
    r, g, b = (round(min(1, v) * 255) for v in c[:3])
    a = alpha if alpha is not None else (c[3] if len(c) > 3 else 1)
    return f"rgba({r},{g},{b},{a:.2f})"


# ---------------------------------------------------------------------------
# Scene: The Barrens, a hunter at the crossroads searching "P raptor"
# ---------------------------------------------------------------------------
MAP_ID = 1413
ZONE_KEY = "The Barrens"
FAMILY = 11  # raptor
PLAYER_LEVEL = 14
PLAYER_POS = (51.5, 30.2)
CURSOR_POS = (39.8, 31.5)
SELECTED_EN = "Sunscale Screecher"
RARE_EN = "Takk the Leaper"

T = {
    "ko": {
        "lead": "월드맵에서 몬스터 · 희귀 몹 · 사냥꾼 야수 · NPC · 채집물 · 퀘스트 · 아이템 위치를 8개 언어로 바로 검색, 월드맵 편의 기능, 레어 알림, 채집 도우미",
        "query": "P 랩터",
        "mapTitle": "칼림도어 - 불모의 땅",
        "quest": "[16] 오아시스의 위협",
        "questObj": "물 정찰병 처치: 2/6",
        "npc": "물 감시관 오그로",
        "questDone": "[14] 수상한 보급품",
        "notes": [
            ("도킹 버튼", "월드맵 왼쪽 아래 첫 칸. 좌클릭: 검색창 펼치기/접기, 드래그: 위치 이동, 우클릭: 위치 초기화."),
            ("분류 탭", "전체 / 몬스터 / NPC / 오브젝트 / 퀘스트 / 아이템."),
            ("검색창 · 접두어", "M 몬스터, R 희귀, P 사냥꾼 야수, N NPC, O 오브젝트, Q 퀘스트, I 아이템 + 공백. “오그경매”처럼 붙여 쓴 약칭도 알아듣습니다. 핀 지우기: 지도 표시 지우기."),
            ("야수 정보", "P로 찾으면 야수 과·레벨·공격 속도·첫 기술이 결과에, 먹이·배율·습득 기술 전체가 툴팁에 나옵니다."),
            ("위치 표시", "결과를 누르면 그 지역 지도로 이동해 튀는 화살표와 웨이포인트를 찍습니다. 지금 있는 지역 → 가까운 순으로 정렬, 누를 때마다 다음 출현 위치로."),
            ("지역 정보", "지역 이름 아래에 적정 레벨(내 레벨 대비 색)과 필요한 낚시 숙련도."),
            ("좌표", "지도 아래에 플레이어 · 마우스 좌표."),
            ("이동 수단", "배 · 비행선 · 지하철 · 차원문을 진영 색 아이콘으로 표시하고, 누르면 도착지 지도를 엽니다."),
            ("미탐험 지역", "가 보지 않은 지역의 안개를 걷고 푸른빛으로 구분합니다(전장 지도 포함)."),
            ("레어 알림", "근처에 레어 몬스터가 보이면 카드와 소리로 알려 주고, “지도에서 보기”로 위치를 찍습니다(같은 몬스터는 5분에 한 번, 던전·공격대 제외)."),
            ("퀘스트 표시", "목표를 다 채운 퀘스트의 보고 위치(?)와 진행 중인 퀘스트의 목표 위치(퀘스트마다 다른 색 점). EzWoW - Quest가 켜져 있으면 EzWoW - Quest가 맡습니다."),
            ("약초 · 광맥 자리", "약초채집 · 채광이 있으면 약초(초록)와 광맥(주황)이 자랄 수 있는 자리를 지역 지도와 미니맵에 표시합니다. 숙련도가 모자라면 흐리게."),
        ],
        "foot": "애드온 코드의 창 크기·좌표·색상·문구와 내장 데이터(야수 이름·레벨·기술·출현 위치, 지역 레벨, 이동 수단)로 재현한 예시 화면입니다. 지도는 단순화한 그림이고, 퀘스트·NPC 이름은 지어낸 예시입니다.",
        "sTitle": "설정창",
        "sLead": "/ezmf config · 언어, 지도 버튼, 웨이포인트, 안개 제거, 좌표·지역 레벨, 지도 배경, 확대, 이동 수단, 레어 알림, 퀘스트 표시, 마을 NPC, 채집 도우미",
        "sNotes": [
            ("언어", "자동 또는 8개 언어. 검색 결과 이름과 화면 문구가 바로 바뀝니다."),
            ("검색 동작", "도킹 버튼을 왼쪽 아래에 자동 정렬, 결과를 고를 때 웨이포인트 자동 표시."),
            ("미탐험 지역", "안개 제거(전장 지도 포함)와 푸른빛 구분."),
            ("좌표 · 지역 정보", "지도 아래 좌표, 지역 이름 아래 적정 레벨과 낚시 숙련도."),
            ("지도 편의", "이동 중 지도 흐려짐 끄기, 지도 뒤 배경 어둡기(0~100%, ‘기본’은 게임 기본 모습), 최대 확대 배율 늘리기(최대 3.2배, 처음엔 꺼짐), 배·비행선·지하철·차원문 표시."),
            ("레어 알림", "근처 레어 몬스터 알림과 알림 소리."),
            ("퀘스트 표시", "완료한 퀘스트의 보고 위치, 진행 중인 퀘스트 위치(처음엔 꺼짐), 진행 중인 퀘스트 목표 위치(지도·미니맵)."),
            ("마을 NPC 표시", "도시 지도에 여관주인·은행·경매인·비행 조련사·교관·상인·우체통 아이콘(교관은 직업 문장·전문기술 아이콘). ‘종류’로 고르고, 일반 지역 지도 표시는 처음엔 꺼짐."),
            ("채집 도우미", "약초채집·채광이 있는 캐릭터용: 미니맵·지역 지도에 약초·광맥 자리, 앞에 있는 가장 가까운 약초·광맥 위 아이콘, 접속·부활 때 약초 찾기·광물 찾기 자동 켜기."),
            ("하단", "도킹 버튼 위치 초기화, 후원하기."),
        ],
        "sHand": ("EzWoW - Quest와 함께 쓸 때", "퀘스트 표시 세 줄 대신 안내 한 줄이 나오고(아래 그림), 지도의 퀘스트 표시는 EzWoW - Quest가 맡습니다."),
        "sFoot": "애드온 코드의 창 크기·좌표·색상·문구로 재현한 예시 화면입니다. 체크 상태는 기본값입니다.",
    },
    "en": {
        "lead": "Find monsters, rares, tameable beasts, NPCs, nodes, quests and items on the World Map in 8 languages, plus map conveniences, rare alerts and gathering helpers",
        "query": "P raptor",
        "mapTitle": "Kalimdor - The Barrens",
        "quest": "[16] Trouble at the Oasis",
        "questObj": "Water Scout slain: 2/6",
        "npc": "Watcher Ogro",
        "questDone": "[14] Suspicious Supplies",
        "notes": [
            ("Dock button", "First slot at the bottom-left of the World Map. Left-click: open or close the search, drag: move, right-click: reset position."),
            ("Category tabs", "All / Monster / NPC / Object / Quest / Item."),
            ("Search box · prefixes", "M monster, R rare, P tameable beast, N NPC, O object, Q quest, I item + space. Clear Pins removes the map markers."),
            ("Beast info", "With P the results show family, level, attack speed and first skill; the tooltip adds diet, modifiers and every learnable skill."),
            ("Show on map", "Click a result to open its zone with a bouncing arrow and a waypoint. Sorted current zone → nearest; each click moves to the next spawn."),
            ("Zone info", "Level range (coloured against your level) and the fishing skill needed, under the zone name."),
            ("Coordinates", "Player and cursor coordinates below the map."),
            ("Transport", "Boats, zeppelins, trams and portals in faction colours; click one to open the destination map."),
            ("Unexplored areas", "Lifts the fog from areas you have not visited and tints them light blue (battlefield map too)."),
            ("Rare alert", "A card and a sound when a rare monster is nearby; “Show on map” marks it (once per 5 minutes per monster, not in dungeons or raids)."),
            ("Quest marks", "Turn-in spots of finished quests (?) and objective spots of quests in progress (one dot colour per quest). With EzWoW - Quest enabled, EzWoW - Quest handles them."),
            ("Herb & ore spots", "With Herbalism or Mining, the places where herbs (green) and ore (orange) can grow on zone maps and the minimap. Dimmed when your skill is too low."),
        ],
        "foot": "Mock-up rebuilt from the window sizes, coordinates, colours and strings in the addon code and the bundled data (beast names, levels, skills and spawns, zone levels, transport). The map is a simplified drawing; quests and NPC names are made up.",
        "sTitle": "Settings",
        "sLead": "/ezmf config · language, map button, waypoint, reveal, coordinates & zone level, map backdrop, zoom, transport, rare alerts, quest marks, town NPCs, gathering",
        "sNotes": [
            ("Language", "Auto or one of 8 languages. Result names and texts change at once."),
            ("Search behaviour", "Keep the dock button at the bottom-left, set a waypoint when you pick a result."),
            ("Unexplored areas", "Reveal (battlefield map too) and light-blue tint."),
            ("Coordinates · zone info", "Coordinates below the map, level range and fishing skill under the zone name."),
            ("Map conveniences", "No map fade while moving, map backdrop darkness (0–100%, ‘Default’ keeps the game's look), extended maximum zoom (up to 3.2×, off by default), boats, zeppelins, trams and portals."),
            ("Rare alert", "Alert for nearby rare monsters and its sound."),
            ("Quest marks", "Turn-in spots of finished quests, spots of quests in progress (off by default), objective spots of quests in progress (map and minimap)."),
            ("Town NPCs", "Icons for innkeepers, banks, auctioneers, flight masters, trainers, vendors and mailboxes on city maps (class crests and profession icons for trainers). Pick kinds with ‘Types’; regular zone maps are off by default."),
            ("Gathering helpers", "For characters with Herbalism or Mining: herb and ore spots on the minimap and zone maps, an icon over the nearest herb or vein in front of you, Find Herbs / Find Minerals switched on at login and after death."),
            ("Bottom", "Reset the dock button position, support."),
        ],
        "sHand": ("With EzWoW - Quest", "One note line replaces the three quest rows (picture below) and EzWoW - Quest draws the quest marks on the map."),
        "sFoot": "Mock-up rebuilt from the window size, coordinates, colours and strings in the addon code. Check boxes show the defaults.",
    },
}

S = 1.25  # game px -> page px


def px(v):
    return f"{v * S:.2f}px"


def esc(s):
    return html.escape(s, quote=False)


SHADOW = "text-shadow:1px 1px 0 #000,0 0 2px rgba(0,0,0,.8);"
OUTLINE = "text-shadow:-1px 0 #000,1px 0 #000,0 -1px #000,0 1px #000,0 0 3px #000;"

CSS = f"""
* {{ box-sizing: border-box; margin: 0; padding: 0; }}
body {{ width: {PAGE_W}px; overflow: hidden; background: radial-gradient(ellipse at 30% 0%, #1f2a3d 0%, #121922 55%, #0b1014 100%);
  font-family: 'Noto Sans KR', 'Malgun Gothic', sans-serif; color: #edf4f7; }}
.page {{ position: relative; padding: 34px 50px 40px; }}
h1 {{ color: {CALL}; font-size: 40px; font-weight: 700; letter-spacing: .3px; display: flex; align-items: center; gap: 14px; }}
h1 .badge {{ font-size: 15px; background: {CALL}; color: #06222b; padding: 2px 9px; border-radius: 5px; }}
.lead {{ color: #d5dde2; font-size: 19px; margin-top: 6px; }}
.abs {{ position: absolute; }}
.t {{ position: absolute; white-space: nowrap; line-height: 1; }}
.call {{ position: absolute; width: 30px; height: 30px; border-radius: 50%; background: {CALL}; color: #06222b; font-weight: 700;
  font-size: 16px; display: flex; align-items: center; justify-content: center; border: 2px solid #06222b; box-shadow: 0 0 0 2px {CALL}55; z-index: 50; }}
.notes {{ position: absolute; }}
.note {{ display: flex; gap: 12px; margin-bottom: 10px; font-size: 16px; line-height: 1.5; color: #dfe6ea; }}
.note .n {{ flex: none; width: 28px; height: 28px; border-radius: 50%; background: {CALL}; color: #06222b; font-weight: 700;
  font-size: 15px; display: flex; align-items: center; justify-content: center; }}
.note .n.i {{ background: #e0af68; }}
.note b {{ color: #fff; }}
.foot {{ color: #7d8d98; font-size: 13.5px; line-height: 1.5; }}
.fit {{ display: inline-block; }}
.tip {{ position: absolute; background: rgba(6,10,16,.94); border: 2px solid #5d6d7a; border-radius: 4px; padding: 7px 11px;
  font-size: 14px; line-height: 1.5; white-space: nowrap; z-index: 20; }}
"""

FIT_JS = """
<script>
document.querySelectorAll('[data-fit]').forEach(function (e) {
  var max = parseFloat(e.dataset.fit), min = parseFloat(e.dataset.min || 8);
  var fs = parseFloat(getComputedStyle(e).fontSize);
  while (e.scrollWidth > max && fs > min) { fs -= 0.25; e.style.fontSize = fs + 'px'; }
});
</script>
"""


def box(x, y, w, h, style="", inner=""):
    return f'<div class="abs" style="left:{px(x)};top:{px(y)};width:{px(w)};height:{px(h)};{style}">{inner}</div>'


def notes_height(notes, width):
    h = 0
    for a, b in notes:
        chars = len(a) + len(b) + 3
        wide = sum(1 for ch in a + b if ord(ch) > 0x2e80)
        per_line = width / (8.4 + 7.4 * wide / chars)
        h += max(1, math.ceil(chars / per_line)) * 24 + 10
    return h


def note_html(start, lst, info=False):
    return "".join(f'<div class="note"><span class="n{" i" if info else ""}">{"i" if info else start + i}</span>'
                   f'<div><b>{esc(a)}</b> — {esc(b)}</div></div>' for i, (a, b) in enumerate(lst))


def disc(x, y, size, color, alpha=1.0):
    return (f'<div class="abs" style="left:{x - size / 2:.2f}px;top:{y - size / 2:.2f}px;width:{size:.2f}px;height:{size:.2f}px;'
            f'border-radius:50%;background:{color};opacity:{alpha}"></div>')


# ---------------------------------------------------------------------------
# Search results (UI/SearchPanel.lua refreshRows, Modules/SearchEngine.lua composePetRowTag)
# ---------------------------------------------------------------------------
def pet_results(ctx, lang):
    fams, skills, pets = ctx["pets"]
    zn = ctx["zones"]
    hits = [p for p in pets if p["fam"] == FAMILY and p["spawns"]]

    def dist(p):
        """distance to the nearest spawn on this map (defaultSpawnIndex)"""
        return min((x * 100 - PLAYER_POS[0]) ** 2 + (y * 100 - PLAYER_POS[1]) ** 2 for m, x, y in p["spawns"] if m == MAP_ID)

    here = sorted((p for p in hits if p["zone"] == ZONE_KEY), key=dist)
    rest = sorted((p for p in hits if p["zone"] != ZONE_KEY), key=lambda p: (p["lo"], p["en"]))
    out = []
    for p in here + rest:
        fam = fams[p["fam"]]
        zone = zn.get(p["zone"], {"en": p["zone"], "ko": p["zone"]})[lang]
        name = p["ko"] if lang == "ko" else p["en"]
        lv = f"Lv{p['lo']}-{p['hi']}" if p["hi"] != p["lo"] else f"Lv{p['lo']}"
        segs = [fam[lang], lv, f"{p['spd']:.1f}s"]
        first = skills.get(p["skills"][0]) if p["skills"] else None
        if first:
            segs.append(first[lang] + (f" {first['rank']}" if first["rank"] else ""))
        out.append(dict(p=p, zone=zone, name=name, tag=" · ".join(segs), count=len(p["spawns"])))
    return out


def row_html(r):
    p = r["p"]
    if p["rare"]:
        badge = '<span style="color:#cc66ff">[R]</span><span style="color:#60cea3">[P]</span> '
    else:
        badge = '<span style="color:#60cea3">[P]</span> '
    count = f' <span style="color:#a7b9c5">({r["count"]})</span>' if r["count"] > 1 else ""
    return (f'{badge}<span style="color:#7ecbe0">{esc(r["zone"])}</span> <span style="color:#a7b9c5">&gt;</span> '
            f'{esc(r["name"])} <span style="color:#60cea3">&lt;{esc(r["tag"])}&gt;</span>{count}')


def row_tooltip(ctx, lang, r):
    fams, skills, _ = ctx["pets"]
    L = ctx["L"][lang]
    p = r["p"]
    fam = fams[p["fam"]]
    fam_name = fam[lang] + (("·정예" if lang == "ko" else "·Elite") if p["elite"] else "")
    lv = f"Lv {p['lo']}-{p['hi']}" if p["hi"] != p["lo"] else f"Lv {p['lo']}"
    speed = f"{p['spd']:.1f}"
    color = "#cc66ff" if p["rare"] else "#60cea3"
    lines = [f'<div style="color:{color};font-size:15px">{esc(r["name"])}</div>']
    lines.append(f'<div style="color:#edf4f7">{esc(L["locCountFmt"].replace("%s", r["zone"], 1).replace("%d", str(r["count"])))}</div>')
    lines.append(f'<div style="color:#60cea3">{esc(L["petLineFmt"].replace("%s", fam_name, 1).replace("%s", lv, 1).replace("%s", speed, 1))}</div>')
    diet = fam["dietKo"] if lang == "ko" else fam["dietEn"]
    pct = lambda v: str(math.floor(v * 100 + 0.5))
    lines.append(f'<div style="color:#c7dbe6">{esc(L["petDietFmt"].replace("%s", diet, 1).replace("%d%%", pct(fam["dmg"]) + "%", 1).replace("%d%%", pct(fam["arm"]) + "%", 1).replace("%d%%", pct(fam["hp"]) + "%", 1))}</div>')
    names = []
    for sid in p["skills"]:
        s = skills.get(sid)
        if s:
            names.append(s[lang] + ((f" {s['rank']}등급" if lang == "ko" else f" {s['rank']}") if s["rank"] else ""))
    if names:
        lines.append(f'<div style="color:#f1bd57">{esc(L["petSkillFmt"].replace("%s", ", ".join(names)))}</div>')
    lines.append(f'<div style="color:#a7b9c5">{esc(L["rowTipClick"])}</div>')
    return "".join(lines)


def search_panel(ctx, lang, x0, y0, results, selected):
    """368 x 390 panel: header 30, category tabs 54 x 20, search box 264 x 22, rows 324 x 25 every 27."""
    th, L = ctx["theme"], ctx["L"][lang]
    W, H = 368, 390
    p = []
    p.append(box(1, 1, W - 2, 30, f"background:{css(th['bgSub'])}"))
    p.append(box(1, 31, W - 2, 1, f"background:{css(th['accent'])}"))
    p.append(f'<div class="t" style="left:{px(11)};top:{px(16)};transform:translate(0,-50%);font-size:{px(12.5)};color:{css(th["accent"])};{SHADOW}">{esc(L["title"])}</div>')
    close_x = W - 1 - 5 - 20
    p.append(box(close_x, 6, 20, 20, f"background:rgba(18,24,31,.9);border:1px solid {css(th['border'])};display:flex;align-items:center;justify-content:center",
                 f'<span style="font-size:{px(10)};color:{css(th["muted"])}">X</span>'))
    gw = 40 if lang == "ko" else 58
    p.append(box(close_x - 4 - gw, 6, gw, 20, f"background:rgba(18,24,31,.9);border:1px solid {css(th['border'])};display:flex;align-items:center;justify-content:center",
                 f'<span style="font-size:{px(10)};color:{css(th["text"])}">{esc(L["settings"])}</span>'))
    cats = ["catAll", "catMonster", "catNpc", "catObj", "catQuest", "catItem"]
    for i, c in enumerate(cats):
        active = i == 0
        bg = "rgba(36,61,77,.96)" if active else css(th["bgSub"])
        bd = css(th["accent"]) if active else css(th["border"])
        col = css(th["accent"]) if active else css(th["muted"])
        p.append(box(12 + i * 58, 36, 54, 20, f"background:{bg};border:1px solid {bd};display:flex;align-items:center;justify-content:center",
                     f'<span class="fit" data-fit="{50 * S:.1f}" style="font-size:{px(10)};color:{col};white-space:nowrap">{esc(L[c])}</span>'))
    p.append(box(12, 62, 264, 22, f"background:rgba(12,17,22,.96);border:1px solid {css(th['accent'])};display:flex;align-items:center;padding-left:{px(6)}",
                 f'<span style="font-size:{px(12)};color:{css(th["text"])}">{esc(T[lang]["query"])}<span style="color:{css(th["accent"])}">|</span></span>'))
    p.append(box(12 + 264 + 6, 62, 74, 22, f"background:{css(th['bgSub'])};border:1px solid {css(th['border'])};display:flex;align-items:center;justify-content:center",
                 f'<span class="fit" data-fit="{70 * S:.1f}" style="font-size:{px(10.5)};color:{css(th["text"])};white-space:nowrap">{esc(L["clearPins"])}</span>'))
    rows = results[:10]
    anchors = {}
    for i, r in enumerate(rows):
        idx = i + 1
        if r["p"]["en"] == selected:
            bg = "rgba(75,200,232,.24)"
            anchors["sel"] = (x0 + (12 + 324) * S, y0 + (90 + i * 27 + 12) * S)
        else:
            bg = f"rgba(29,40,49,{.75 if idx % 2 == 0 else .45})"
        p.append(box(12, 90 + i * 27, 324, 25, f"background:{bg};display:flex;align-items:center;padding:0 {px(8)};overflow:hidden",
                     f'<span style="font-size:{px(10)};white-space:nowrap;overflow:hidden;text-overflow:ellipsis;{SHADOW}">{row_html(r)}</span>'))
    # scroll bar (12 wide, right edge of the list)
    lh = H - 90 - 28
    p.append(box(W - 12 - 12, 92, 12, lh - 4, "background:rgba(18,24,31,.8)"))
    p.append(box(W - 12 - 10, 94, 8, max(18, (lh - 8) * 10 / max(10, len(results))), "background:#7d8d98;border-radius:3px"))
    status = L["resultsFmt"].replace("%d", "{}").format(len(results), 1, min(10, len(results)))
    p.append(f'<div class="t" style="left:{px(12)};top:{px(H - 8)};transform:translate(0,-100%);font-size:{px(10.5)};color:{css(th["muted"])};{SHADOW}">{esc(status)}</div>')
    html_ = (f'<div class="abs" style="left:{x0}px;top:{y0}px;width:{px(W)};height:{px(H)};background:{css(th["bg"])};'
             f'border:1px solid {css(th["border"])};z-index:10">' + "".join(p) + "</div>")
    anchors.update({"tabs": (x0 + W * S, y0 + 46 * S), "edit": (x0 + W * S, y0 + 73 * S)})
    return html_, anchors, (W * S, H * S)


# ---------------------------------------------------------------------------
# World map (simplified art) with the addon's marks
# ---------------------------------------------------------------------------
BOAT_ICON = "Transit-Boat.png"
# a character with Herbalism and Mining: (kind, x %, y %, skill high enough)
GATHER_SPOTS = [("herb", 42.5, 82.0, True), ("herb", 48.0, 86.5, True), ("ore", 53.5, 80.5, True),
                ("herb", 58.0, 87.0, True), ("ore", 61.0, 79.0, False)]
HERB_SVG = ('<svg viewBox="0 0 20 20" width="100%" height="100%"><rect width="20" height="20" fill="#2f4a22"/>'
            '<g fill="#e9d36a"><circle cx="10" cy="5.5" r="3"/><circle cx="14.5" cy="9" r="3"/><circle cx="12.5" cy="14" r="3"/>'
            '<circle cx="7.5" cy="14" r="3"/><circle cx="5.5" cy="9" r="3"/></g><circle cx="10" cy="10" r="2.4" fill="#b8542a"/></svg>')
ORE_SVG = ('<svg viewBox="0 0 20 20" width="100%" height="100%"><rect width="20" height="20" fill="#3b332c"/>'
           '<path d="M3 14 L7 6 L13 5 L17 11 L13 16 L6 17 Z" fill="#c07a45" stroke="#6b4022" stroke-width="1"/>'
           '<path d="M7 6 L10 11 L13 5 M10 11 L6 17 M10 11 L17 11" stroke="#e7a56c" stroke-width=".8" fill="none"/></svg>')


def map_scene(ctx, lang, x0, y0, w, h):
    th, L = ctx["theme"], ctx["L"][lang]
    t = T[lang]
    TB = 30
    cw, ch = w, h - TB
    cx0, cy0 = x0, y0 + TB

    def M(mx, my):  # map percent -> page px
        return cx0 + mx / 100 * cw, cy0 + my / 100 * ch

    parts = []
    terrain = (f'<svg class="abs" style="left:{cx0}px;top:{cy0}px" width="{cw}" height="{ch}" viewBox="0 0 100 100" preserveAspectRatio="none">'
               '<defs><radialGradient id="sv" cx="40%" cy="45%" r="75%"><stop offset="0" stop-color="#a98d56"/><stop offset="1" stop-color="#7d6a3e"/></radialGradient></defs>'
               '<rect width="100" height="100" fill="url(#sv)"/>'
               '<path d="M66 0 Q63 20 66 38 Q62 55 67 72 Q64 88 68 100 H100 V0 Z" fill="#3f6f8c"/>'
               '<path d="M66 0 Q63 20 66 38 Q62 55 67 72 Q64 88 68 100" fill="none" stroke="#d8c48e" stroke-width=".6" opacity=".6"/>'
               '<path d="M0 0 H30 Q24 10 16 14 Q8 18 0 16 Z" fill="#5f7a3c" opacity=".75"/>'
               '<path d="M18 100 Q24 80 22 70 Q30 64 40 70 Q46 82 44 100 Z" fill="#8a6e3f" opacity=".7"/>'
               '<path d="M51.5 0 V100 M8 30.2 H63.5" stroke="#c9ad73" stroke-width=".7" fill="none"/>'
               '<path d="M51.5 30.2 Q56 34 63.5 38.8" stroke="#c9ad73" stroke-width=".5" fill="none"/>'
               '<g fill="#6c7a3a" opacity=".85"><circle cx="30" cy="22" r="1.4"/><circle cx="44" cy="12" r="1.1"/><circle cx="58" cy="52" r="1.3"/>'
               '<circle cx="36" cy="58" r="1.2"/><circle cx="54" cy="80" r="1.4"/><circle cx="12" cy="44" r="1.2"/></g>'
               '<g fill="#8d8478" stroke="#3a352e" stroke-width=".25"><rect x="50.3" y="28.6" width="1.4" height="1.6"/><rect x="52.2" y="29.2" width="1.2" height="1.4"/></g>'
               '</svg>')
    parts.append(terrain)
    # unexplored area, revealed with the light blue tint
    parts.append(f'<svg class="abs" style="left:{cx0}px;top:{cy0}px" width="{cw}" height="{ch}" viewBox="0 0 100 100" preserveAspectRatio="none">'
                 '<path d="M4 0 H26 Q25 10 18 13 Q9 15 3 9 Z" fill="rgba(110,175,255,.34)" stroke="rgba(160,205,255,.6)" stroke-width=".25"/></svg>')
    # title bar of the map window
    parts.append(f'<div class="abs" style="left:{x0}px;top:{y0}px;width:{w}px;height:{TB}px;background:linear-gradient(#26313b,#161d24);border-bottom:2px solid #5d6d7a"></div>')
    parts.append(f'<div class="t" style="left:{x0 + w / 2}px;top:{y0 + TB / 2}px;transform:translate(-50%,-50%);font-size:15px;color:#ffd100;{OUTLINE}">{esc(t["mapTitle"])}</div>')
    # zone label: name, level range in the level colour, fishing skill
    lo, hi, fish = ctx["levels"][MAP_ID]
    lvl_col = "#ff5050" if PLAYER_LEVEL < lo - 3 else "#ff9933" if PLAYER_LEVEL < lo else "#55e673" if PLAYER_LEVEL <= hi + 2 else "#99aabb"
    zname = ctx["zones"][ZONE_KEY][lang]
    zx, zy = x0 + w * 0.5, cy0 + 22
    parts.append(f'<div class="t" style="left:{zx}px;top:{zy}px;transform:translate(-50%,0);font-size:30px;color:#ffd100;{OUTLINE}">{esc(zname)}</div>')
    parts.append(f'<div class="t" style="left:{zx}px;top:{zy + 36}px;transform:translate(-50%,0);font-size:20px;color:{lvl_col};{OUTLINE}">({lo}-{hi})</div>')
    parts.append(f'<div class="t" style="left:{zx}px;top:{zy + 60}px;transform:translate(-50%,0);font-size:14px;color:#7ecbe0;{OUTLINE}">{esc(L["fishingSkill"])} {fish}</div>')
    anchors = {"zone": (zx - 100, zy + 40)}
    # transit pins (20 x 20)
    fc = ctx["factions"]
    for i, tr in enumerate(ctx["transit"]):
        tx, ty = M(tr["x"], tr["y"])
        col = fc.get(tr["fac"], fc["N"])
        parts.append(f'<div class="abs" style="left:{tx - 10 * S:.1f}px;top:{ty - 10 * S:.1f}px;width:{px(20)};height:{px(20)};'
                     f'background:url({ctx["icons"][tr["kind"]]}) center/contain no-repeat;filter:drop-shadow(0 0 2px #000)"></div>')
        if i == 0:
            anchors["transit"] = (tx, ty)
            name = tr["ko"] if lang == "ko" else tr["en"]
            fac = {"A": ("얼라이언스", "Alliance"), "H": ("호드", "Horde")}.get(tr["fac"], ("중립", "Neutral"))[0 if lang == "ko" else 1]
            parts.append(f'<div class="tip" style="left:{tx + 18}px;top:{ty + 14}px">'
                         f'<div style="color:{css(th["accent"])};font-size:15px">{esc(name)}</div>'
                         f'<div style="color:{css(col)}">[{esc(fac)}] ({tr["x"]:.1f}, {tr["y"]:.1f})</div>'
                         f'<div style="color:{css(th["muted"])}">{esc(L["transitClick"])}</div>'
                         f'<div style="color:{css(th["muted"])}">EzWoW - Map Finder</div></div>')
    # quest marks (Modules/QuestLogPins.lua, Modules/QuestObjectivePins.lua)
    qc = ctx["qcolors"]
    DS = S
    dots = [(44.2, 46.0), (45.6, 48.4), (43.1, 49.6), (46.8, 45.2), (44.9, 51.3)]
    pts = [M(a, b) for a, b in dots]
    col = "#%02x%02x%02x" % tuple(round(v * 255) for v in qc[1])
    lines = "".join(f'<line x1="{a[0]}" y1="{a[1]}" x2="{b[0]}" y2="{b[1]}" stroke="{col}" stroke-opacity=".45" stroke-width="{1.2 * DS:.1f}"/>'
                    for a, b in ((pts[0], pts[1]), (pts[0], pts[3]), (pts[1], pts[2]), (pts[1], pts[4]), (pts[2], pts[4])))
    parts.append(f'<svg class="abs" style="left:0;top:0;overflow:visible" width="1" height="1">{lines}</svg>')
    for x, y in pts:
        parts.append(disc(x, y, 7 * DS, "#000", .95) + disc(x, y, 4 * DS, col))
    qx, qy = M(54.2, 27.4)
    parts.append(disc(qx, qy, 16 * DS, "rgb(242,217,115)", .95) + disc(qx, qy, 14 * DS, "rgb(20,15,10)", .92)
                 + f'<div class="t" style="left:{qx}px;top:{qy + 0.5:.1f}px;transform:translate(-50%,-50%);font-size:{14 * DS:.0f}px;font-weight:800;color:#ffd200;text-shadow:0 0 2px #000">?</div>')
    hx, hy = pts[3]
    parts.append(f'<div class="tip" style="left:{hx + 12}px;top:{hy - 20}px">'
                 f'<div style="color:{col};font-size:15px">{esc(t["quest"])}</div>'
                 f'<div style="color:#edf4f7">&nbsp;&nbsp;{esc(t["questObj"])}</div>'
                 f'<div style="color:{css(th["muted"])}">{esc(L["questObjHint"])}</div>'
                 f'<div style="color:{css(th["muted"])}">EzWoW - Map Finder</div></div>')
    anchors["quest"] = (pts[2][0] - 26, pts[2][1] + 4)
    anchors["questQ"] = (qx, qy)
    # herb / ore spots (Modules/ServiceNpcPins.lua GatherPins): coloured rim, round icon,
    # dimmed and desaturated when the skill is too low
    gs = 18 * S  # drawn larger than in game so the icons read at this size
    for kind, gx, gy, can in GATHER_SPOTS:
        cx_, cy_ = M(gx, gy)
        col = ctx["gather"][kind]
        icon = HERB_SVG if kind == "herb" else ORE_SVG
        parts.append(f'<div class="abs" style="left:{cx_ - gs / 2:.1f}px;top:{cy_ - gs / 2:.1f}px;width:{gs:.1f}px;height:{gs:.1f}px;border-radius:50%;'
                     f'background:{css(col, 1 if can else .5)};opacity:{1 if can else .55};padding:{1.5 * S:.1f}px;'
                     f'filter:{"none" if can else "grayscale(1)"} drop-shadow(0 0 1px #000)">'
                     f'<div style="width:100%;height:100%;border-radius:50%;overflow:hidden">{icon}</div></div>')
    anchors["gather"] = (M(*GATHER_SPOTS[0][1:3])[0] - 30, M(*GATHER_SPOTS[0][1:3])[1])
    # coordinate bar (250 x 20, bottom of the map)
    bw, bh = 250 * S, 20 * S
    bx, by = x0 + w / 2 - bw / 2, y0 + h - 8 * S - bh
    coord = (f'<span style="color:#4bc8e8">{esc(L["playerCoord"])}:</span> <span style="color:#edf4f7">{PLAYER_POS[0]:.1f}, {PLAYER_POS[1]:.1f}</span>&nbsp;&nbsp;&nbsp;'
             f'<span style="color:#4bc8e8">{esc(L["cursorCoord"])}:</span> <span style="color:#edf4f7">{CURSOR_POS[0]:.1f}, {CURSOR_POS[1]:.1f}</span>')
    parts.append(f'<div class="abs" style="left:{bx}px;top:{by}px;width:{bw}px;height:{bh}px;background:rgba(18,24,31,.82);border:1px solid rgba(52,76,91,.9);'
                 f'display:flex;align-items:center;justify-content:center;font-size:{px(10)};white-space:nowrap;{SHADOW}"><span>{coord}</span></div>')
    anchors["coords"] = (bx - 24, by + bh / 2)
    # player arrow
    ppx, ppy = M(*PLAYER_POS)
    parts.append(f'<svg class="abs" style="left:{ppx - 9}px;top:{ppy - 11}px" width="18" height="22" viewBox="0 0 18 22">'
                 '<path d="M9 1 L17 20 L9 15 L1 20 Z" fill="#f2f2f2" stroke="#222" stroke-width="1.5" transform="rotate(-70 9 12)"/></svg>')
    return parts, anchors, M


def selected_pin(x, y):
    """Search pin (32 x 46): pulse ring 16, target dot 9/5, bouncing arrow above."""
    k = S
    return (disc(x, y, 22 * k, "rgba(75,200,232,.25)") + disc(x, y, 16 * k, "rgba(75,200,232,.55)")
            + disc(x, y, 9 * k, "#062430") + disc(x, y, 5 * k, "#4bc8e8")
            + f'<svg class="abs" style="left:{x - 12 * k}px;top:{y - 40 * k}px" width="{24 * k}" height="{30 * k}" viewBox="0 0 24 30">'
              '<path d="M8 1 H16 V14 H22 L12 27 L2 14 H8 Z" fill="#4bc8e8" stroke="#062430" stroke-width="2" stroke-linejoin="round"/></svg>')


def rare_card(ctx, lang, x, y, entry):
    th, L = ctx["theme"], ctx["L"][lang]
    rc = "rgb(204,102,255)"
    zname = ctx["zones"][entry["zone"]][lang]
    _, sx, sy = entry["spawns"][0]
    name = entry["ko"] if lang == "ko" else entry["en"]
    p = [box(1, 1, 4, 72, f"background:{rc}"),
         f'<img class="abs" src="{ctx["icon"]}" style="left:{px(14)};top:{px(22)};width:{px(30)};height:{px(30)}">',
         f'<div class="t" style="left:{px(54)};top:{px(18)};font-size:{px(10.5)};color:{rc};{SHADOW}">{esc(L["rareTitle"])}</div>',
         f'<div class="t" style="left:{px(54)};top:{px(32)};font-size:{px(12.5)};color:{css(th["text"])};{SHADOW}">{esc(name)}</div>',
         f'<div class="t" style="left:{px(54)};top:{px(48)};font-size:{px(10)};color:{css(th["muted"])};{SHADOW}">{esc(zname)} · {sx * 100:.1f}, {sy * 100:.1f}</div>',
         box(320 - 12 - 86, 37 - 11 + 4, 86, 22, f"background:rgba(36,61,77,.96);border:1px solid {css(th['accent'])};display:flex;align-items:center;justify-content:center",
             f'<span class="fit" data-fit="{80 * S:.1f}" style="font-size:{px(10)};color:{css(th["accent"])};white-space:nowrap">{esc(L["rareShowMap"])}</span>'),
         box(320 - 6 - 18, 6, 18, 18, f"background:{css(th['bgSub'])};border:1px solid {css(th['border'])};display:flex;align-items:center;justify-content:center",
             f'<span style="font-size:{px(10)};color:{css(th["text"])}">x</span>')]
    return (f'<div class="abs" style="left:{x}px;top:{y}px;width:{px(320)};height:{px(74)};background:{css(th["bg"])};border:1px solid {css(th["border"])};z-index:12">'
            + "".join(p) + "</div>")


def ui_page(lang, ctx):
    t = T[lang]
    parts = []
    mx, my, mw, mh = 50, 160, 1500, 760
    scene, anchors, M = map_scene(ctx, lang, mx, my, mw, mh)
    parts.append(f'<div class="abs" style="left:{mx}px;top:{my}px;width:{mw}px;height:{mh}px;border:2px solid #5d6d7a;border-radius:6px;overflow:hidden;background:#0e1418">'
                 f'<div class="abs" style="left:{-mx}px;top:{-my}px;width:{PAGE_W}px;height:2000px">{"".join(scene)}</div></div>')
    results = pet_results(ctx, lang)
    sel = next(r for r in results if r["p"]["en"] == SELECTED_EN)
    # selected result on the map
    _, sx, sy = sel["p"]["spawns"][0]
    spx, spy = M(sx * 100, sy * 100)
    parts.append(selected_pin(spx, spy))
    # dock button (28 x 28) at the bottom-left of the canvas, panel to its right
    bx, by = mx + 12, my + mh - 12 - 28 * S
    parts.append(f'<img class="abs" src="{ctx["icon"]}" style="left:{bx}px;top:{by}px;width:{px(28)};height:{px(28)};z-index:11;'
                 f'box-shadow:0 0 0 1px #000">')
    pw, ph = 368 * S, 390 * S
    px0, py0 = bx + 28 * S + 6 * S, by + 28 * S - ph
    panel, pa, _ = search_panel(ctx, lang, px0, py0, results, SELECTED_EN)
    parts.append(panel)
    tip_y = pa["sel"][1] - 14
    parts.append(f'<div class="tip" style="left:{pa["sel"][0] + 34}px;top:{tip_y:.0f}px">{row_tooltip(ctx, lang, sel)}</div>')
    # rare alert card
    rare = next(p for p in ctx["pets"][2] if p["en"] == RARE_EN)
    card_x, card_y = mx + mw - 320 * S - 30, my + 50
    parts.append(rare_card(ctx, lang, card_x, card_y, rare))

    calls = [
        (bx + 14 * S, by - 22),                         # 1 dock button
        (pa["tabs"][0] + 20, pa["tabs"][1]),            # 2 tabs
        (pa["edit"][0] + 20, pa["edit"][1] + 4),        # 3 search box
        (pa["sel"][0] + 14, pa["sel"][1]),              # 4 beast info
        (spx + 30, spy - 32),                           # 5 pin on the map
        anchors["zone"],                                # 6 zone info
        anchors["coords"],                              # 7 coordinates
        (anchors["transit"][0] - 28, anchors["transit"][1]),  # 8 transport
        M(28, 5),                                       # 9 unexplored tint
        (card_x - 22, card_y + 37 * S),                 # 10 rare alert
        anchors["quest"],                               # 11 quest marks
        anchors["gather"],                              # 12 herb and ore spots
    ]
    for i, (x, y) in enumerate(calls, 1):
        parts.append(f'<div class="call" style="left:{x - 15:.0f}px;top:{y - 15:.0f}px">{i}</div>')
    notes_top = my + mh + 34
    half = 6
    parts.append(f'<div class="notes" style="left:50px;top:{notes_top:.0f}px;width:720px">{note_html(1, t["notes"][:half])}</div>')
    parts.append(f'<div class="notes" style="left:820px;top:{notes_top:.0f}px;width:730px">{note_html(half + 1, t["notes"][half:])}</div>')
    nh = max(notes_height(t["notes"][:half], 680), notes_height(t["notes"][half:], 690))
    page_h = notes_top + nh + 70
    parts.append(f'<div class="abs foot" style="left:50px;top:{page_h - 58:.0f}px;width:1500px">{esc(t["foot"])}</div>')
    head = f'<div class="page"><h1>EzWoW - Map Finder</h1><div class="lead">{esc(t["lead"])}</div></div>'
    return head + "".join(parts), page_h


# ---------------------------------------------------------------------------
# Settings window (UI/OptionsWindow.lua)
# ---------------------------------------------------------------------------
CHECK = ('<svg viewBox="0 0 22 22" width="100%" height="100%"><rect x="3.5" y="3.5" width="15" height="15" rx="1.5" fill="#15130f" stroke="#8a7a50" stroke-width="1.4"/>'
         '{mark}</svg>')
MARK = '<path d="M5.5 11.5 L9.5 15.5 L17.5 5.5" fill="none" stroke="#ffd100" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/>'


def settings_window(ctx, lang, x0, y0, managed=False, crop=None):
    th, L, o, d = ctx["theme"], ctx["L"][lang], ctx["options"], ctx["defaults"]
    W, H = o["size"]
    if managed:
        H = o["managedH"]
    acc, text_c, mut = css(th["accent"]), css(th["text"]), css(th["muted"])
    p = []

    def btn(x, y, w, h, label, accent=False, size=10.5):
        bg = "rgba(36,61,77,.96)" if accent else css(th["bgSub"])
        bd = acc if accent else css(th["border"])
        return box(x, y, w, h, f"background:{bg};border:1px solid {bd};display:flex;align-items:center;justify-content:center",
                   f'<span class="fit" data-fit="{(w - 8) * S:.1f}" style="font-size:{px(size)};color:{acc if accent else text_c};white-space:nowrap;{SHADOW}">{esc(label)}</span>')

    # header 56, accent line, icon 28, title, subtitle, close
    p.append(box(1, 1, W - 2, 56, f"background:{css(th['bgSub'])}"))
    p.append(box(1, 55, W - 2, 2, f"background:{acc}"))
    p.append(f'<img class="abs" src="{ctx["icon"]}" style="left:{px(15)};top:{px(15)};width:{px(28)};height:{px(28)}">')
    p.append(f'<div class="t" style="left:{px(49)};top:{px(12)};font-size:{px(14.5)};color:{acc};{SHADOW}">EzWoW - Map Finder</div>')
    p.append(f'<div class="t" style="left:{px(49)};top:{px(32)};font-size:{px(10)};color:{mut};{SHADOW}">{esc(L["subtitle"])}</div>')
    p.append(btn(W - 12 - 24, 14, 24, 24, "X"))
    # section title, line, language
    p.append(f'<div class="t" style="left:{px(20)};top:{px(68)};font-size:{px(12.5)};color:{acc};{SHADOW}">{esc(L["settings"])}</div>')
    p.append(box(20, 85, W - 40, 1, "background:rgba(52,76,91,.85)"))
    p.append(f'<div class="t" style="left:{px(20)};top:{px(93)};font-size:{px(10.5)};color:{mut};{SHADOW}">{esc(L["language"])}</div>')
    p.append(btn(20, 110, 220, 24, f'{L["langAuto"]} ▼'))
    # check rows (UICheckButtonTemplate 22 x 22, label 4 px right)
    for r in o["rows"]:
        if managed and r["field"].startswith("quest"):
            continue
        val = d.get(r["field"])
        on = (val is not False) if r["op"] == "~= false" else (val is True)
        y = r["y"]
        service = r["field"].startswith(("serviceNpc", "gather"))  # placeServiceRows moves both
        if managed and service:
            y -= o["serviceShift"]  # rows move up into the space of the hidden quest rows
        fit = 290 if r["field"] == "serviceNpcPins" else 380
        p.append(box(18, y, 22, 22, "", CHECK.format(mark=MARK if on else "")))
        p.append(f'<div class="t" style="left:{px(44)};top:{px(y + 11)};transform:translate(0,-50%);font-size:{px(10.5)};color:{text_c};{SHADOW}">'
                 f'<span class="fit" data-fit="{fit * S:.1f}" data-min="{10.5 * 0.7 * S:.1f}">{esc(L[r["label"]])}</span></div>')
        if r["field"] == "serviceNpcPins":
            # "Types" button with the per-type checklist
            p.append(btn(W - 20 - o["typesW"], y + 1, o["typesW"], 20, f'{L["serviceNpcTypes"]} ▼', size=10))
    if managed:
        p.append(f'<div class="t" style="left:{px(22)};top:{px(o["noteY"])};font-size:{px(10.5)};color:{mut};{SHADOW}">{esc(L["questManagedByQuest"])}</div>')
    # backdrop slider row
    by = o["backdropY"]
    p.append(f'<div class="t" style="left:{px(22)};top:{px(by + 4)};font-size:{px(10.5)};color:{text_c};{SHADOW}">{esc(L["mapBackdrop"])}</div>')
    p.append(f'<div class="t" style="right:{px(20)};top:{px(by + 4)};font-size:{px(10.5)};color:{acc};{SHADOW}">{esc(L["mapBackdropDefault"])}</div>')
    p.append(box(24, by + 24, 310, 14, f"background:rgba(18,24,31,.9);box-shadow:0 0 0 1px {css(th['border'], .6)}"))
    p.append(box(24 + 310 - 16, by + 24 - 3, 16, 20, "background:linear-gradient(#e8e8e8,#9a9a9a);border:1px solid #333;border-radius:3px"))
    p.append(btn(24 + 310 + 16, by + 24 + 7 - 10, 70, 20, L["mapBackdropDefault"], size=10))
    # bottom buttons and hint
    p.append(btn(20, H - 32 - 26, 194, 26, L["resetPos"]))
    p.append(btn(W - 20 - 194, H - 32 - 26, 194, 26, L["donate"], accent=True))
    hint = f'EzWoW - Map Finder v{ctx["version"]}  ·  {L["help"]}'
    p.append(f'<div class="t" style="left:{px(W / 2)};bottom:{px(10)};transform:translate(-50%,0);font-size:{px(9)};color:{mut};{SHADOW}">'
             f'<span class="fit" data-fit="{(W - 20) * S:.1f}">{esc(hint)}</span></div>')
    inner = "".join(p)
    if crop:
        top = crop
        return (f'<div class="abs" style="left:{x0}px;top:{y0}px;width:{px(W)};height:{px(H - top)};overflow:hidden;background:{css(th["bg"])};'
                f'border:1px solid {css(th["border"])};border-top:1px dashed #7d8d98">'
                f'<div class="abs" style="left:0;top:{px(-top)};width:{px(W)};height:{px(H)}">{inner}</div></div>'), H - top
    return (f'<div class="abs" style="left:{x0}px;top:{y0}px;width:{px(W)};height:{px(H)};background:{css(th["bg"])};border:1px solid {css(th["border"])}">'
            + inner + "</div>"), H


def settings_page(lang, ctx):
    t = T[lang]
    o = ctx["options"]
    W, H = o["size"]
    ox, oy = 60, 150
    win, _ = settings_window(ctx, lang, ox, oy)
    ys = {r["field"]: r["y"] for r in o["rows"]}
    spans = [(93, 134), (ys["autoAlign"], ys["autoWaypoint"] + 22), (ys["revealMap"], ys["revealTint"] + 22),
             (ys["showCoords"], ys["showZoneLevels"] + 22), (ys["noMapFade"], ys["showTransit"] + 22),
             (ys["rareAlert"], ys["rareAlertSound"] + 22), (ys["questLogPins"], ys["questObjectivePins"] + 22),
             (ys["serviceNpcPins"], ys["serviceNpcPinsZones"] + 22), (ys["gatherPins"], ys["gatherAutoTrack"] + 22), (H - 58, H)]
    calls = "".join(f'<div class="call" style="left:{ox + W * S + 18:.0f}px;top:{oy + (a + b) / 2 * S - 15:.0f}px">{i}</div>'
                    for i, (a, b) in enumerate(spans, 1))
    nx = ox + W * S + 80
    nw = PAGE_W - nx - 50
    notes = note_html(1, t["sNotes"]) + note_html(0, [t["sHand"]], info=True)
    notes_h = notes_height(t["sNotes"] + [t["sHand"]], nw - 40)
    crop_top = ys["rareAlert"] - 8
    inset, ih = settings_window(ctx, lang, nx + 40, oy + 10 + notes_h + 12, managed=True, crop=crop_top)
    page_h = max(oy + H * S, oy + 10 + notes_h + 12 + ih * S) + 80
    body = (f'<div class="page"><h1>EzWoW - Map Finder <span class="badge">{esc(t["sTitle"])}</span></h1>'
            f'<div class="lead">{esc(t["sLead"])}</div></div>' + win + calls
            + f'<div class="notes" style="left:{nx:.0f}px;top:{oy + 10}px;width:{nw:.0f}px">{notes}</div>' + inset
            + f'<div class="abs foot" style="left:50px;top:{page_h - 44:.0f}px">{esc(t["sFoot"])}</div>')
    return body, page_h


# ---------------------------------------------------------------------------
def find_chrome():
    cands = [os.environ.get("CHROME"), r"C:\Program Files\Google\Chrome\Application\chrome.exe",
             r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
             shutil.which("chrome"), shutil.which("google-chrome"), shutil.which("chromium")]
    for c in cands:
        if c and Path(c).exists():
            return c
    sys.exit("Chrome not found (set CHROME=<path to chrome>)")


def render(chrome, html_text, out_png, height, tmp):
    page = Path(tmp) / (out_png.stem + ".html")
    page.write_text(html_text, encoding="utf-8")
    before = out_png.stat().st_mtime_ns if out_png.exists() else 0
    proc = subprocess.Popen([chrome, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
                             f"--user-data-dir={Path(tmp) / 'chrome_profile'}", f"--window-size={PAGE_W},{int(height)}",
                             "--virtual-time-budget=2000", f"--screenshot={out_png}", page.as_uri()],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    # Chrome sometimes keeps running after the screenshot is saved: stop waiting
    # once the file is written and no longer growing.
    deadline, last = time.time() + 180, -1
    while proc.poll() is None and time.time() < deadline:
        time.sleep(0.5)
        if out_png.exists() and out_png.stat().st_mtime_ns != before:
            size = out_png.stat().st_size
            if size and size == last:
                break
            last = size
    if proc.poll() is None:
        proc.kill()
        proc.wait()
    if not (out_png.exists() and out_png.stat().st_mtime_ns != before):
        sys.exit(f"screenshot failed: {out_png}")


def data_uri(path):
    return "data:image/png;base64," + base64.b64encode(path.read_bytes()).decode()


def main(root: Path):
    out = root / "docs" / "images"
    out.mkdir(parents=True, exist_ok=True)
    zone_src = read(root, "Data/ZoneAndGatherData.lua")
    pins_src = read(root, "Modules/QuestObjectivePins.lua")
    qblock = re.search(r"^local QUEST_COLORS = \{(.*?)^\}", pins_src, re.S | re.M).group(1)
    ctx = {
        "theme": parse_theme(read(root, "Core/Init.lua")),
        "defaults": parse_db_defaults(read(root, "Core/Init.lua")),
        "L": parse_locales(read(root, "Core/Locales.lua")),
        "options": parse_options(read(root, "UI/OptionsWindow.lua")),
        "version": parse_version(read(root, "EzWoW-MapFinder.toc")),
        "zones": parse_zone_names(zone_src),
        "levels": parse_zone_levels(zone_src),
        "transit": parse_transit(zone_src, MAP_ID),
        "factions": parse_faction_colors(zone_src),
        "pets": parse_pets(read(root, "Database/HunterPets.lua")),
        "gather": parse_gather_colors(read(root, "Modules/ServiceNpcPins.lua")),
        "qcolors": [[float(v) for v in b.split(",")] for b in re.findall(r"\{\s*([\d.,\s]+)\}", qblock)],
        "icon": data_uri(root / "Media" / "Icon.png"),
        "icons": {k: data_uri(root / "Media" / f"Transit-{n}.png") for k, n in
                  (("boat", "Boat"), ("zepp", "Zeppelin"), ("tram", "Tram"), ("portal", "Portal"))},
    }
    chrome = find_chrome()
    tmp = tempfile.mkdtemp(prefix="ezmf_readme_")
    try:
        for lang in ("ko", "en"):
            for name, fn in (("ui", ui_page), ("settings", settings_page)):
                body, h = fn(lang, ctx)
                html_text = (f'<!doctype html><html><head><meta charset="utf-8"><style>{CSS}</style></head>'
                             f'<body style="height:{int(h)}px">{body}{FIT_JS}</body></html>')
                png = out / f"{name}_{lang}.png"
                render(chrome, html_text, png, h, tmp)
                print("wrote", png, int(h))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main(Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve())
