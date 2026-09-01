---
name: pixellab-animation-production
description: 무사여우 캐릭터·오브젝트의 움직임, 방향 전환, 애니메이션 스프라이트를 PixelLab API로 만들고 검증할 때 사용한다.
metadata:
  short-description: PixelLab 기반 움직임 스프라이트 제작
---

# PixelLab 애니메이션 제작

무사여우에서 캐릭터, 몬스터, 오브젝트의 걷기·대기·공격·상호작용 같은 움직임이 필요한 스프라이트를 만들 때 사용한다. 일반 단일 이미지 생성보다 PixelLab의 캐릭터·애니메이션 전용 API를 우선한다.

## 우선 적용 조건

- 캐릭터 또는 오브젝트의 움직임 프레임을 새로 만든다.
- 기존 1프레임 스프라이트를 기준으로 걷기, 숨쉬기, 공격, 피격 같은 애니메이션을 만든다.
- 방향별 캐릭터 시트, 회전, 프레임 보간, 스프라이트시트 export가 필요하다.
- PixelLab API 인증, balance 확인, 비동기 job polling, 생성 결과 정리가 필요하다.

단일 아이콘, UI, 타일처럼 움직임이 없는 이미지는 먼저 `ai-sprite-production`을 사용한다. 그 작업 중 움직임이나 방향 세트가 필요해지면 이 스킬을 함께 사용한다.

## 필수 선행 규칙

- 저장소 파일 수정, 에셋 반영, PR 작업이 포함되면 반드시 `isolated-worktree-pr` 흐름으로 전용 branch/worktree에서 작업한다.
- Markdown 문서나 스킬을 수정할 때는 `korean-md-authoring` 규칙을 따른다.
- 제작 대상, 규격, 방향 수, 프레임 수, 상태는 Notion `🎨 아트 에셋` DB를 정본으로 삼는다.
- 프롬프트 작성 전 `assets/style/art-style-tokens.json`을 읽고 팔레트, 시점, 금지 토큰을 따른다.
- PixelLab 호출 전 공식 문서 `https://api.pixellab.ai/v2/llms.txt` 또는 `https://api.pixellab.ai/v2/openapi.json`에서 현재 endpoint와 schema를 확인한다.

## 인증과 로컬 환경

- API 토큰은 `PIXELLAB_API_KEY` 환경변수로만 읽는다.
- 기본 API 주소는 `PIXELLAB_API_BASE_URL=https://api.pixellab.ai/v2`다.
- 로컬 파일은 `.env.local`을 우선하고, 없으면 `.env`를 읽는다.
- 토큰, 전체 balance 값, 원본 응답의 민감한 계정 정보는 채팅, 커밋, 로그, PR 본문에 노출하지 않는다.
- `.env`, `.env.*`, `.pixellab.config.json`은 커밋하지 않는다. 공개 가능한 변수 이름은 `.env.example`에만 둔다.
- 실제 생성 전에 `scripts/pixellab_balance_check.mjs`로 인증이 통과하는지 확인한다.

## Endpoint 선택

- 기존 캐릭터 ID에 애니메이션을 추가한다: `POST /characters/animations`
- 기존 1프레임 이미지에서 텍스트 액션으로 프레임을 만든다: `POST /animate-with-text-v3`
- 스켈레톤 포즈를 명시해 만든다: `POST /animate-with-skeleton`
- 기존 애니메이션의 일관된 수정이 필요하다: `POST /edit-animation-v2`
- 두 키프레임 사이를 보간한다: `POST /interpolation-v2`
- 방향별 캐릭터가 먼저 필요하다: `POST /create-character-v3`, `POST /create-character-with-4-directions`, `POST /create-character-with-8-directions`
- 결과 다운로드가 필요하다: `GET /characters/{character_id}/spritesheet`, `GET /characters/{character_id}/zip`, `GET /objects/{object_id}/spritesheet`
- 비동기 작업은 `GET /background-jobs/{job_id}`를 5-10초 간격으로 polling한다.

엔드포인트 이름은 공식 OpenAPI를 우선한다. schema enum 값은 추측하지 말고 OpenAPI에서 확인해 그대로 사용한다.

## 제작 흐름

1. Notion `🎨 아트 에셋` 행에서 이름, 용도, 캔버스 크기, 방향 수, 프레임 수, 배경 투명 여부를 확인한다.
2. 기존 기준 이미지가 있으면 실제 경로와 크기를 확인한다. 없으면 먼저 기준 1프레임 또는 방향 세트를 만든 뒤 애니메이션으로 넘어간다.
3. `assets/style/art-style-tokens.json`에서 공통 positive/negative 토큰과 대상 `asset_profiles`를 읽는다.
4. `/balance` 인증 확인을 실행한다. 실패하면 생성 호출을 중단하고 환경변수, base URL, 토큰 설정만 점검한다.
5. 액션 프롬프트에는 동작, 프레임 수, 반복 여부, 방향, 투명 배경, 실루엣 보존, 무기·꼬리·다구 같은 식별 요소를 명시한다.
6. PixelLab 요청과 응답에서 prompt, endpoint, seed, job id, 후처리 내역만 아티팩트 메모로 남긴다. base64 이미지와 계정 정보는 redaction한다.
7. 결과 프레임과 AI 생성 원본 raw는 먼저 Git에서 제외된 `assets/source/imagegen/pixellab-<asset>-<yyyymmdd>/raw/`에 저장한다.
8. 최종 후보만 런타임 경로에 정규화한다. 캐릭터와 오브젝트는 기본적으로 `assets/sprites/`를 사용한다.
9. `/correct-pixelart`, `/reduce-colors`, `/remove-background`, `/resize`는 결함이 확인된 경우에만 작은 강도로 적용한다.
10. Godot 또는 에셋 브라우저에서 1x와 2x 정수 배율, 프레임 순서, 루프 이음, 투명 배경, nearest filtering을 확인한다.
11. 통과한 파일 경로와 검수 메모를 Notion `🎨 아트 에셋` DB에 반영한다.

## 프롬프트 기준

- 무사여우 주인공은 큰 붉은여우 귀와 꼬리, 작은 검, 차통 또는 다구, 절제된 사무라이 실루엣을 유지한다.
- 기본은 32x32 저해상도 픽셀아트, 명확한 외곽선, 낮은 색 수, anti-aliasing 없음이다.
- 움직임은 작은 크기에서 읽히는 핵심 포즈를 우선한다. 장식 프레임보다 발, 귀, 꼬리, 무기 방향의 변화가 먼저 보여야 한다.
- 걷기는 8프레임을 기본으로 삼고, idle은 4프레임, 공격·의식 동작은 8-16프레임을 후보로 둔다. Notion 행의 프레임 수가 있으면 그 값을 우선한다.
- 방향 규칙이 정면 탑뷰로 제한된 에셋은 측면·후면·3/4 방향을 만들지 않는다.
- 스프라이트시트에는 텍스트, 워터마크, 배경색, 그림자판, 여분 캐릭터가 들어가면 안 된다.

## 검증 완료 기준

- PixelLab 인증 확인이 성공했다.
- 생성에 사용한 endpoint, prompt 출처, job id 또는 response id를 redaction된 메모로 남겼다.
- PNG 크기, 프레임 수, 방향 수, alpha 채널이 요구사항과 맞다.
- 1x와 2x에서 실루엣, 방향, 루프가 읽힌다.
- Godot import 또는 에셋 브라우저 확인에서 픽셀 정렬이 깨지지 않는다.
- PR 작업이라면 isolated worktree에서 테스트 후 PR을 열고, 머지 후 로컬 main으로 복귀했다.

## 보고

완료 보고에는 대상 Notion 행, PixelLab endpoint, 생성 파일 경로, 검수 방식, 테스트 명령, 남은 리스크를 포함한다. API 토큰, 전체 balance 값, base64 원문, 다운로드 URL 원문은 보고하지 않는다.
