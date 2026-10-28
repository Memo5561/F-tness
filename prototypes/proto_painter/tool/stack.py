"""Stack strip PNGs vertically: python3 tool/stack.py out.png a.png b.png ..."""
import sys
from PIL import Image
ims = [Image.open(p).convert('RGB') for p in sys.argv[2:]]
w = max(i.width for i in ims)
h = sum(i.height for i in ims)
out = Image.new('RGB', (w, h))
y = 0
for i in ims:
    out.paste(i, (0, y))
    y += i.height
out.save(sys.argv[1])
