# DEV-84 배치형 시설 에셋 생성 리포트

- 생성일: 2026-09-04
- 생성 도구: built-in image_gen, 대상별 1회 호출
- 정본: Notion DEV-84, 09. 아트디렉션·맵·UI, 🎨 아트 에셋, assets/style/art-style-tokens.json
- Contact sheet: assets/source/imagegen/objects/dev84/dev-84-facility-objects-contact-sheet.png 와 docs/reports/dev-84-facility-objects-contact-sheet.png

## 산중 가마 64x64 오브젝트

- Notion art row: https://app.notion.com/p/3d1373699e6681d2872de9c0e7b5632e
- Notion item row: https://app.notion.com/p/3cd373699e6681078e52ffcf1237456e
- Prompt: 64x64 transparent top-view low mountain kiln, stone/clay/soot, front-facing fixed map object, muted palette, no text/watermark/3/4/isometric.
- Raw: assets/source/imagegen/objects/dev84/mountain_kiln_raw_imagegen_20260904.png
- Runtime: assets/sprites/objects/crafting/mountain_kiln_64x64.png
- Raw source sha256: sha256:3817ef6096dc62c61dce358d22a42494009294a7853d1a09b1826f255aae5002
- Raw RGBA sha256: sha256:383a27558e3957ff6b5d212bf2af3fd81d02b7f728ed4d5389ce4c5f0e72eb42
- Runtime source sha256: sha256:ea67a51920c6745c0dd263d6bf773758f237b54a86f166226044dcdf2d3d17d4
- Runtime RGBA sha256: sha256:a8f6175965ade481538b559ca62271553944782c25e66bea8c7892a52f6e7c8b
- Runtime validation: RGBA 64x64, alpha_bbox=(8, 10, 59, 54), no text/watermark by visual inspection
- Visual judgement: 통과: 낮은 가마 실루엣, 돌/점토 보수와 숯검댕 입구가 1x에서도 구분됨.

## 목재 작업대 64x64 오브젝트

- Notion art row: https://app.notion.com/p/3d1373699e668197ad26ffd4581ca662
- Notion item row: https://app.notion.com/p/3cd373699e6681c589bfc2a50231a98d
- Prompt: 64x64 transparent top-view low wooden workbench, worn rectangular table, cuts/tea stains/small tools, muted palette, no text/watermark/3/4/isometric.
- Raw: assets/source/imagegen/objects/dev84/wooden_workbench_raw_imagegen_20260904.png
- Runtime: assets/sprites/objects/crafting/wooden_workbench_64x64.png
- Raw source sha256: sha256:2fd25176269690cb102a0da6ed0413f717aa3a8d785cc6728c96a674dcd9ddcc
- Raw RGBA sha256: sha256:8b061fed65459f7d1bef28029944576b15d5c4a7a859e9d5d4e5bb27598ecaf2
- Runtime source sha256: sha256:17a4a751cea61887343509f0f41b76f43bba90bb13d0274a5a581c72a9866fe0
- Runtime RGBA sha256: sha256:929711e64439986b552c0c29fbdd35ad4856c506cb55582e1536b3334b790912
- Runtime validation: RGBA 64x64, alpha_bbox=(2, 16, 63, 48), no text/watermark by visual inspection
- Visual judgement: 통과: 낮은 사각 작업대와 작은 도구 흔적이 명확하고 산중 가마와 실루엣이 구분됨.

