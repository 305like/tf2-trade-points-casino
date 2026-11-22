# 봇거래·포인트·카지노 외주 인계용 점검

> 분리 인계 후속: 이 문서의 GitHub 상태와 미추적 파일 설명은 원본 FF2 작업본을 점검한 시점의 기록이다. 이후 FF2는 비공개로 복원하고 관련 소스/선별 테스트/본 문서를 `305like/tf2-trade-points-casino`에 새 이력으로 분리했다. 원본의 배포 스크립트·민감 운영 데이터·제3자 게임 리소스는 공개 저장소에 포함하지 않았다. 최신 공개 범위와 사용 제한은 루트 README를 따른다.

점검일: 2026-11-22. 대상: 현재 로컬 작업본, GitHub 원격 브랜치, 테스트/거래 서버 27019 및 기존 거래 봇 호스팅. 운영 파일 변경·거래·잔액 수정·로드/리로드·커밋·푸시 없이 점검했다.

## 핵심 결론

1. 테스트 서버의 `metal_points`, `casino_unified`, `bot_trade_shop`는 점검 시점에 모두 미로드였다. RCON `sm plugins info`와 전체 38개 플러그인 목록을 교차 확인했다. 과거 배포 기록만으로 현재 정상 운영이라고 판단하면 안 된다. 미로드 이유와 시점은 이번 점검으로 확인하지 못했다.
2. 아이템→포인트→카지노는 하나의 연결된 서비스가 아니다. 현재 코드에는 아이템 충전/환전을 명시적으로 차단하고 게임 전용 장부를 분리한 변경이 있다.
3. 거래 봇의 `poll-health.json`은 확인 시점 기준 20초 전이었다. 이는 최근 폴링 증거이지 실제 입고·구매·판매대금 지급 성공의 증거가 아니다.
4. 최신 관련 로컬 커밋은 GitHub **archive/game-points-20261031** 브랜치에 존재한다. GitHub **main에는 미통합**이다. 문서·배포 도구·여러 테스트는 로컬 미추적 파일이므로 저장소만 전달하면 인계 자료가 빠진다.

## 시스템 구분

| 구성 | 구현 및 연결 | 현재 확인 수준 |
|---|---|---|
| 게임 내 봇거래 NPC/메뉴 | `bot_trade_shop.sp`, 세션 include → 웹 상점 | 플러그인 미로드 |
| 웹 거래 상점 | `tools/bot_trade_shop/`: Steam 로그인, 소유 배낭, 입고, 구매, 반환, 판매자 대금 수령 | 코드와 운영 파일 일부 비교. 실거래 미검증 |
| Steam 거래 봇 | `tools/metal_points/`: 입고·구매·반환·자금 모듈과 영수증/보관 장부 | 핵심 5개 모듈이 운영 파일과 바이트 일치, 최근 폴링 기록 확인 |
| 기존 아이템 포인트 | SQLite `accounts`, `deposits` 및 입출금 관련 코드 보존 | 신규 아이템 연동을 여러 계층에서 차단 |
| 게임 전용 포인트 | SQLite `play_accounts`, `play_rounds`, 소유자 조정 감사 기록 | 별도 장부. 아이템 변환 경로 없음 |
| 더블엔 낫띵 | `GamePoints_Don`으로 베팅·성공/실패·수령·복구 | 로컬 코드에 연동. 현재 서버에서는 미로드 |
| 다이아몬드 슬롯 | 당첨액 계산 및 공용 누적금/연출 | 당첨액을 `(테스트)` 힌트로 표시. 이 모듈에서 게임 포인트 지급 호출을 찾지 못함 |

상점의 아이템 구매/판매대금은 키·금속을 직접 교환하는 별도 흐름이다. 이를 카지노에서 쓰는 게임 포인트와 혼동하지 말 것. 다른 카지노 게임 전체의 베팅·정산 통합이 완료됐다고 간주할 근거도 없다.

## 명시적 차단 근거

- `tools/bot_trade_shop/finance.php:43`: `topup` 요청을 예외로 거부.
- `tools/metal_points/ingress.php:15`: health 응답은 `ready=false`, `item_points_enabled=false`. 장부 가동 여부는 별도 `ledger_ready`.
- 같은 ingress에서 `claim`, `bind`는 denied 응답.
- `tools/metal_points/deposit-bot.js:108,155`: 해당 입출금 경로는 API ready 확인 후 진행하므로 위 정책에 의해 중단된다.
- `addons/sourcemod/scripting/metal_points_withdraw.inc:89`: 아이템 출금 메뉴 실행을 `false && ...`로 차단.
- `addons/sourcemod/scripting/game_points.inc`: 게임 장부는 `play_accounts/play_rounds` 사용. 기존 `accounts`와 분리.
- `addons/sourcemod/scripting/casino_unified/don.inc:876` 이후: 베팅 차감, 결과, 수령 native 호출.
- `addons/sourcemod/scripting/casino_unified/diamond.inc:1153`: 계산한 보상을 테스트 힌트로 표시.

위 사항은 단순 연결 누락뿐 아니라 **정책적으로 비활성화한 코드**다. 담당자가 이유 확인 없이 ready=true 또는 차단 조건만 제거해서는 안 된다. 오래된 미처리 거래·장부를 먼저 대조해야 한다.

## 운영 파일 확인

다음 파일은 원격에서 읽어 로컬 바이트와 일치함을 확인했다. 파일 일치는 메모리에 로드된 프로그램 버전이나 거래 성공을 보장하지 않는다.

- 웹: `/public_html/bot-shop/finance.php`, `/public_html/metal-points/ingress.php`
- 게임 서버 소스: `/tf/addons/sourcemod/scripting/metal_points.sp`
- 봇: `/metal-points/` 아래 `deposit-bot.js`, `shop-checkout.js`, `shop-finance.js`, `shop-intake.js`, `shop-returns.js`

현재 플러그인이 미로드이므로 서버에서 동작 중인 최신 포인트/카지노 바이너리라는 표현은 사용할 수 없다. 바이너리 전체·의존성·설정·리소스 전체의 일치 여부는 추가 확인 대상이다.

## GitHub 상태

저장소: `305like/FF2_RPG_SKILL`.

| 위치 | 커밋 | 의미 |
|---|---|---|
| 로컬 main | `f339da3011b99bf27e60ddee1042f888685b37ab` | 2026-10-31, 게임 포인트 분리·아이템 변환 비활성화 |
| GitHub archive/game-points-20261031 | 위와 동일 | 관련 커밋은 원격에 보존되어 있음 |
| GitHub main | `53c347d271ed82007eb3235f2dc4dc0a6eb31217` | 2026-11-14, Double Revolver 변경 |

`git ls-remote --heads origin`으로 실제 원격을 조회했다. 원격 main 해시는 기존 origin/main과 일치했다. 로컬 main만의 커밋 4개, 원격 main만의 커밋 23개로 분기되어 있다. 날짜만 비교해 어느 쪽이 모든 기능의 최신이라고 판단할 수 없다.

미추적 파일 예: `tools/bot_trade_shop/README.md`, 상점 배포 도구, 여러 PHP/JS 테스트, `tools/metal_points/ARCHITECTURE.md`, `AUTO_WITHDRAWAL.md`, 배포/검사 도구, `docs/shop_points_treasury.md`. 카지노 별도 플러그인 `tower_slots_test.sp` 및 seats/camera/setup include에도 미커밋 수정이 있다.

외주 인계 전: 기준 브랜치를 합의하고, 비밀값 검사를 거쳐 필요한 소스·테스트·문서를 선별 커밋한 뒤 main과 통합/검증해야 한다. 전체 작업 폴더를 무차별 업로드하거나 강제 푸시하지 말 것. 원장·세션·자격증명·사용자 거래 데이터는 코드 저장소에 넣지 않는다.

## 실행한 안전한 검증

- `python tests/check_game_points.py`: PASS. 메모리 SQLite에서 차감, 잔액 부족, 동시 라운드 제한, 배수, 패배, 중복 수령 방지, 재시작 복구, 장부 분리.
- `python tests/check_point_wallet.py`: PASS. 메모리 SQLite에서 관리자 조정 감사, 재시도 중복 방지, 음수 잔액 방지, 원자적 롤백.
- `node tools/metal_points/test-shop-finance.js`: PASS. 모의 거래로 충전 차단, 운영자 자금, 영수증 검증, 불명확한 전송/재시작/중복 완료.
- `node tools/metal_points/test-ledger-audit.js`: PASS. 보관 소유자·자산·가격·장부 누락·완료 경계 검사.
- `node tools/metal_points/test-policy.js`: PASS. 모의 거래의 금속/영수증/보류/수령·지급 방향 검사.
- `casino_unified.sp`: SourcePawn 1.12.0.7253으로 임시 경로 빌드 성공, 경고 7개(상수 조건/미사용 함수). 서버에 업로드하지 않음.

테스트는 일부 로직을 검증하며 실제 Steam 거래, 실행 중 서비스의 전체 복구성 또는 무결성을 입증하지 않는다. 기존 `check-live.py`는 이름과 달리 claim 요청을 제출하므로 이번 읽기 전용 점검에서는 실행하지 않았다.

## 외주 작업 요청안 / 완료 조건

1. **현황 복원**: 게임 서버 플러그인 미로드 이유, 실제 운영 위치/버전, 봇·웹 설정과 의존성을 확인. 가동 중인 서비스와 보관된 소스를 구분해 배포 목록 작성.
2. **장부 정책 확정**: 게임 전용 포인트와 아이템 거래를 계속 분리할지 명시. 현재 코드는 분리 상태이며 환전 재활성화는 별도 설계·검토·승인이 필요.
3. **게임별 정산 명세**: 각 카지노의 차감 시점, 승리 금액이 총수령인지 순이익인지, 중도 종료/접속 종료/리로드/강제 결과 테스트의 처리 정의. 슬롯의 화면 표시를 실제 지급으로 오해하지 않도록 표시 정리.
4. **거래 검수**: 별도 테스트 계정과 명시적 승인을 받아 입고→게시→구매→대금 수령, 반환, Steam 보류/취소, 영수증 불일치, 타임아웃 후 재시작을 확인. offer/trade ID별 중복 정산이 없어야 함.
5. **잔액 검수**: 장부 변경은 트랜잭션과 유일 요청 ID 사용. 동시 클릭·이중 수령·접속 종료·서버 재시작 후에도 잔액/라운드가 일치해야 함. 기존 장부를 빈 파일로 교체하지 말 것.
6. **문서 정정**: README의 최신/과거 설명과 `shop_points_treasury.md`에 충전 가능하다는 과거 내용이 섞여 있다. 현재 정책과 검증일을 상단에 명확히 기재.
7. **인계/배포**: 재현 가능한 빌드, 테스트 결과, 운영 파일 해시, 버전/태그, 백업·복구 순서를 제공. 원장 백업의 외부 보관과 복구 훈련도 별도 완료 조건으로 설정.

## 미검증 범위

실제 아이템 이동, 실제 잔액 증감, 봇 전체 미처리 거래 및 개인정보 포함 원장 대조, 모든 웹 화면/엔드포인트, 전체 리소스, Hale 서버는 검사하지 않았다. 따라서 전체 서비스가 정상 작동한다거나 모든 결함을 찾았다고 결론 내릴 수 없다. 이번에 확인된 미로드·정책 차단·Git 분기부터 해결 범위를 확정해야 한다.
