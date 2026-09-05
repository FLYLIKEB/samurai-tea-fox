"""기존 PixelLab 방향 원본으로 실제 걷기 프레임을 생성한다."""
import concurrent.futures
import json
import os
from pathlib import Path
import pixellab_walk_production as p

SOURCE = Path(os.environ.get('MONSTER_ASSET_SOURCE_ROOT', Path(__file__).resolve().parents[2]))
p.ROOT = SOURCE
raw = SOURCE / 'assets/source/imagegen/pixellab-monster-walk-real/raw'
style = json.loads((SOURCE / 'assets/style/art-style-tokens.json').read_text())
env = p.load_env()
key = env['PIXELLAB_API_KEY']
base = env.get('PIXELLAB_API_BASE_URL', p.API_BASE)
directions_root = SOURCE / 'assets/source/imagegen/pixellab-monster-directions-20260905/raw'

class Spec:
    def __init__(self, directory, index):
        self.directory = directory
        self.character_id = directory.name
        self.slug = directory.name
        self.name = directory.name.replace('_', ' ')
        self.identity = self.name
        self.seed_base = 950000 + index * 10
    def source_path(self, direction):
        return self.directory / (direction + '.png')

def generate(spec):
    for direction in p.DIRECTIONS:
        result = p.produce_direction(spec, direction, base, key,
            style['prompt_assembly']['default_positive_prefix'],
            style['prompt_assembly']['default_negative_suffix'],
            True, raw / spec.slug, 5)
        print('DONE', spec.slug, direction, flush=True)

if __name__ == '__main__':
    specs = [Spec(d, i) for i, d in enumerate(sorted(directions_root.iterdir()))
             if (d / 'response.json').exists()]
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        for result in pool.map(generate, specs):
            pass
