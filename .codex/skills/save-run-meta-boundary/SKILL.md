---
name: save-run-meta-boundary
description: run save와 meta save, 런 종료, 사망 처리, 메타 해금, 이전 런 기억 조건을 구현하거나 검토할 때 사용한다.
metadata:
  short-description: run/meta 저장 경계 규칙
---

# Run Save와 Meta Save 경계

저장, 런 종료, 사망, 메타 해금, 반복 런 기억 조건을 다룰 때 사용한다. 이 프로젝트는 run save와 meta save를 논리적으로 분리한다.

## run save에 속하는 것

- 현재 맵 seed와 진행
- 현재 런 인벤토리와 화폐
- 현재 런의 꼬리와 요술
- 텔레포트 상태
- 현재 런 제작 해금과 시설 상태
- 중단 후 같은 런을 이어 하기 위한 상태

## meta save에 속하는 것

- run count
- 도감과 발견 기록
- 최고 도달 바이옴
- 메타 해금
- 대화 조건
- 센리큐와 구미호 아버지처럼 이전 런을 기억하는 존재의 조건

## 금지

- 사망 후 run save로 롤백하는 구조를 만들지 않는다.
- 런 종료 시 런 내부 성장, 아이템, 화폐, 꼬리, 요술, 텔레포트, 제작 해금을 영구 보존하지 않는다.
- 직접적인 영구 전투 능력치 누적을 기본 설계에 추가하지 않는다.
- run save와 meta save를 같은 kind/schema로 취급하지 않는다.

## 구현 규칙

- 저장 데이터에는 schema version을 둔다.
- decode 단계에서 run save와 meta save kind를 구분한다.
- 사망 확정 시 run save는 폐기하고, 충족된 meta 조건만 반영한다.
- 중단 저장은 현재 run을 이어 하기 위한 것이며 사망 롤백 수단이 아니다.
- 메타 보상 조건과 보상 내용은 `🔁 메타 해금` DB를 정본으로 사용한다.

## 검증

- run save와 meta save round-trip을 각각 테스트한다.
- run save를 meta save로 decode할 수 없고, 반대도 불가능해야 한다.
- 사망/런 종료 처리에서 run-only 상태가 meta로 새지 않는지 테스트한다.
