"""Stitch golden cells into labelled contact sheets (out/*.png)."""
import os, sys
from PIL import Image, ImageDraw, ImageFont

P = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CELLS = os.path.join(P, 'test', 'goldens', 'cells')
OUT = os.path.join(P, 'out')
os.makedirs(OUT, exist_ok=True)
SHOTS = ['cal_front_lever', 'cal_strict_muscle_up', 'cal_full_planche', 'cal_handstand', 'cal_pistol_squat',
         'cal_jumping_jack', 'cal_human_flag', 'cal_tuck_front_lever', 'cal_negative_dip', 'cal_dead_hang']
YAWS = [0, 35, 90]
LIGHT = ['cal_front_lever', 'cal_strict_muscle_up', 'cal_pistol_squat', 'cal_human_flag']
THUMB = ['cal_front_lever', 'cal_full_planche', 'cal_handstand', 'cal_pistol_squat', 'cal_human_flag', 'cal_strict_muscle_up']

def font(sz):
    for f in ['/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', '/usr/share/fonts/dejavu/DejaVuSans.ttf']:
        if os.path.exists(f):
            return ImageFont.truetype(f, sz)
    return ImageFont.load_default()

def sheet(prefix, ids, bg, fg, name, cell=320, label_w=170, gap=4):
    hdr = 28
    W = label_w + len(YAWS) * (cell + gap)
    H = hdr + len(ids) * (cell + gap)
    im = Image.new('RGB', (W, H), bg)
    d = ImageDraw.Draw(im)
    f = font(15)
    for c, y in enumerate(YAWS):
        d.text((label_w + c * (cell + gap) + 8, 6), f'yaw {y}°', fill=fg, font=f)
    for r, i in enumerate(ids):
        y0 = hdr + r * (cell + gap)
        d.text((8, y0 + cell // 2 - 9), i.replace('cal_', ''), fill=fg, font=f)
        for c, yaw in enumerate(YAWS):
            pth = os.path.join(CELLS, f'{prefix}_{i}_{yaw}.png')
            if os.path.exists(pth):
                im.paste(Image.open(pth).convert('RGB'), (label_w + c * (cell + gap), y0))
    im.save(os.path.join(OUT, name))
    print('wrote', name, im.size)

sheet('dark', SHOTS, (18, 18, 18), (200, 200, 200), 'sheet_dark.png')
sheet('light', LIGHT, (245, 245, 245), (40, 40, 40), 'sheet_light.png')

# thumbnails at 100x100 (dark row + light row)
tw = 100
im = Image.new('RGB', (len(THUMB) * (tw + 6) + 6, 2 * (tw + 6) + 6), (90, 90, 90))
for c, i in enumerate(THUMB):
    for r, pre in enumerate(['thumb_dark', 'thumb_light']):
        pth = os.path.join(CELLS, f'{pre}_{i}.png')
        if os.path.exists(pth):
            im.paste(Image.open(pth).convert('RGB'), (6 + c * (tw + 6), 6 + r * (tw + 6)))
im.save(os.path.join(OUT, 'thumb_100px.png'))
print('wrote thumb_100px.png', im.size)

# animation strips (8 phases over one loop period)
rows = ['cal_strict_muscle_up', 'cal_jumping_jack']
cw = 200
im = Image.new('RGB', (8 * (cw + 4) + 4, len(rows) * (cw + 4) + 4), (60, 60, 60))
for r, i in enumerate(rows):
    for c in range(8):
        pth = os.path.join(CELLS, f'anim_{i}_{c}.png')
        if os.path.exists(pth):
            im.paste(Image.open(pth).convert('RGB'), (4 + c * (cw + 4), 4 + r * (cw + 4)))
im.save(os.path.join(OUT, 'anim_strip.png'))
print('wrote anim_strip.png', im.size)

# hero renders (640 px): dark-only row and a mixed 2x2 grid
def grid(names, cols, cell, name, gap=4, bg=(60, 60, 60)):
    names = [n for n in names if os.path.exists(os.path.join(CELLS, n + '.png'))]
    if not names:
        return
    rows = (len(names) + cols - 1) // cols
    im = Image.new('RGB', (cols * (cell + gap) + gap, rows * (cell + gap) + gap), bg)
    for i, n in enumerate(names):
        c = Image.open(os.path.join(CELLS, n + '.png')).convert('RGB').resize((cell, cell), Image.LANCZOS)
        im.paste(c, (gap + (i % cols) * (cell + gap), gap + (i // cols) * (cell + gap)))
    im.save(os.path.join(OUT, name))
    print('wrote', name, im.size)

grid(['hero_pistol', 'hero_jj', 'hero_flag'], 3, 640, 'hero_dark.png')
grid(['hero_pistol', 'hero_jj', 'hero_planche', 'hero_flag'], 2, 640, 'hero_mixed.png')
# close-ups / other poses from test/extra_test.dart
grid(sorted(os.path.splitext(f)[0] for f in os.listdir(CELLS) if f.startswith('extra_')), 5, 320, 'extras.png')
