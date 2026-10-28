"""crop: python3 tool/crop.py in.png out.png x0 y0 x1 y1 (fractions 0..1)"""
import sys
from PIL import Image
im = Image.open(sys.argv[1])
x0, y0, x1, y1 = [float(v) for v in sys.argv[3:7]]
W, H = im.size
im.crop((int(x0 * W), int(y0 * H), int(x1 * W), int(y1 * H))).save(sys.argv[2])
