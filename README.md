# TF2 Bot Trade, Points & Casino

> **도박과 아이템 간 연결은 현재 비활성화되어 있으며, 추가 연결 작업이 필요합니다.**
> 아이템 거래 → 포인트 충전 → 도박 베팅/정산 → 아이템 환전의 통합 흐름은 제공되지 않습니다.
> 더블엔 낫띵에 연결된 별도 게임 포인트는 아이템으로 충전하거나 환전할 수 없습니다.
> 다이아몬드 슬롯·복권은 지급 없는 테스트이며, 포커·블랙잭·확장 카지노는 별도 시험 칩을 사용합니다.
> 연결하려면 정책 확정, 게임별 장부 연동, 거래 영수증 검증, 중복 정산 방지 및 취소·재시작 복구 검수가 필요합니다. 비활성화 조건만 제거해서는 안 됩니다.

봇거래·포인트·카지노 관련 소스만 분리한 공개 인계 저장소입니다.
2026-11-22 로컬 작업본을 기준으로 추출했으며 FF2/Hale/RPG 코드 및 기존 저장소의 Git 이력을 포함하지 않습니다.

## 포함 범위

- `tools/bot_trade_shop`: PHP 웹 상점, 배낭, 거래·자금·세션 처리와 테스트.
- `tools/metal_points`: Node.js 거래 봇, 입고·구매·반환·영수증·장부 모듈과 단위 테스트.
- `addons/sourcemod/scripting`: 봇거래 NPC, 포인트, 통합 카지노, 개별 슬롯/더블/카드/확장 게임/스크래치 복권.
- `tests`: 메모리 SQLite를 사용하는 게임 포인트 및 관리자 잔액 조정 테스트.
- `docs/bot_trade_audit_handoff_20261122.md`: 운영 점검 결과, 확인 근거, 외주 수정 범위.

## 현재 상태 — 완성된 자동 설치 패키지가 아닙니다

- 최초 점검 당시 테스트 서버의 관련 플러그인은 미로드였으나, 2026-11-22 포인트·봇거래·통합 카지노·복권을 설치/로드했습니다. 슬롯·더블·복권은 준비 완료, 카드 테이블은 추가 점검 대상입니다.
- 웹 상점 저장소 소유권을 복구해 HTTP 200과 판매 상품 4개 표시, 입고·구매·반환·자금 heartbeat를 확인했습니다. 판매자 지급 영수증 저장 수정은 봇에 업로드했으며, **Node.js 봇 재시작 후 활성화 및 기존 영수증 복구 검증이 남아 있습니다.** 상세: [상점 복구 기록](docs/shop_repair_20261122.md).
- 아이템으로 포인트 충전/환전하는 경로는 명시적으로 비활성화되어 있습니다.
- 더블엔 낫띵은 별도 게임 포인트 장부에 연결되어 있으나 다이아몬드 슬롯의 당첨 표시는 테스트입니다.
- 원본 소스의 서버 도메인과 공개 SteamID 상수는 유지했습니다. 다른 서버 배포 전 소유자/봇 신원, 인증 정책, 경로를 검토해야 합니다. 비밀 토큰/비밀번호와는 별개입니다.
- 통합 카지노 include와 개별 플러그인 소스는 서로 다른 수정 이력을 가질 수 있습니다. 제공된 통합 include를 임의 재생성해 덮어쓰지 마세요.
- 실거래·실제 잔액 변경을 통한 end-to-end 검증은 수행하지 않았습니다.

## 의도적으로 제외한 파일

Steam 인증정보, API 키, 거래 URL 토큰, DB 설정, 개인 거래 원장, 운영 로그, 서버 접속/배포 스크립트, 컴파일러, 빌드 바이너리, 제3자 모델·재질·음원 및 데이터 인덱스는 포함하지 않습니다.
게임 리소스가 없는 환경에서는 모델·화면·소리가 정상 표시되지 않습니다. 리소스의 사용·배포 권한은 별도로 확인해야 합니다.
`item-index.json`과 `effect-index.json`은 운영자가 적법하게 확보한 아이템/번역 데이터로 별도 준비해야 합니다. 일부 웹 테스트에도 이 인덱스가 필요합니다.

## 개발 의존성 / 빌드

- SourceMod 1.12 SDK 및 `spcomp` (검증에 사용한 빌드: 1.12.0.7253).
- PHP 8.3 CLI/웹 서버. 웹 격리 테스트는 Docker 필요.
- Node.js 및 봇 런타임 외부 패키지: `steam-session`, `@tf2autobot/steamcommunity`, `@tf2autobot/tradeoffer-manager`, `steam-user`.
- Python 3, 표준 라이브러리 SQLite.

기존 호스팅의 정확한 Node 의존성 버전/lockfile은 이번 추출에 포함되지 않았습니다. 실거래 전 버전을 고정하고 재검증해야 합니다. 임의 최신 패키지를 설치해 즉시 운영하지 마세요.

통합 카지노는 제공된 include를 사용해 직접 빌드합니다. SDK_INCLUDE와 출력 폴더는 개발 환경에 맞게 준비하세요.

```text
spcomp addons/sourcemod/scripting/casino_unified.sp -iSDK_INCLUDE -iaddons/sourcemod/scripting -obuild/casino_unified.smx
spcomp addons/sourcemod/scripting/metal_points.sp -iSDK_INCLUDE -iaddons/sourcemod/scripting -obuild/metal_points.smx
spcomp addons/sourcemod/scripting/bot_trade_shop.sp -iSDK_INCLUDE -iaddons/sourcemod/scripting -obuild/bot_trade_shop.smx
```

통합 카지노와 개별 카지노 플러그인을 동시에 로드하지 마세요. 게임 포인트 native 공급자는 `metal_points`입니다. 웹에는 운영 PHP/JS/CSS만 배포하고 `test_*` 파일을 배포하지 마세요. 봇 진입 파일 `metal-points.js`는 호스팅 루트, 나머지 모듈은 그 아래 `metal-points/`에 배치하는 구조입니다. 운영 원장이 없는 상태를 임의로 빈 원장으로 초기화하지 마세요.

## 비운영 테스트

```text
python tests/check_game_points.py
python tests/check_point_wallet.py
node tools/metal_points/test-shop-finance.js
node tools/metal_points/test-ledger-audit.js
node tools/metal_points/test-policy.js
```

위 5개 테스트는 분리 전 및 분리 후 확인합니다. 테스트 통과가 실거래 성공을 보장하지 않습니다. 봇 엔트리포인트를 실행하면 실제 거래에 영향을 줄 수 있으므로 테스트로 실행하지 마세요.

## 외주 우선 작업

1. 현재 운영 버전과 플러그인 미로드 이유 파악.
2. 아이템 거래와 게임 포인트 분리 정책 확정.
3. 게임별 차감/정산/복구를 정의하고 슬롯의 테스트 표시와 실제 장부를 구분.
4. 승인된 테스트 계정으로 거래 취소·보류·중복·재시작 검수.
5. 안전한 배포 설정 예제, 고정 의존성, 백업/복구 절차 제공.

원본 FF2 저장소는 비공개이며 이 공개 저장소에는 관련 코드 사본만 있습니다. 서버 실행 파일이나 기존 FF2 파일을 삭제/이동하지 않았습니다. 공개 접근은 제3자 리소스의 재배포 권한을 부여하지 않습니다.
