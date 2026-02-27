---
title: "Lending Protocol Study Day 1: DeFi 렌딩의 핵심 개념과 아키텍처"
description: "7일간의 DeFi Lending Protocol 스터디 시리즈. 풀 기반 중개, Share-Based Accounting, Scaled Balance 가스 최적화, Compound vs Aave 아키텍처까지."
slug: lending-protocol-study-day1
date: 2026-02-23
categories: []
tags:
    - DeFi
    - Lending
    - Compound
    - Aave
    - Solidity
    - Smart Contract
series:
    - Lending Protocol Study
math: true
---

> 7일간의 DeFi Lending Protocol 스터디 시리즈. 백엔드/인프라 엔지니어 관점에서 렌딩 프로토콜을 코드 레벨까지 파헤친다.
>
> **Repository:** [jeongseup/lending-protocol-study](https://github.com/jeongseup/lending-protocol-study)

---

## Why Lending Protocol?

블록체인 인프라 엔지니어로 일하면서 노드 운영, 밸리데이터 모니터링, 스테이킹 보상 분석 등을 해왔다. 그런데 DeFi의 가장 큰 축인 **렌딩 프로토콜**은 "대충 알겠는데 코드 레벨에서는 모른다"는 상태였다.

이번 스터디의 목표는 명확하다:
- Compound V2 / Aave V3의 핵심 로직을 **코드로 읽고 구현**한다
- 렌딩의 수학적 모델(이자율, 청산, Health Factor)을 **공식 수준**으로 이해한다
- Solidity + Go 모니터링 도구까지 만들어 **실무에 적용 가능한 수준**으로 올린다

---

## 렌딩 프로토콜의 본질: 풀 기반 중개

전통 금융의 대출은 대출자와 차입자를 1:1로 매칭한다. DeFi 렌딩은 다르다.

```
전통 금융:  Alice → [은행] → Bob  (1:1 매칭)
DeFi 렌딩:  Alice → [Pool] ← Bob  (풀 기반 간접 매칭)
```

예치자들이 자산을 풀에 넣으면, 차입자들이 담보를 걸고 풀에서 빌려간다. **아무도 누가 누구에게 빌려줬는지 모른다.** 이자율은 풀의 사용률(Utilization Rate)에 따라 알고리즘이 자동으로 결정한다.

이 구조의 핵심 이유는 간단하다:

```
블록체인 = 익명 → 신용평가 불가 → 담보로만 판단 → 과담보 필수
```

신용이 없으니 담보로 대체한다. 그래서 DeFi 렌딩은 태생적으로 **과담보(Over-collateralized)** 구조다.

---

## 렌딩의 5대 핵심 파라미터

렌딩 프로토콜을 이해하려면 이 5가지 숫자만 확실히 알면 된다.

| 파라미터 | 의미 | 일반적 범위 |
|---------|------|-----------|
| **LTV** (Loan-to-Value) | 담보 대비 얼마까지 빌릴 수 있나 | 75-80% |
| **Health Factor** | 내 포지션이 안전한가 (< 1이면 청산) | 1.0 이상 유지 |
| **Utilization Rate** | 풀의 자금 중 얼마가 빌려졌나 | 이자율 결정 |
| **Reserve Factor** | 프로토콜이 이자에서 떼가는 비율 | 10-35% |
| **Collateral Factor** | 자산의 담보 가치 인정 비율 | 자산마다 다름 |

### 외워야 할 공식 3개

$$HF = \frac{LT}{LTV}$$

$$\text{최대 허용 하락률} = 1 - \frac{LTV}{LT}$$

$$\text{Supply APY} = \text{Borrow APR} \times \text{Utilization} \times (1 - \text{Reserve Factor})$$

세 번째 공식이 특히 중요하다. Supply APY가 Borrow APR보다 **수학적으로 항상 작은** 이유가 여기 있다. 풀의 돈이 100% 빌려진 게 아니고(Utilization < 1), 프로토콜이 Reserve Factor만큼 떼가기 때문이다.

> 단, 토큰 인센티브(COMP, AAVE)나 포인트/에어드랍까지 포함하면 역전될 수 있다. 2020년 DeFi Summer에 "빌리면 돈 버는" 상황이 실제로 발생했다.

---

## 이자율 모델: Jump Rate Model

"사용률이 올라가면 이자율도 올라간다"는 단순한 원칙이지만, 구현 방식은 프로토콜마다 다르다.

| 프로토콜 | 모델 | 특징 |
|---------|------|------|
| Compound V2 | Jump Rate Model | 원조. kink 지점에서 이자율 급등 |
| Aave V3 | Variable Rate Strategy | 비슷하지만 파라미터 구조 다름 |
| MakerDAO | 거버넌스 직접 설정 | 알고리즘 아님 |
| Euler V2 | 모듈형 | 풀 생성자가 모델 직접 선택 |

DEX에서 `x * y = k` (CPMM)가 원조 모델이듯, 렌딩에서는 Jump Rate Model이 원조다. "유일한 표준"은 아니지만, 대부분의 모델이 이걸 변형한 것이다.

---

## cToken vs aToken: 이자를 반영하는 두 가지 방법

렌딩에 자산을 예치하면 "영수증 토큰"을 받는다. 이 영수증이 이자를 반영하는 방식이 Compound와 Aave에서 근본적으로 다르다.

### Compound의 cToken: 교환비율 상승

```
예치: 1,000 USDC → 50,000 cUSDC (교환비율 0.02)
1년후: 50,000 cUSDC 그대로, 교환비율 0.025로 상승
인출: 50,000 × 0.025 = 1,250 USDC
```

토큰 수량은 변하지 않고, **교환비율이 올라간다.**

### Aave의 aToken: 잔고 자동 증가 (Rebase)

```
예치: 1,000 USDC → 1,000 aUSDC (1:1)
1년후: 지갑에 1,050 aUSDC로 자동 증가
인출: 1,050 aUSDC → 1,050 USDC
```

교환비율은 1:1 고정이고, **토큰 수량이 늘어난다.**

| 비교 | cToken | aToken |
|------|--------|--------|
| UX | 비직관적 (교환비율 계산 필요) | 직관적 (잔고 = 실제 가치) |
| DeFi 호환성 | 유리 (표준 ERC20) | 불리 (rebase 토큰) |
| 수학 | `amount = shares × exchangeRate` | `balance = scaledBalance × index` |

수학적으로는 동일하다. **"언제 곱하느냐"의 차이일 뿐이다.**

---

## Share-Based Accounting: DeFi의 범용 패턴

cToken의 교환비율 패턴은 사실 DeFi 전반에서 반복되는 범용 패턴이다.

```
지분으로 변환 → 전역 비율만 업데이트 → 인출 시 역변환
```

이 패턴을 쓰는 곳들:

| 프로토콜 | 용도 |
|---------|------|
| Compound cToken | 렌딩 예치 영수증 |
| ERC-4626 | 토큰화된 Vault 표준 |
| Lido wstETH | Liquid Staking |
| Rocket Pool rETH | Liquid Staking |
| Walrus StakingPool | 스토리지 네트워크 스테이킹 |

Walrus의 `StakingPool`과 비교하면:

```
Compound cToken:
  exchange_rate = (totalCash + totalBorrows - totalReserves) / totalSupply
  deposit:  shares = amount / exchange_rate
  withdraw: amount = shares × exchange_rate

Walrus StakingPool:
  exchange_rate = total_wal / total_shares
  stake:    shares = principal × total_shares / total_wal
  withdraw: amount = shares × total_wal / total_shares
```

**같은 공식이다. 변수명만 다르다.**

---

## 가스 최적화의 핵심: Scaled Balance

aToken이 "잔고가 자동으로 늘어난다"면, 매번 모든 사용자의 잔고를 업데이트하는 걸까? 당연히 아니다. 그러면 가스비가 폭발한다.

핵심 아이디어: **쓰기를 읽기로 바꾼다.**

```
Scaled Balance = 예치금 / 예치 시점의 liquidityIndex
```

이 값은 한번 저장되면 **절대 변하지 않는다.** 변하는 건 전역 `liquidityIndex` 하나뿐이다.

잔고를 조회할 때 `scaledBalance × 현재 index`로 계산한다. `balanceOf()`는 view 함수이므로 가스비가 0이다.

```
순진한 방식: 이자 발생 시 모든 사용자 잔고 SSTORE
  → 1,000명 × 5,000 gas = 5,000,000 gas

Scaled Balance: 전역 index 1개만 SSTORE
  → 5,000 gas
  → 99.9% 절약
```

EVM에서 `SSTORE`(쓰기)는 5,000 gas, `MUL`(곱셈)은 5 gas다. **쓰기는 계산보다 1,000배 비싸다.** Merkle Patricia Trie를 재계산하고 모든 노드에 영구 저장해야 하기 때문이다. Scaled Balance는 이 비용 구조를 정확히 활용한 최적화다.

---

## Compound V2 vs Aave V3: 아키텍처 차이

두 프로토콜의 가장 큰 차이는 코드 구조에 있다.

```
Compound: CToken이 풀 역할까지 겸함 (Monolithic)
  사용자 → CToken.mint()

Aave/우리 프로젝트: Pool과 토큰 분리 (Modular)
  사용자 → Pool.deposit() → aToken.mint()
```

Compound의 CToken은 ERC20 토큰이면서 동시에 렌딩 풀이다. `mint()`, `borrow()`, `repay()`, `liquidate()` 모두 CToken 컨트랙트에 있다. 반면 Aave는 Pool이 중심이고 aToken은 순수한 영수증 토큰이다.

### Compound V2 코드 리딩 가이드

Compound V2 코드를 읽고 싶다면, 핵심 **3개 파일, 5개 함수**만 보면 된다.

**CToken.sol** - 핵심 함수 5개:
- `accrueInterest()` - 이자 누적 (borrowIndex = scaled balance 패턴)
- `mintFresh()` - 예치
- `borrowFresh()` - 대출
- `repayBorrowFresh()` - 상환
- `liquidateBorrowFresh()` - 청산

**Comptroller.sol** - 핵심 함수 1개:
- `getHypotheticalAccountLiquidityInternal()` - Health Factor 계산

**BaseJumpRateModelV2.sol** - 이자율 모델

나머지(Governance, Lens, Timelock 등)는 렌딩 로직과 무관하므로 무시해도 된다.

---

## 이자율의 3개 레이어

DeFi에서 실제 수익률은 단순한 이자율이 아니라 3개 레이어의 합이다.

```
Layer 1: 기본 이자        → Jump Rate Model이 결정
Layer 2: 토큰 인센티브    → COMP, AAVE 등 거버넌스 토큰 보상
Layer 3: 포인트/에어드랍  → Blast, EigenLayer 등
```

Layer 2, 3까지 포함하면 "빌리면 돈 버는" 상황도 발생한다. 2020 DeFi Summer에 COMP 보상이 대출 이자보다 커서 Compound에서 빌리는 것 자체가 수익이었던 것이 대표적인 사례다.

---

## Day 1 핵심 인사이트 정리

1. **렌딩의 본질은 풀 기반 중개** - 예치자와 대출자를 직접 매칭하지 않고, 풀을 통해 간접 매칭한다. 스테이킹 풀과 동일한 패턴.

2. **Share-Based Accounting은 DeFi의 범용 패턴** - cToken, ERC-4626, wstETH, rETH, Walrus 전부 같은 원리. "지분으로 변환 → 전역 비율만 업데이트 → 인출 시 역변환."

3. **가스 최적화의 핵심은 "쓰기를 읽기로 바꾸기"** - SSTORE는 계산보다 1,000배 비싸다. Scaled Balance 패턴으로 전역 index 하나만 업데이트하고 나머지는 읽기 시점에 계산.

4. **Compound는 Monolithic, Aave는 Modular** - CToken이 풀 겸 토큰 vs Pool과 토큰 분리.

5. **실제 수익률 = 기본 이자 + 토큰 인센티브 + 포인트** - 3개 레이어를 모두 봐야 DeFi의 실제 경제를 이해할 수 있다.

---

## Next: Day 2

내일은 **Aave V3 아키텍처를 코드 레벨로** 들어간다.

- `Pool.sol`, `SupplyLogic.sol`, `BorrowLogic.sol`, `LiquidationLogic.sol` 리딩
- Fork Testing으로 Aave V3 메인넷 상태에서 직접 테스트
- Fuzz Testing으로 이자율 엣지 케이스 탐색

---

*이 시리즈의 전체 코드와 학습 자료는 [lending-protocol-study](https://github.com/jeongseup/lending-protocol-study) 레포에서 확인할 수 있다.*
