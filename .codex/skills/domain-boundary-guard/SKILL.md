---
name: domain-boundary-guard
description: Godot 도메인 모듈, 화면 구성, 입력 어댑터, 데이터 계층 변경에서 무사여우 기술 정본의 책임 경계를 지켜야 할 때 사용한다.
metadata:
  short-description: 도메인 경계 위반 방지
---

# 도메인 경계 가드

이 프로젝트의 GDScript 구조를 수정할 때 모듈 책임과 의존성 경계를 점검한다.

## 핵심 경계

- UI는 게임 상태를 소유하거나 직접 수정하지 않는다.
- UI와 입력 어댑터는 상태를 관찰하고 `GameCommand` 같은 명령을 전달한다.
- 키보드, 터치, gamepad 입력은 같은 게임 명령 계층으로 합류한다.
- 도메인 모듈은 다른 모듈의 내부 노드나 구체 구현을 직접 탐색하지 않는다.
- 모듈 간 연결은 작은 공개 API, signal/event, command, 명시적 의존성 주입을 사용한다.
- definition 데이터와 runtime state를 분리한다.
- 콘텐츠 이름별 `if/else` 또는 `match` 누적 대신 안정적인 ID와 데이터 주도 구조를 사용한다.

## 모듈 책임

- `core`: command layer, stable ID, deterministic RNG, data catalog
- `player`: HP, 기운, 心, 꼬리와 플레이어 상태
- `combat`: 공격, 회피, 피해, 피격 무적
- `tea`: 차 준비, 마시기, 기운 회복
- `inventory`: 슬롯, 스택, 직렬화
- `crafting`: 제작 조건, 재료 소비, 시설 요구
- `world`: 바이옴 정의, deterministic generation, connectivity
- `save`: versioned run save와 meta save codec
- `meta`: 런 종료 해금과 영구 기록
- `ui`: HUD, 메뉴 표시, 입력 어댑터

## 변경 전 점검

- 현재 변경이 어느 모듈 책임인지 먼저 정한다.
- 새 전역 singleton/autoload는 명확한 전역 생명주기 책임이 있을 때만 추가한다.
- 두 번째 실제 사용 사례가 생기기 전에는 큰 범용 추상화를 만들지 않는다.
- 기존 공개 인터페이스를 불필요하게 깨지 않는다.

## 완료 전 점검

- UI가 도메인 상태를 직접 바꾸는 경로가 생기지 않았는지 확인한다.
- 입력별로 별도 게임 로직이 생기지 않았는지 확인한다.
- 콘텐츠 이름 조건문이 늘었다면 데이터 정의로 옮길 수 있는지 확인한다.
- 관련 pure/domain 테스트를 추가하거나 실행한다.
