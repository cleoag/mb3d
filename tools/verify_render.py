"""FPC Default Scene Verification — comprehensive pixel-level checks"""
import struct, math, sys
from collections import Counter

def load_bmp_pixels(path):
    """Load 24-bit BMP -> 2D list of (R,G,B) tuples, top-down order"""
    with open(path, 'rb') as f:
        f.seek(18)
        w = struct.unpack('<i', f.read(4))[0]
        h = struct.unpack('<i', f.read(4))[0]
        f.seek(54)
        data = f.read()
    row_size = w * 3
    pad = (4 - (row_size % 4)) % 4
    bmp_row = row_size + pad
    pixels = []
    for y in range(h):
        row = []
        bmp_y = h - 1 - y  # BMP is bottom-up
        for x in range(w):
            off = bmp_y * bmp_row + x * 3
            b, g, r = data[off], data[off+1], data[off+2]
            row.append((r, g, b))
        pixels.append(row)
    return pixels, w, h

print("=" * 60)
print("FPC DEFAULT SCENE VERIFICATION REPORT")
print("=" * 60)

# Load both renders
p1, w, h = load_bmp_pixels('fpc_default_run1.bmp')
p2, _, _ = load_bmp_pixels('fpc_default_run2.bmp')

# ==== TEST 1: DETERMINISM ====
print("\n--- TEST 1: DETERMINISM (two identical renders) ---")
diff_count = 0
max_diff = 0
diff_pixels = 0
for y in range(h):
    for x in range(w):
        pdiff = False
        for c in range(3):
            d = abs(p1[y][x][c] - p2[y][x][c])
            if d > 0:
                diff_count += 1
                max_diff = max(max_diff, d)
                pdiff = True
        if pdiff:
            diff_pixels += 1

if diff_count == 0:
    print("  [PASS] Pixel-perfect match: 0 differences across all %d pixels" % (w * h))
else:
    pct = 100.0 * diff_pixels / (w * h)
    print("  [INFO] %d differing pixels (%.2f%%), %d channel diffs, max=%d" % (diff_pixels, pct, diff_count, max_diff))
    if max_diff <= 2 and pct < 5.0:
        print("  [PASS] Within tolerance (multi-thread FPU rounding variance)")
    else:
        print("  [FAIL] Significant non-determinism")

pixels = p1

# ==== TEST 2: GEOMETRY ====
print("\n--- TEST 2: GEOMETRY (center=surface, corners=background) ---")
center = pixels[180][240]
print("  Center (240,180): RGB=(%d,%d,%d)" % center)
corner_labels = ["top-left (0,0)", "top-right (479,0)", "bot-left (0,359)", "bot-right (479,359)"]
corner_coords = [(0, 0), (0, 479), (359, 0), (359, 479)]
for label, (cy, cx) in zip(corner_labels, corner_coords):
    c = pixels[cy][cx]
    print("  %s: RGB=(%d,%d,%d)" % (label, c[0], c[1], c[2]))

# Center should have green/teal surface tones
if center[1] > 50:  # green channel present
    print("  [PASS] Center pixel on fractal surface (green/teal tones)")
else:
    print("  [WARN] Center pixel may not be on surface")

# Corners should be background (blue gradient, no green fractal tones)
corner_ok = True
for label, (cy, cx) in zip(corner_labels, corner_coords):
    c = pixels[cy][cx]
    if c[2] > c[1] and c[2] > c[0]:  # blue dominant = background
        pass
    else:
        corner_ok = False
        print("  [WARN] %s doesn't look like background" % label)
if corner_ok:
    print("  [PASS] All 4 corners are background (blue-dominant)")

# ==== TEST 3: VERTICAL SYMMETRY ====
print("\n--- TEST 3: VERTICAL SYMMETRY (left-right mirror) ---")
sym_diffs = []
for y in range(h):
    for x in range(w // 2):
        xm = w - 1 - x
        for c in range(3):
            sym_diffs.append(abs(pixels[y][x][c] - pixels[y][xm][c]))

avg_sym = sum(sym_diffs) / len(sym_diffs)
max_sym = max(sym_diffs)
exact_pct = 100.0 * sum(1 for d in sym_diffs if d == 0) / len(sym_diffs)

print("  Compared %d channel pairs (full image)" % len(sym_diffs))
print("  Avg left-right diff: %.2f" % avg_sym)
print("  Max left-right diff: %d" % max_sym)
print("  Exact matches: %.1f%%" % exact_pct)

if avg_sym < 2.0:
    print("  [PASS] Strong vertical symmetry")
elif avg_sym < 10.0:
    print("  [PASS] Approximate symmetry (lighting/AO break exact symmetry)")
else:
    print("  [FAIL] Poor symmetry")

# ==== TEST 4: COLOR STATISTICS ====
print("\n--- TEST 4: COLOR STATISTICS ---")
all_colors = set()
ch_sum = [0, 0, 0]
special = {'black': 0, 'white': 0, 'pure_r': 0, 'pure_g': 0, 'pure_b': 0}
for y in range(h):
    for x in range(w):
        r, g, b = pixels[y][x]
        all_colors.add((r, g, b))
        ch_sum[0] += r; ch_sum[1] += g; ch_sum[2] += b
        if r == 0 and g == 0 and b == 0: special['black'] += 1
        if r == 255 and g == 255 and b == 255: special['white'] += 1
        if r == 255 and g == 0 and b == 0: special['pure_r'] += 1
        if r == 0 and g == 255 and b == 0: special['pure_g'] += 1
        if r == 0 and g == 0 and b == 255: special['pure_b'] += 1

total = w * h
print("  Unique colors: %d" % len(all_colors))
print("  Avg RGB: (%.1f, %.1f, %.1f)" % (ch_sum[0]/total, ch_sum[1]/total, ch_sum[2]/total))
print("  Black: %d (%.1f%%)" % (special['black'], 100*special['black']/total))
print("  White: %d (%.1f%%)" % (special['white'], 100*special['white']/total))
print("  Pure R/G/B: %d / %d / %d" % (special['pure_r'], special['pure_g'], special['pure_b']))

color_counts = Counter()
for y in range(h):
    for x in range(w):
        color_counts[pixels[y][x]] += 1
mc_color, mc_count = color_counts.most_common(1)[0]
pct_dom = 100 * mc_count / total
print("  Most common: RGB%s = %d px (%.1f%%)" % (mc_color, mc_count, pct_dom))

issues = []
if len(all_colors) < 1000:
    issues.append("Too few unique colors (%d)" % len(all_colors))
if special['black'] > total * 0.5:
    issues.append("Too many black pixels")
if special['pure_r'] > 100 or special['pure_g'] > 100 or special['pure_b'] > 100:
    issues.append("Anomalous pure-channel pixels")
if pct_dom > 50:
    issues.append("Dominant color > 50%%")

if not issues:
    print("  [PASS] Color distribution healthy")
else:
    for i in issues:
        print("  [FAIL] %s" % i)

# ==== TEST 5: SURFACE COVERAGE ====
print("\n--- TEST 5: SURFACE REGION (fractal occupies center) ---")
# Count pixels that look like fractal surface vs background
# Background: blue dominant, relatively uniform
# Surface: green/teal, varied
surface_total = 0
bg_total = 0
for y in range(h):
    for x in range(w):
        r, g, b = pixels[y][x]
        # Background is blue-dominant with little green; surface has significant green
        if g > 80 and g > b * 0.6 and r < 200:
            surface_total += 1
        else:
            bg_total += 1

pct_surf = 100.0 * surface_total / total
print("  Surface-like pixels: %d (%.1f%%)" % (surface_total, pct_surf))
print("  Background-like pixels: %d (%.1f%%)" % (bg_total, 100 - pct_surf))

if 10 < pct_surf < 70:
    print("  [PASS] Reasonable surface/background ratio for centered Mandelbulb")
elif pct_surf <= 10:
    print("  [FAIL] Too little surface — object may not be rendering")
else:
    print("  [WARN] Very high surface coverage — may be zoomed in too much")

# ==== TEST 6: SILIGHT5 VALIDATION ====
print("\n--- TEST 6: siLight5 BUFFER VALIDATION ---")
with open('silight5_default_run1.txt', 'r') as f:
    sl_text = f.read()

# Parse center pixel values
import re
# Find the (240, 180) block
m = re.search(r'Point \(240, 180\).*?NormalX\s*=\s*(-?\d+).*?NormalY\s*=\s*(-?\d+).*?NormalZ\s*=\s*(-?\d+).*?Zpos\s*=\s*(\d+).*?AmbShadow\s*=\s*(\d+)', sl_text, re.DOTALL)
if m:
    nx, ny, nz = int(m.group(1)), int(m.group(2)), int(m.group(3))
    zpos = int(m.group(4))
    ambsh = int(m.group(5))

    print("  Center normal: (%d, %d, %d)" % (nx, ny, nz))
    # Normal magnitude (SmallInt encoded, max ~32767)
    nmag = math.sqrt(nx*nx + ny*ny + nz*nz)
    print("  Normal magnitude: %.0f (encoded as SmallInt, max=32767)" % nmag)
    print("  Zpos: %d (surface < 32768, bg = 32768)" % zpos)
    print("  AmbShadow: %d (surface < 5000, bg = 5000)" % ambsh)

    if zpos < 32768:
        print("  [PASS] Center pixel is on surface (Zpos=%d < 32768)" % zpos)
    else:
        print("  [FAIL] Center pixel is background")

    if nx != 0 or ny != 0 or nz != 0:
        print("  [PASS] Non-zero surface normal at center")
    else:
        print("  [FAIL] Zero normal at center")

    if ambsh < 5000:
        print("  [PASS] AO shadow active at center (AmbShadow=%d < 5000)" % ambsh)
    else:
        print("  [WARN] No AO at center")

    if nmag > 20000 and nmag < 40000:
        print("  [PASS] Normal magnitude in expected range (%.0f)" % nmag)
    else:
        print("  [WARN] Normal magnitude unusual (%.0f)" % nmag)
else:
    print("  [FAIL] Could not parse center pixel from silight5 file")

# Check a corner pixel (should be background)
m2 = re.search(r'Point \(0, 0\).*?NormalX\s*=\s*(-?\d+).*?NormalY\s*=\s*(-?\d+).*?NormalZ\s*=\s*(-?\d+).*?Zpos\s*=\s*(\d+)', sl_text, re.DOTALL)
if m2:
    cnx, cny, cnz, czpos = int(m2.group(1)), int(m2.group(2)), int(m2.group(3)), int(m2.group(4))
    if czpos == 32768 and cnx == 0 and cny == 0 and cnz == 0:
        print("  [PASS] Corner (0,0) is background (Zpos=32768, normal=0)")
    else:
        print("  [WARN] Corner (0,0) unexpected: Zpos=%d normal=(%d,%d,%d)" % (czpos, cnx, cny, cnz))

# ==== FINAL SUMMARY ====
print("\n" + "=" * 60)
print("VERIFICATION COMPLETE")
print("=" * 60)
