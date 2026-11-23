"""Write the character's paper-doll layers and their wardrobe icons (AV-1).

Every layer is the whole 16 x 16 character cell of Kenney's Roguelike
Characters sheet, enlarged eight times with no smoothing, so a hat is
already on the head and a shirt already on the torso: the app stacks the
layers at one size with no offsets. Each icon is the same layer cut to its
own pixels, so a wardrobe tile and the worn item can never disagree.

    python tools/export_layers.py

Writes mobile/assets/cosmetics/layers/<name>.png and icons/<name>.png, named
body_<id>, outfit_<key> and head_<key>, and tools/art/guide.png, which marks
the head box, the torso box and the feet line for anyone drawing a new item.
Fails, writing nothing, if any layer has a different size from the others or
spills out of its box.
"""
import os
import sys

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHEET = os.path.join(ROOT, "tools/art/kenney-roguelike-characters/roguelikeChar_transparent.png")
LAYERS = os.path.join(ROOT, "mobile/assets/cosmetics/layers")
ICONS = os.path.join(ROOT, "mobile/assets/cosmetics/icons")
GUIDE = os.path.join(ROOT, "tools/art/guide.png")

TILE, PITCH, SCALE = 16, 17, 8

# Where things go on the 16 x 16 cell, as (left, top, right, bottom), right
# and bottom exclusive: headwear above the shoulders (wide enough for wings
# and feathers), a shirt over the torso and down the arms, trousers over the
# legs. The app's debug overlay (character_portrait.dart) draws the same
# boxes; change both together.
HEAD_BOX = (0, 0, 16, 8)
TORSO_BOX = (0, 6, 16, 15)
LEGS_BOX = (3, 13, 13, 16)
FEET_LINE = 16

# A skin tone the sheet does not have, made by recolouring the brown base:
# (outline, fill) from -> to.
DEEP_BROWN = {(107, 84, 52): (72, 52, 34), (159, 124, 77): (116, 84, 55)}

# Bodies: skin cell, hair cell, and an optional recolour of the skin.
BODIES = {
    "body_1": ((0, 0), (19, 0), None),   # light skin, short brown hair
    "body_2": ((0, 1), (24, 4), None),   # tan skin, long black hair
    "body_3": ((0, 2), (23, 4), None),   # brown skin, short black hair
    "body_4": ((0, 2), (26, 5), DEEP_BROWN),  # deep brown skin, black braids
}

# Outfits: the shirt, then the trousers under it.
OUTFITS = {
    "rainbow_hoodie": [(14, 0), (3, 7)],
    "explorer_jacket": [(10, 5), (3, 1)],
    "ninja_outfit": [(14, 5), (3, 0)],
    "pirate_coat": [(6, 0), (3, 3)],
    "superhero_suit": [(10, 0), (3, 6)],
    "space_suit": [(12, 4), (3, 2)],
}

HEADWEAR = {
    "adventure_cap": (31, 8),    # green wide-brimmed hat
    "ninja_headband": (28, 2),   # circlet
    "pirate_hat": (28, 8),       # brown wide-brimmed hat
    "wizard_hat": (30, 8),       # purple wide-brimmed hat
    "superhero_mask": (28, 7),   # feathered headdress
    "space_helmet": (30, 1),     # closed helmet
}


def cell(sheet, col, row):
    x, y = col * PITCH, row * PITCH
    return sheet.crop((x, y, x + TILE, y + TILE))


def recolour(img, mapping):
    out = img.copy()
    px = out.load()
    for y in range(out.height):
        for x in range(out.width):
            r, g, b, a = px[x, y]
            if a and (r, g, b) in mapping:
                px[x, y] = (*mapping[(r, g, b)], a)
    return out


def stack(sheet, cells):
    out = Image.new("RGBA", (TILE, TILE), (0, 0, 0, 0))
    for col, row in cells:
        out.alpha_composite(cell(sheet, col, row))
    return out


def within(img, boxes):
    """Whether every visible pixel of [img] lies inside one of [boxes]."""
    px = img.load()
    for y in range(img.height):
        for x in range(img.width):
            if px[x, y][3] and not any(l <= x < r and t <= y < b for l, t, r, b in boxes):
                return False
    return True


def build(sheet):
    layers = {}
    problems = []

    for key, (skin, hair, mapping) in BODIES.items():
        body = cell(sheet, *skin)
        if mapping:
            body = recolour(body, mapping)
        body.alpha_composite(cell(sheet, *hair))
        layers[key] = body

    for key, cells in OUTFITS.items():
        layer = stack(sheet, cells)
        if not within(layer, [TORSO_BOX, LEGS_BOX]):
            problems.append(f"outfit_{key} reaches outside the torso and legs")
        layers[f"outfit_{key}"] = layer

    for key, at in HEADWEAR.items():
        layer = cell(sheet, *at)
        if not within(layer, [HEAD_BOX]):
            problems.append(f"head_{key} reaches outside the head box")
        layers[f"head_{key}"] = layer

    for name, layer in layers.items():
        if layer.getbbox() is None:
            problems.append(f"{name} is empty")

    sizes = {layer.size for layer in layers.values()}
    if len(sizes) != 1:
        problems.append(f"layers differ in size: {sorted(sizes)}")

    return layers, problems


def enlarge(img):
    return img.resize((img.width * SCALE, img.height * SCALE), Image.NEAREST)


def guide(sheet):
    """The base body with the three boxes and the feet line drawn over it."""
    img = enlarge(cell(sheet, 0, 0))
    canvas = Image.new("RGBA", img.size, (255, 255, 255, 255))
    canvas.alpha_composite(img)
    draw = ImageDraw.Draw(canvas)
    for box, colour in [(HEAD_BOX, (220, 40, 40)), (TORSO_BOX, (40, 90, 220)), (LEGS_BOX, (40, 160, 80))]:
        l, t, r, b = (v * SCALE for v in box)
        draw.rectangle((l, t, r - 1, b - 1), outline=colour, width=2)
    draw.line((0, FEET_LINE * SCALE - 1, canvas.width, FEET_LINE * SCALE - 1), fill=(0, 0, 0), width=2)
    return canvas


def main():
    sheet = Image.open(SHEET).convert("RGBA")
    layers, problems = build(sheet)
    if problems:
        for problem in problems:
            print(f"error: {problem}", file=sys.stderr)
        sys.exit(1)

    os.makedirs(LAYERS, exist_ok=True)
    os.makedirs(ICONS, exist_ok=True)
    for name, layer in layers.items():
        enlarge(layer).save(os.path.join(LAYERS, f"{name}.png"), optimize=True)
        enlarge(layer.crop(layer.getbbox())).save(os.path.join(ICONS, f"{name}.png"), optimize=True)
    guide(sheet).save(GUIDE, optimize=True)

    print(f"{len(layers)} layers at {TILE * SCALE} x {TILE * SCALE}, icons beside them, and the guide")


if __name__ == "__main__":
    main()
