"""Report how much of each contact-sheet cell the figure fills (beige body
pixels only, props excluded): bbox height / width fraction and centre."""
import os, sys
import numpy as np
from PIL import Image
P = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CELLS = os.path.join(P, 'test', 'goldens', 'cells')
pre = sys.argv[1] if len(sys.argv) > 1 else 'dark_'
for f in sorted(os.listdir(CELLS)):
    if not f.startswith(pre):
        continue
    a = np.asarray(Image.open(os.path.join(CELLS, f)).convert('RGB')).astype(int)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    body = (r - b > 14) & (r > 60)
    ys, xs = np.nonzero(body)
    if len(ys) == 0:
        print(f, 'no body'); continue
    h, w = a.shape[:2]
    fh = (ys.max() - ys.min() + 1) / h
    fw = (xs.max() - xs.min() + 1) / w
    cy = (ys.max() + ys.min()) / 2 / h
    cx = (xs.max() + xs.min()) / 2 / w
    print(f'{f[len(pre):-4]:34s} height {fh:5.0%}  width {fw:5.0%}  max {max(fh, fw):5.0%}  centre ({cx:.2f}, {cy:.2f})')
