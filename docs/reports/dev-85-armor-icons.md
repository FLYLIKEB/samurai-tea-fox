# DEV-85 방어구 3종 아이콘 생성 리포트

- 생성일: 2026-09-04
- 생성 도구: built-in image_gen, 대상별 생성 호출 후 32x32 RGBA 런타임 승격
- 정본: Notion DEV-85, 09. 아트디렉션·맵·UI, 아이템·다구 3행, 🎨 아트 에셋 ART-57~59, assets/style/art-style-tokens.json
- Contact sheet: assets/source/imagegen/items/armor/dev85/dev-85-armor-icons-contact-sheet.png 와 docs/reports/dev-85-armor-icons-contact-sheet.png

## Notion 보강값 확인

- 여행자의 누비옷: 메인 색상 `바랜 회갈색 #8A7E70 · 탁한 아이보리 #C7BDAA · 먹갈색 #3E3934`, 스프라이트 설명 채움 확인.
- 산바람 겹옷: 메인 색상 `탁한 산녹색 #687056 · 회갈색 #756B5F · 바랜 갈색 #9A7A58`, 스프라이트 설명 채움 확인.
- 설죽 덧옷: 메인 색상 `설백색 #C9CBC6 · 옅은 청회색 #8FA2A6 · 먹회색 #4E5556`, 스프라이트 설명 채움 확인.
- 근거: 00은 개별 아이템 값을 아이템·다구 DB에 둔다고 정의하고, 09/12는 32x32 저해상도 픽셀아트·nearest·정본 DB 우선·schema 임의 확장 금지를 요구한다.

## 여행자의 누비옷

- Notion art row: https://app.notion.com/p/3d1373699e6681d18b37e2a0eb2c8ce0
- Notion item row: https://app.notion.com/p/3ce373699e66813c87ded8c7b58f9fb3
- Prompt: 32x32 transparent pixel art icon: folded worn gray-brown quilted clothes, no text, no watermark.
- Raw: assets/source/imagegen/items/armor/dev85/traveler_quilted_clothes_raw_imagegen_20260904.png
- Runtime: res://assets/sprites/items/traveler_quilted_clothes_32x32.png
- Raw source sha256: sha256:db61fe7a35291ae813fa5fb243faff6c8551fc6014c5d4fb9f41364eb06c63b1
- Raw RGBA sha256: sha256:3e81555c774af22f604ed166f6a6e6472ae4760406b75ef01b118187da2fadec
- Runtime source sha256: sha256:ff425798c08f3dbb3de1ab543f46664407c6eabf3486e2a50383b3751670a212
- Runtime RGBA sha256: sha256:0bd803c1b603f4b0fa446650922d83ab6d0ec50504aa0cb216e3d1941a749171
- Runtime validation: RGBA 32x32, visible colors=6, transparent background, no text/watermark by icon construction and local inspection
- Visual judgement: 통과: 접힌 짧은 누비옷, 바랜 회갈색 본체와 밝은 목깃, 1픽셀 누빔 선이 작은 크기에서 구분된다.

## 산바람 겹옷

- Notion art row: https://app.notion.com/p/3d1373699e6681d0a317f106f8553e9b
- Notion item row: https://app.notion.com/p/3ce373699e668120be35d4208f14f2b4
- Prompt: 32x32 transparent pixel art icon: folded mountain layered clothes, muted moss green and gray-brown cloth, visible overlapping edges, no text, no watermark.
- Raw: assets/source/imagegen/items/armor/dev85/mountain_wind_layered_clothes_raw_imagegen_20260904.png
- Runtime: res://assets/sprites/items/mountain_wind_layered_clothes_32x32.png
- Raw source sha256: sha256:768a91e183771943608f8cdd1c5142f9b85aa716c7b32362269b3374bf5fbb78
- Raw RGBA sha256: sha256:c10375119928fde6f9f7a174e1017c8c8149a9a94eebce4583aff15c8013b1ca
- Runtime source sha256: sha256:1dc883d5baf5d65ec90d946f337383430c9284fc97d5d95ca16fd8888f17292b
- Runtime RGBA sha256: sha256:7e6651a4b86606d673763d613971c2fa4c085b1244b7c641e7611f771a8065e9
- Runtime validation: RGBA 32x32, visible colors=6, transparent background, no text/watermark by icon construction and local inspection
- Visual judgement: 통과: 산녹색 겉감과 회갈색 안감의 겹친 가장자리가 여행자의 누비옷과 다른 실루엣으로 읽힌다.

## 설죽 덧옷

- Notion art row: https://app.notion.com/p/3d1373699e6681aeb414e6dd8b2257a1
- Notion item row: https://app.notion.com/p/3ce373699e6681c195f2ff952c156d7d
- Prompt: 32x32 transparent pixel art icon: folded thick snow bamboo overcoat, snow white and pale blue-gray cloth, subtle vertical bamboo weave, no text, no watermark.
- Raw: assets/source/imagegen/items/armor/dev85/snow_bamboo_overcoat_raw_imagegen_20260904.png
- Runtime: res://assets/sprites/items/snow_bamboo_overcoat_32x32.png
- Raw source sha256: sha256:6e80425f9a124c6d55ef426921869a2e4d86bbaa42d3aff7b7edbfff665595f3
- Raw RGBA sha256: sha256:e0782970f0cc5d22c73a263f9282a667e2d1d1554601a750ccd113b8aa0bbf3f
- Runtime source sha256: sha256:0447fcee7d6185a08536d92dfad3df1ad5fd2f903641892df5daca9f2a4ef06a
- Runtime RGBA sha256: sha256:40aa4d9ef0707d375566d9e8087c19e878aa82ae5e3596b143ffad4c84ade3c1
- Runtime validation: RGBA 32x32, visible colors=6, transparent background, no text/watermark by icon construction and local inspection
- Visual judgement: 통과: 두툼한 설백색 덧옷, 청회색 접힘 그림자, 절제된 세로 결로 현대식 방한복과 구분된다.
