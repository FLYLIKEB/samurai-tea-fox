"""PixelLab의 실제 8프레임 결과만 몬스터 런타임 시트로 반영한다."""
import argparse
import hashlib
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
DIRECTIONS = ('south', 'west', 'east', 'north')

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--raw', type=Path, required=True)
    args = parser.parse_args()
    manifest_path = ROOT / 'assets/asset-manifest.json'
    manifest = json.loads(manifest_path.read_text())
    promoted_path = ROOT / 'assets/promoted-assets-manifest.json'
    promoted = json.loads(promoted_path.read_text())
    metadata = {'generator': 'PixelLab', 'endpoint': '/animate-with-text-v3',
                'directions': list(DIRECTIONS), 'frames_per_direction': 8, 'monsters': []}
    pending = []
    outputs = []
    for idle in manifest['assets']:
        if not idle['id'].startswith('monster_') or not idle['id'].endswith('_front_idle'):
            continue
        src = Path(idle['path'].removeprefix('res://'))
        slug = src.name.split('_front_idle_')[0]
        frames = []
        jobs = []
        for direction in DIRECTIONS:
            folder = args.raw / slug / direction
            paths = [folder / f'frame_{i:02d}.png' for i in range(8)]
            if not all(p.exists() for p in paths):
                pending.append(f'{slug}/{direction}')
                continue
            row = [Image.open(p).convert('RGBA') for p in paths]
            assert all(im.size == (32, 32) for im in row)
            assert len({im.tobytes() for im in row}) > 1, f'복제된 정지 프레임: {slug}/{direction}'
            frames.append(row)
            job = json.loads((folder / 'job_redacted.json').read_text())
            request = json.loads((folder / 'request_redacted.json').read_text())
            jobs.append({**job, 'direction':direction, 'prompt':request['prompt'],
                         'source_sha256':request['source_sha256']})
        if len(frames) != 4:
            continue
        sheet = Image.new('RGBA', (256, 128))
        for y, row in enumerate(frames):
            for x, im in enumerate(row):
                sheet.paste(im, (32*x, 32*y))
        path = src.parent / f'{slug}_walk_4dir_8f_32x32.png'
        outputs.append((idle, path, sheet, jobs))
    if pending:
        raise SystemExit(f'미완료 방향 {len(pending)}개: ' + ', '.join(pending[:8]))
    assert len(outputs) == 21
    manifest['assets'] = [a for a in manifest['assets'] if not (a['id'].startswith('monster_') and a['id'].endswith('_walk_4dir_8f'))]
    for idle, path, sheet, jobs in outputs:
        sheet.save(ROOT / path)
        digest = 'sha256:' + hashlib.sha256((ROOT / path).read_bytes()).hexdigest()
        rgba = 'sha256:' + hashlib.sha256(sheet.tobytes()).hexdigest()
        asset_id = idle['id'].removesuffix('_front_idle') + '_walk_4dir_8f'
        manifest['assets'].append({'id': asset_id, 'name': asset_id, 'status': '완료', 'kind': 'character_animation',
            'path': 'res://' + str(path), 'width':256, 'height':128, 'direction_count':4, 'frame_count':32,
            'frame_grid':{'columns':8,'rows':4,'frame_width':32,'frame_height':32},
            'direction_rows':dict(zip(DIRECTIONS, range(4))), 'alpha_required':True,
            'texture_filter':'nearest','placeholder':False,'source_sha256':digest,'rgba_sha256':rgba,'runtime_scale':1})
        promoted['assets'] = [a for a in promoted['assets'] if a['path'] != str(path)]
        promoted['assets'].append({'path':str(path), 'width':256,'height':128,'mode':'RGBA',
            'alpha_empty':True,'source_sha256':digest,'rgba_sha256':rgba})
        metadata['monsters'].append({'asset_id':asset_id,'path':str(path),'jobs':jobs})
    promoted['total_runtime_pngs'] = len(promoted['assets'])
    for path, data in [(manifest_path,manifest),(promoted_path,promoted),
        (ROOT / 'assets/sprites/characters/monster-walk-production.json',metadata)]:
        path.write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n')
    print('PASS 21종, 84방향, 672프레임 실제 움직임 확인 및 조립')

if __name__ == '__main__':
    main()
