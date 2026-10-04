#!/usr/bin/env python3
"""Render MapBlueprint to a top-down PNG for layout inspection.
Usage: luau tools/export_blueprint.luau > build/blueprint.json && python3 tools/map_preview.py
"""
import json, sys, os
from PIL import Image, ImageDraw

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
data = json.load(open(os.path.join(root, "build", "blueprint.json")))
I = data["Island"]
S = 1.0  # px per stud
PAD = 40
W = int((I["maxX"] - I["minX"]) * S) + 2 * PAD
H = int((I["maxZ"] - I["minZ"]) * S) + 2 * PAD
img = Image.new("RGB", (W, H), (40, 90, 110))
d = ImageDraw.Draw(img)

def px(x, z):
    return (PAD + (x - I["minX"]) * S, PAD + (z - I["minZ"]) * S)

def rect(cx, cz, w, dd, fill, outline=None, label=None):
    x1, z1 = px(cx - w / 2, cz - dd / 2)
    x2, z2 = px(cx + w / 2, cz + dd / 2)
    d.rectangle([x1, z1, x2, z2], fill=fill, outline=outline)
    if label:
        d.text((x1 + 3, z1 + 2), label, fill=(0, 0, 0))

# island
d.rectangle([px(I["minX"], I["minZ"]), px(I["maxX"], I["maxZ"])], fill=(214, 206, 190))
# canal
c = data["Canal"]
rect(c["x"], (c["fromZ"] + c["toZ"]) / 2, c["width"], c["toZ"] - c["fromZ"], (40, 90, 110))
# roads
for r in data["Roads"]:
    f, t_ = r["from"], r["to"]
    cx, cz = (f["x"] + t_["x"]) / 2, (f["z"] + t_["z"]) / 2
    w = r["width"] if f["x"] == t_["x"] else abs(t_["x"] - f["x"]) + r["width"]
    dd = r["width"] if f["z"] == t_["z"] else abs(t_["z"] - f["z"]) + r["width"]
    col = (168, 164, 152) if r.get("pedestrian") else ((90, 92, 100) if r.get("elevated") else (44, 46, 50))
    rect(cx, cz, w, dd, col)
    d.text(px(cx - 30, cz - 6), r["name"], fill=(255, 255, 255))
# reserved
style_col = {"Stone": (196, 180, 150), "Warm": (255, 196, 120), "Industrial": (94, 98, 104), "Glass": (170, 210, 220), "Brick": (140, 86, 58), "Yard": (120, 110, 90)}
rect(data["Plaza"]["x"], data["Plaza"]["z"], data["Plaza"]["w"], data["Plaza"]["d"], (200, 196, 180), (0, 0, 0), "Aurora Plaza")
rect(data["Museum"]["x"], data["Museum"]["z"], data["Museum"]["w"], data["Museum"]["d"], (120, 196, 184), (0, 0, 0), "AURORA EXCHANGE")
rect(data["ParkingDeck"]["x"], data["ParkingDeck"]["z"], data["ParkingDeck"]["w"], data["ParkingDeck"]["d"], (150, 150, 150), (0, 0, 0), "Parking Deck")
rect(data["PoliceStation"]["x"], data["PoliceStation"]["z"], data["PoliceStation"]["w"], data["PoliceStation"]["d"], (36, 52, 92), (0, 0, 0), "POLICE")
rect(data["PoliceLot"]["x"], data["PoliceLot"]["z"], data["PoliceLot"]["w"], data["PoliceLot"]["d"], (80, 90, 110), (0, 0, 0), "Lot")
for b in data["Buildings"]:
    rect(b["x"], b["z"], b["w"], b["d"], style_col.get(b["style"], (200, 200, 200)), (0, 0, 0), f'{b["name"]} h{b["h"]}')
for h in data["Hideouts"]:
    rect(h["x"], h["z"], h["w"], h["d"], (122, 86, 56), (0, 0, 0), h["label"])
for cpt in data["StreetCars"]:
    rect(cpt["x"], cpt["z"], 8, 8, (255, 208, 96), (0, 0, 0))
for bol in data["Bollards"]:
    rect(bol["x"], bol["z"], 6, 6, (230, 60, 48))
for l in data["Landmarks"]:
    x, z = px(l["x"], l["z"])
    d.ellipse([x - 4, z - 4, x + 4, z + 4], fill=(255, 96, 160))
    d.text((x + 6, z - 6), l["name"], fill=(80, 0, 40))
lh = data["Lighthouse"]
rect(lh["x"], lh["z"], 16, 16, (255, 255, 255), (0, 0, 0), "LH")
pp = data["PolicePatrol"]
pts = [px(p["x"], p["z"]) for p in pp] + [px(pp[0]["x"], pp[0]["z"])]
d.line(pts, fill=(80, 140, 255), width=2)
out = os.path.join(root, "build", "map_preview.png")
img.save(out)
print("wrote", out)
