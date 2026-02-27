---
title: "Lending Protocol Study Day 2: Compound V2 Deep Dive와 Aave V3 아키텍처"
date: 2026-02-25
draft: false
authors: ["Jeongseup"]
description: "Compound V2 CToken 상속 구조와 Fresh 패턴, 3가지 렌딩 모델 유형 분석, Aave V3 비트맵 스토리지 최적화까지."
slug: lending-protocol-study-day2
tags: ["DeFi", "Lending", "Compound", "Aave", "Solidity", "Smart Contract"]
categories: []
series: ["Lending Protocol Study"]
math: true
---

> 7일간의 DeFi Lending Protocol 스터디 시리즈. Day 2에서는 Compound V2의 내부 구조를 코드 레벨로 파고들고, 렌딩 프로토콜의 3가지 유형을 분류한 뒤, Aave V3의 아키텍처 진화를 분석한다.
>
> **Repository:** [jeongseup/lending-protocol-study](https://github.com/jeongseup/lending-protocol-study)

---

## Day 2 목표

- Compound V2의 CToken 상속 구조와 **"Fresh" 패턴**을 코드 레벨로 이해한다
- **Mantissa** 기반 고정소수점 연산과 **Lazy Interest Accrual** 메커니즘을 파악한다
- 렌딩 프로토콜을 **3가지 유형**(Pool-based, CDP-based, Fixed-rate)으로 분류한다
- Aave V3의 **비트맵 스토리지 최적화**와 아키텍처 진화를 분석한다

---

## Compound V2 Deep Dive: CToken 상속 구조

Day 1에서 Compound V2의 핵심 파일 3개를 언급했다. Day 2에서는 CToken의 **상속 구조**부터 파고든다.

```
CTokenInterface (인터페이스)
  └─ CToken (핵심 로직)
       ├─ CErc20 (ERC20 자산용 - USDC, DAI 등)
       └─ CEther (ETH 전용)
```

`CErc20`과 `CEther`의 차이는 단순하다. ETH는 ERC20이 아니라 `msg.value`로 받아야 하므로, 자금 수수 로직만 다르고 **핵심 렌딩 로직은 CToken에 모두 있다.**

중요한 건 CToken이 **풀 역할까지 겸한다**는 점이다. `mint()`, `borrow()`, `repay()`, `liquidate()` 모두 CToken 컨트랙트에 있다. 하나의 컨트랙트가 ERC20 토큰이면서 동시에 렌딩 풀인 **Monolithic 구조**다.

---

## Fresh 패턴: "이자부터 정산하고 본론으로"

Compound V2의 모든 핵심 함수 이름에 `Fresh`가 붙어 있다.

```solidity
function mintFresh(address minter, uint mintAmount) internal
function borrowFresh(address payable borrower, uint borrowAmount) internal
function repayBorrowFresh(address payer, address borrower, uint repayAmount) internal
function liquidateBorrowFresh(address liquidator, address borrower, ...) internal
```

왜 `Fresh`일까? **"이자를 최신 상태로 정산한 뒤에 핵심 로직을 실행한다"**는 패턴이다.

```solidity
function mint(uint mintAmount) external returns (uint) {
    accrueInterest();       // 1. 이자 먼저 정산
    return mintFresh(msg.sender, mintAmount);  // 2. 그 다음 본론
}
```

모든 external 함수가 이 패턴을 따른다:

```
사용자 호출 → accrueInterest() → xxxFresh() → 실제 로직
```

이렇게 하는 이유는 간단하다. 이자 계산은 **마지막 업데이트 이후의 블록 수**에 기반한다. 이자를 정산하지 않고 `mint()`을 실행하면, 기존 예치자들의 교환비율이 부정확한 상태에서 새로운 지분이 발행되어 **기존 예치자가 손해를 본다.**

---

## Mantissa: Solidity의 소수점 해법

Solidity에는 부동소수점이 없다. Compound V2는 이를 **Mantissa** 방식으로 해결한다.

$$\text{Mantissa} = \text{실제값} \times 10^{18}$$

예를 들어:
- 이자율 5% → `0.05 × 10^18 = 50000000000000000`
- 교환비율 0.02 → `0.02 × 10^18 = 20000000000000000`

곱셈과 나눗셈 시 스케일링을 맞춰야 한다:

```solidity
// 두 Mantissa 값의 곱셈: 결과를 10^18으로 나눠서 스케일 복원
function mulScalar(Exp memory a, uint scalar) pure internal returns (Exp memory) {
    return Exp({mantissa: a.mantissa * scalar});
}

function mulExp(Exp memory a, Exp memory b) pure internal returns (Exp memory) {
    return Exp({mantissa: a.mantissa * b.mantissa / 1e18});
}
```

이 패턴은 Compound만의 것이 아니다. Aave의 `RAY(10^27)`, Uniswap V3의 `Q96(2^96)`, MakerDAO의 `WAD(10^18)` 모두 같은 원리다. **정수로 소수점을 표현하기 위한 고정소수점 연산.**

---

## Lazy Interest Accrual: 이자는 "필요할 때만" 계산한다

`accrueInterest()`는 매 블록마다 자동으로 실행되는 게 아니다. **누군가 트랜잭션을 보낼 때만** 실행된다. 이것이 **Lazy Evaluation**이다.

```
블록 100: Alice가 mint()     → accrueInterest() 실행 (블록 0~100 이자 계산)
블록 200: 아무 일 없음        → 이자 계산 안 함
블록 300: Bob이 borrow()      → accrueInterest() 실행 (블록 100~300 이자 계산)
```

200 블록 동안 아무도 상호작용하지 않으면, 200 블록치의 이자가 한번에 계산된다. 가스비는 **트랜잭션 수가 아니라 상호작용 빈도에 비례**한다.

`accrueInterest()`가 업데이트하는 상태 변수는 딱 **4개**다:

```solidity
totalBorrows    // 총 대출량 (이자 포함)
totalReserves   // 프로토콜 수익 누적
borrowIndex     // 대출자 이자 추적용 전역 인덱스
accrualBlockNumber  // 마지막 이자 정산 블록 번호
```

4개의 `SSTORE` = 20,000 gas. 사용자 수가 아무리 많아도 이 비용은 고정이다. 이것이 Day 1에서 설명한 **Scaled Balance 패턴**의 실제 구현이다.

---

## 이자 시나리오 시뮬레이션

구체적인 숫자로 따라가보자.

### 초기 상태

```
블록 0: Pool에 10,000 USDC
- totalCash = 10,000
- totalBorrows = 0
- totalReserves = 0
- borrowIndex = 1.0 (1e18)
- exchangeRate = 10,000 / 500,000 = 0.02 (cToken 500,000개 발행 가정)
```

### Alice가 1,000 USDC 대출

```
블록 100: Alice borrow(1,000)
- accrueInterest() 실행 (totalBorrows = 0이므로 이자 없음)
- totalCash = 9,000 (1,000 빠짐)
- totalBorrows = 1,000
- Alice의 borrowSnapshot = {principal: 1,000, interestIndex: 1.0}
```

### 100블록 후 이자 정산

```
블록 200: Bob이 mint() 호출
- 이자율: borrowRate = 0.0001/블록 (연 약 5.3%)
- 경과 블록: 100
- simpleInterestFactor = 0.0001 × 100 = 0.01
- 새 totalBorrows = 1,000 × 1.01 = 1,010
- Reserve Factor 10%: 새 totalReserves = 10 × 0.1 = 1
- 새 borrowIndex = 1.0 × 1.01 = 1.01
```

Alice의 실제 대출 잔액은?

$$\text{Alice 대출잔액} = \frac{\text{principal} \times \text{현재 borrowIndex}}{\text{Alice의 interestIndex}} = \frac{1{,}000 \times 1.01}{1.0} = 1{,}010 \text{ USDC}$$

Alice의 Storage를 건드리지 않고도 **전역 borrowIndex 하나만으로** 정확한 잔액을 계산했다.

---

## 렌딩 프로토콜의 3가지 유형

Day 1에서는 Pool-based 모델만 다뤘다. 실제로 렌딩 프로토콜은 **자금 조달 방식**에 따라 3가지로 분류된다.

### 1. Pool-based (Compound, Aave)

```
예치자 → [Pool] → 차입자
```

- **기존 예치금**에서 대출
- 예치자가 없으면 빌릴 수 없다
- 이자율은 Utilization Rate에 연동

### 2. CDP-based (MakerDAO)

```
사용자 → [Vault] → 새 DAI 발행
```

- 프로토콜이 **새 토큰을 발행** (mint)
- 예치자 없이도 대출 가능
- Stability Fee(이자)는 거버넌스가 결정
- CDP = Collateralized Debt Position

### 3. Fixed-rate (Yield Protocol)

```
사용자 → fyToken (만기 시 1:1 교환 가능)
```

- **할인된 미래 가치 토큰** 매매
- 0.95 fyUSDC를 사면, 만기에 1 USDC → 약 5% 고정 금리
- 이자율이 트레이딩으로 결정

### 비교 정리

| 특성 | Pool-based | CDP-based | Fixed-rate |
|------|-----------|-----------|------------|
| 자금 출처 | 예치자 | 프로토콜 발행 | 시장 매매 |
| 이자율 결정 | 알고리즘 (사용률) | 거버넌스 투표 | 시장 수급 |
| 변동/고정 | 변동 | 반고정 | 고정 |
| 대표 | Compound, Aave | MakerDAO | Yield, Notional |
| 필요 조건 | 유동성 공급자 | 없음 (mint) | 만기 매칭 |

대부분의 메이저 프로토콜이 Pool-based인 이유: **구현이 단순하고, 유동성이 자연스럽게 형성**되기 때문이다. CDP는 토큰 경제 설계가 복잡하고, Fixed-rate는 만기 매칭이 어렵다.

---

## Aave V3 아키텍처: Compound에서 무엇이 진화했나

Compound V2는 CToken이 모든 걸 한다. Aave V3는 이를 **분리**했다.

```
Compound V2:
  사용자 → CToken.mint()     (CToken = 풀 + 토큰)

Aave V3:
  사용자 → Pool.supply()     (Pool = 라우터)
         → SupplyLogic.executeSupply()  (Library = 실제 로직)
         → aToken.mint()    (aToken = 순수 영수증)
```

### delegatecall + Library 패턴

Aave V3의 `Pool.sol`은 얇은 프록시에 가깝다. 실제 로직은 **Library** 컨트랙트에 있다.

```solidity
// Pool.sol
function supply(address asset, uint256 amount, ...) external {
    SupplyLogic.executeSupply(...);  // delegatecall로 Library 호출
}

function borrow(address asset, uint256 amount, ...) external {
    BorrowLogic.executeBorrow(...);
}
```

Library를 쓰면:
- **코드 크기 제한(24KB)** 회피 - Pool의 로직이 아무리 커도 Library에 분산
- **관심사 분리** - Supply, Borrow, Liquidation 로직이 독립적으로 관리
- 단, Library는 **독립 배포 후 업그레이드 불가** - Proxy 패턴과 조합하여 해결

### Debt Tokenization

Compound V2에서 대출은 단순 매핑이다:

```solidity
// Compound V2
mapping(address => BorrowSnapshot) accountBorrows;
```

Aave V3는 대출도 **토큰화**했다:

```solidity
// Aave V3
variableDebtToken.mint(borrower, amount);  // 대출하면 부채 토큰 발행
variableDebtToken.burn(borrower, amount);  // 상환하면 부채 토큰 소각
```

부채를 토큰화하면 무엇이 좋은가?
- `balanceOf()`로 대출 잔액 조회 가능 (표준 인터페이스)
- Transfer 제한으로 부채 이전 방지
- 이벤트 표준화 (Transfer 이벤트로 대출/상환 추적 가능)

> Aave V3.2부터 Stable Rate이 제거되었다. 변동금리만 남았으므로 `stableDebtToken`은 더 이상 사용되지 않는다.

---

## 비트맵 스토리지 최적화

Day 2의 가장 중요한 기술적 발견이다. Compound V2와 Aave V3의 **사용자 상태 관리 방식**이 근본적으로 다르다.

### Compound V2: 배열 순회

```solidity
// Comptroller.sol
mapping(address => CToken[]) public accountAssets;  // 사용자별 참여 마켓 배열

// Health Factor 계산 시
for (uint i = 0; i < assets.length; i++) {
    // 모든 마켓을 순회하며 담보 가치 합산
}
```

문제: 사용자가 참여한 마켓이 많을수록 **가스비가 선형으로 증가**한다.

### Aave V3: 비트맵

```solidity
// 하나의 uint256에 128개 자산의 상태를 담는다
// 각 자산이 2비트를 차지: [담보 사용 여부][대출 여부]
mapping(address => UserConfigurationMap) internal _usersConfig;

struct UserConfigurationMap {
    uint256 data;  // 256비트 = 128개 자산 × 2비트
}
```

비트맵의 구조:

```
비트 위치:  ... | 5 | 4 | 3 | 2 | 1 | 0 |
자산 ID:        |  2  |  1  |  0  |
의미:       ... | C | B | C | B | C | B |
                  B = Borrowing (대출 중)
                  C = Collateral (담보로 사용 중)
```

Health Factor 계산 시:

```solidity
// 비트맵에서 해당 비트가 0이면 스킵
if (userConfig.data & (1 << (reserveIndex * 2)) == 0) {
    continue;  // 이 자산은 대출도 담보도 아님 → O(1)로 스킵
}
```

### 성능 비교

```
Compound V2 (배열):
  10개 마켓 참여 → 10번 SLOAD + 루프 = ~50,000 gas

Aave V3 (비트맵):
  128개 마켓 확인 → 1번 SLOAD + 비트 연산 = ~2,100 gas
```

비트 연산(`AND`, `SHIFT`)은 3 gas다. 128개 자산을 확인해도 `2,100 + 128 × 3 = 2,484 gas`. 배열 방식 대비 **약 20배 절약**이다.

이 차이가 결정적인 이유: Health Factor 계산은 **모든 트랜잭션에서 발생**한다. supply, borrow, repay, liquidate 전부. 가장 빈번하게 호출되는 로직의 가스를 20배 줄이면 프로토콜 전체의 가스 효율이 극적으로 개선된다.

---

## LendingPool 리팩토링: 배운 것을 적용하기

스터디 프로젝트의 `LendingPool.sol`에 Aave V3의 PoolStorage 패턴을 적용했다.

### Before: 단순 매핑

```solidity
mapping(address => mapping(address => uint256)) public deposits;
mapping(address => mapping(address => uint256)) public borrows;
```

### After: 구조화된 스토리지

```solidity
struct ReserveData {
    uint128 liquidityIndex;
    uint128 variableBorrowIndex;
    uint128 currentLiquidityRate;
    uint128 currentVariableBorrowRate;
    uint40 lastUpdateTimestamp;
    uint16 id;
    address aTokenAddress;
    address variableDebtTokenAddress;
    uint128 totalDeposits;
    uint128 totalBorrows;
}

mapping(address => ReserveData) internal _reserves;
mapping(uint256 => address) internal _reservesList;
uint16 internal _reservesCount;

mapping(address => UserConfigurationMap) internal _usersConfig;
```

핵심 변경점:
- `_reserves`: 자산 주소 → ReserveData 매핑 (모든 자산 상태를 하나의 구조체로)
- `_reservesList`: reserveId → 자산 주소 매핑 (비트맵 인덱싱용)
- `_usersConfig`: 사용자별 비트맵 (담보/대출 상태)

비트맵 헬퍼도 구현했다:

```solidity
function isUsingAsCollateral(UserConfigurationMap memory self, uint256 reserveIndex)
    internal pure returns (bool) {
    return (self.data >> (reserveIndex * 2 + 1)) & 1 != 0;
}

function isBorrowing(UserConfigurationMap memory self, uint256 reserveIndex)
    internal pure returns (bool) {
    return (self.data >> (reserveIndex * 2)) & 1 != 0;
}
```

리팩토링 후 모든 62개 테스트(기존 61 + 비트맵 테스트 1)가 통과했다.

---

## JumpRateModel 테스트: Fuzz Testing까지

Day 1에서 이론으로 다룬 JumpRateModel을 실제로 구현하고 테스트했다.

### Unit Test: 18개 케이스

```
[PASS] testGetBorrowRate_ZeroUtilization()
[PASS] testGetBorrowRate_AtKink()
[PASS] testGetBorrowRate_AboveKink()
[PASS] testGetBorrowRate_FullUtilization()
[PASS] testGetSupplyRate_WithReserveFactor()
... (18개 전부 통과)
```

### Fuzz Test: 6개 케이스

```solidity
function testFuzz_BorrowRateMonotonicity(uint256 util1, uint256 util2) public {
    util1 = bound(util1, 0, 1e18);
    util2 = bound(util2, util1, 1e18);

    uint256 rate1 = model.getBorrowRate(cash1, borrows1, reserves1);
    uint256 rate2 = model.getBorrowRate(cash2, borrows2, reserves2);

    assertGe(rate2, rate1);  // 사용률이 높으면 이자율도 높아야 한다
}
```

Fuzz Testing으로 검증한 불변 조건:
- **단조 증가**: 사용률이 올라가면 이자율도 올라간다
- **Supply ≤ Borrow**: Supply Rate은 항상 Borrow Rate 이하
- **Kink에서의 연속성**: kink 전후로 이자율이 비연속적으로 뛰지 않는다

전체 24개 테스트 (18 unit + 6 fuzz) 모두 통과.

---

## Day 2 핵심 인사이트 정리

1. **Fresh 패턴은 렌딩의 정합성을 보장한다** - 이자를 먼저 정산하지 않으면 교환비율이 부정확해져서 기존 사용자가 손해본다. "이자부터, 그 다음 본론"이 원칙.

2. **Lazy Interest Accrual은 가스 효율의 핵심** - 매 블록이 아니라 트랜잭션이 발생할 때만 이자를 계산한다. 4개의 SSTORE로 전체 사용자의 이자를 한번에 정산.

3. **렌딩은 3가지 유형** - Pool-based(예치금에서 빌림), CDP-based(새 토큰 발행), Fixed-rate(할인 토큰). 대부분이 Pool-based인 이유는 구현 단순성과 유동성 형성의 용이함.

4. **비트맵이 아키텍처를 결정한다** - Compound의 배열 vs Aave의 비트맵. 한 번의 SLOAD로 128개 자산 상태를 확인하는 것은 단순한 최적화가 아니라, Health Factor 계산이 모든 트랜잭션에서 발생하기 때문에 **프로토콜 전체 가스 효율**을 좌우한다.

5. **Storage 레이아웃이 아키텍처를 결정한다** - Compound는 배열 중심이라 Monolithic이 자연스럽고, Aave는 비트맵 + 구조체 중심이라 Modular가 자연스럽다. 데이터 구조가 코드 구조를 결정한다.

---

## Next: Day 3

내일은 **청산(Liquidation) 메커니즘**을 파고든다.

- 청산 트리거 조건과 `liquidateBorrowFresh()` 코드 리딩
- 청산 보너스(Liquidation Incentive) 경제학
- Foundry Fork Testing으로 Aave V3 메인넷 청산 시뮬레이션
- 고급 Foundry 테스팅 패턴 (invariant, fork)

---

*이 시리즈의 전체 코드와 학습 자료는 [lending-protocol-study](https://github.com/jeongseup/lending-protocol-study) 레포에서 확인할 수 있다.*
