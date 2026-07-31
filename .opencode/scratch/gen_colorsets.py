#!/usr/bin/env python3
"""Generate the 13 PhotoVault colorsets with full double-precision sRGB decimals."""
import json, os

BASE = "/Users/20015659/immich_swiftui/Resources/Assets.xcassets"

# name -> (light_hex, dark_hex)
COLORSETS = {
    "BrandIndigo":      ("4250AF", "6B78D9"),
    "BrandIndigoMuted": ("6B78D9", "8B96E8"),
    "LogoGreen":        ("2E9C4B", "4FCB6E"),
    "LogoYellow":       ("F5A623", "FFB84D"),
    "LogoRedPink":      ("E85D75", "F47A8E"),
    "LogoBlue":         ("3DA9FC", "5BC8FF"),
    "BgPrimary":        ("FFFFFF", "000000"),
    "BgSecondary":      ("F2F2F7", "1C1C1E"),
    "BgTertiary":       ("E5E5EA", "2C2C2E"),
    "SeparatorColor":   ("C6C6C8", "38383A"),
    "TextPrimary":      ("1D1D1F", "F5F5F7"),
    "TextSecondary":    ("6E6E73", "AEAEB2"),
    "TextTertiary":     ("A1A1A6", "636366"),
}

def comp(hexstr):
    r = int(hexstr[0:2], 16) / 255
    g = int(hexstr[2:4], 16) / 255
    b = int(hexstr[4:6], 16) / 255
    return {"alpha": "1.000", "red": repr(r), "green": repr(g), "blue": repr(b)}

def color_obj(hexstr):
    return {"color-space": "srgb", "components": comp(hexstr)}

def contents(light, dark):
    return {
        "colors": [
            {"color": color_obj(light)},
            {"appearances": [{"appearance": "luminosity", "value": "dark"}],
             "color": color_obj(dark)},
        ],
        "info": {"author": "xcode", "version": 1},
    }

for name, (light, dark) in COLORSETS.items():
    d = os.path.join(BASE, name + ".colorset")
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "Contents.json"), "w") as f:
        json.dump(contents(light, dark), f, indent=2)
        f.write("\n")
    print("wrote", d)

# sanity spot-check
with open(os.path.join(BASE, "BrandIndigo.colorset", "Contents.json")) as f:
    c = json.load(f)
    print("BrandIndigo light components:", c["colors"][0]["color"]["components"])
