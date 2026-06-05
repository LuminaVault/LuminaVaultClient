#!/usr/bin/env python3
"""Generate the LuminaVault neural-brain app icon candidate.

A stylized brain: a luminous cyan->gold body (split hemispheres + gyri folds)
overlaid with a glowing node/synapse network, on a deep navy radial
background. No text. 1024x1024, opaque (no alpha). Rendered at 2x supersample.
"""
import math
import random
from PIL import Image, ImageDraw, ImageFilter

random.seed(11)

SS = 2
S = 1024 * SS
CX, CY = S // 2, int(0.49 * S)

NAVY_CENTER = (12, 22, 52)
NAVY_EDGE = (3, 5, 13)
CYAN = (0, 212, 255)
GOLD = (245, 170, 40)

BW, BH = int(0.72 * S), int(0.64 * S)        # brain bounding size


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def radial_bg():
    bg = Image.new("RGB", (S, S), NAVY_EDGE)
    px = bg.load()
    maxd = math.hypot(CX, CY)
    for y in range(S):
        for x in range(S):
            d = min(1.0, math.hypot(x - CX, y - CY) / maxd * 1.1)
            px[x, y] = lerp(NAVY_CENTER, NAVY_EDGE, d)
    return bg


def brain_mask():
    m = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(m)
    d.ellipse((CX - BW // 2, CY - BH // 2, CX + BW // 2, CY + BH // 2), fill=255)
    # crown bumps
    br = int(0.115 * S)
    for off in (-0.20, -0.07, 0.07, 0.20):
        bx, by = CX + int(off * S), CY - BH // 2 + int(0.03 * S)
        d.ellipse((bx - br, by - br, bx + br, by + br), fill=255)
    # side lobe bulges
    sr = int(0.10 * S)
    for sx in (CX - BW // 2 + int(0.03 * S), CX + BW // 2 - int(0.03 * S)):
        d.ellipse((sx - sr, CY - sr, sx + sr, CY + sr), fill=255)
    return m


def xcolor(x):
    t = (x - (CX - BW / 2)) / BW
    return lerp(CYAN, GOLD, max(0.0, min(1.0, t)))


def gradient_body(mask):
    """Brain body: horizontal cyan->gold gradient, masked, soft."""
    grad = Image.new("RGB", (S, S))
    gp = grad.load()
    for x in range(S):
        c = xcolor(x)
        for y in range(S):
            gp[x, y] = c
    body = grad.convert("RGBA")
    body.putalpha(mask.point(lambda v: int(v * 0.42)))

    # gyri folds: dark wavy lines carved across the body (inside mask only)
    fold = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    fd = ImageDraw.Draw(fold)
    for row in range(-5, 6):
        y0 = CY + row * 0.072 * S
        amp = 0.022 * S
        pts = []
        for x in range(CX - BW // 2, CX + BW // 2, 6):
            y = y0 + amp * math.sin((x / S) * 22 + row)
            if mask.getpixel((int(x), int(min(S - 1, max(0, y))))) > 128:
                pts.append((x, y))
            else:
                if len(pts) > 1:
                    fd.line(pts, fill=(4, 12, 30, 120), width=max(2, int(0.006 * S)))
                pts = []
        if len(pts) > 1:
            fd.line(pts, fill=(4, 12, 30, 120), width=max(2, int(0.006 * S)))

    body.alpha_composite(fold)
    # central fissure
    cd = ImageDraw.Draw(body)
    cd.line([(CX, CY - 0.30 * S), (CX, CY + 0.31 * S)],
            fill=(3, 9, 24, 200), width=max(4, int(0.016 * S)))
    return body


def rim(mask):
    edge = mask.filter(ImageFilter.FIND_EDGES).filter(ImageFilter.GaussianBlur(0.01 * S))
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.bitmap((0, 0), edge, fill=(120, 230, 255, 255))
    return glow


def inside(mask, x, y):
    return 0 <= x < S and 0 <= y < S and mask.getpixel((int(x), int(y))) > 128


def sample_nodes(mask, n=46, min_dist=0.078 * S, fissure=0.018 * S):
    nodes, tries = [], 0
    while len(nodes) < n and tries < 30000:
        tries += 1
        x = random.uniform(CX - 0.34 * S, CX + 0.34 * S)
        y = random.uniform(CY - 0.32 * S, CY + 0.32 * S)
        if not inside(mask, x, y) or abs(x - CX) < fissure:
            continue
        if all((x - nx) ** 2 + (y - ny) ** 2 > min_dist ** 2 for nx, ny, _ in nodes):
            nodes.append((x, y, 1 if x < CX else 0))
    return nodes


def build_edges(nodes, k=3):
    edges = set()
    for i, (xi, yi, hi) in enumerate(nodes):
        nb = sorted(((((xi - xj) ** 2 + (yi - yj) ** 2), j)
                     for j, (xj, yj, hj) in enumerate(nodes) if j != i and hj == hi))
        for _, j in nb[:k]:
            edges.add(tuple(sorted((i, j))))
    tops = sorted(range(len(nodes)), key=lambda i: nodes[i][1])[:12]
    left = [i for i in tops if nodes[i][2] == 1]
    right = [i for i in tops if nodes[i][2] == 0]
    for li in left[:2]:
        if right:
            rj = min(right, key=lambda r: abs(nodes[r][1] - nodes[li][1]))
            edges.add(tuple(sorted((li, rj))))
    return edges


def draw_network(mask):
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    nodes = sample_nodes(mask)
    for i, j in build_edges(nodes):
        xi, yi, _ = nodes[i]
        xj, yj, _ = nodes[j]
        d.line([(xi, yi), (xj, yj)], fill=xcolor((xi + xj) / 2) + (210,),
               width=max(2, int(0.0038 * S)))
    for x, y, _ in nodes:
        c = xcolor(x)
        r = random.uniform(0.011, 0.019) * S
        d.ellipse((x - r, y - r, x + r, y + r), fill=c + (240,))
        cr = r * 0.42
        d.ellipse((x - cr, y - cr, x + cr, y + cr), fill=(255, 255, 255, 245))
    return layer


def main():
    img = radial_bg().convert("RGBA")
    mask = brain_mask()

    body = gradient_body(mask)
    img.alpha_composite(body.filter(ImageFilter.GaussianBlur(0.012 * S)))
    img.alpha_composite(body)
    img.alpha_composite(rim(mask))

    net = draw_network(mask)
    glow = net.filter(ImageFilter.GaussianBlur(0.016 * S))
    img.alpha_composite(glow)
    img.alpha_composite(glow)
    img.alpha_composite(net)

    flat = Image.new("RGB", (S, S), NAVY_EDGE)
    flat.paste(img.convert("RGB"), (0, 0))
    out = flat.resize((1024, 1024), Image.LANCZOS)
    out.save("/tmp/candidate_neural_brain.png", "PNG")
    print("wrote", out.size, out.mode)


if __name__ == "__main__":
    main()
