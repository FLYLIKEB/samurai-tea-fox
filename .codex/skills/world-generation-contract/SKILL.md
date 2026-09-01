---
name: world-generation-contract
description: 월드 생성, 바이옴 정의, 시드 재현성, 필수 랜드마크, 연결성 검증을 구현하거나 검토할 때 사용한다.
metadata:
  short-description: 월드 생성 재현성과 연결성 규칙
---

# 월드 생성 계약

`src/world/`, biome 데이터, deterministic RNG, connectivity validation을 다룰 때 사용한다. 목표는 같은 seed와 같은 data version이 같은 월드를 만들고, 필수 진행 지점이 접근 가능하도록 보장하는 것이다.

## 생성 파이프라인

월드 생성은 다음 책임 흐름을 따른다.

```text
seed
  -> biome definition
  -> chunk/rule composition
  -> required landmark placement
  -> resource/enemy placement
  -> connectivity validation
  -> retry or accept
  -> visual TileMapLayer rendering
```

## 필수 규칙

- 바이옴 진행 순서는 고정이다.
- 런마다 랜덤 생성되는 것은 바이옴 내부 맵이다.
- 같은 seed와 같은 data version은 같은 결과를 만들어야 한다.
- 생성기와 검증기를 분리한다.
- 진입 지점, 텔레포트 존, 핵심 던전, 최소 자원량, 통과 가능한 경로를 우선 보장한다.
- 핵심 진행물이 지형 생성 때문에 접근 불가능해지는 결과는 허용하지 않는다.
- visual TileMapLayer 렌더링은 생성 데이터 이후 단계로 둔다.
- 렌더링용 맵, 랜드마크, 맵 내 사물 에셋은 정사각형 타일 기반 탑뷰 로그라이크에 맞춰 정면 시점으로 읽혀야 한다.

## 데이터 규칙

- biome 수치와 자원 요구는 `지역·바이옴` DB와 `⚖️ 밸런스 상수`를 정본으로 사용한다.
- 코드에는 biome 표시 이름별 조건문을 늘리지 않는다.
- 안정적인 ID와 definition 기반 설정을 사용한다.

## 검증

- 같은 seed와 data version의 결과가 같은지 테스트한다.
- 다른 seed가 다른 결과를 만들 수 있는지 확인한다.
- required landmark connectivity를 테스트한다.
- 데이터 버전이 결과에 저장되거나 재현성 판단에 반영되는지 확인한다.
