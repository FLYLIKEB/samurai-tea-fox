"""생성 프레임을 정수 배율로 모아 육안 검수한다."""
from pathlib import Path
import sys
from PIL import Image, ImageDraw

raw = Path(sys.argv[1])
folders = sorted(p.parent for p in raw.glob('*/*/frame_07.png'))
canvas = Image.new('RGB', (720, max(1, len(folders))*72), '#484848')
draw = ImageDraw.Draw(canvas)
for row, folder in enumerate(folders):
    draw.text((0, row*72), folder.parent.name + '/' + folder.name, fill='white')
    for index in range(8):
        im = Image.open(folder / f'frame_{index:02d}.png').convert('RGBA').resize((64,64), Image.Resampling.NEAREST)
        canvas.paste(im, (205+index*64, row*72), im)
canvas.save('/tmp/monster-walk-preview.png')
