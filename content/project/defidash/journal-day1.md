---
title: "DefiDash Technical Journal Day 1: 프로젝트 킥오프와 Sui 렌딩 생태계 분석"
date: 2026-02-27
draft: false
authors: ["Jeongseup"]
description: "DefiDash 프로젝트의 시작. Sui 생태계의 렌딩 프로토콜들을 분석하고, 레버리지 렌딩 어그리게이터의 아키텍처를 설계한 기록."
slug: defidash-technical-journal-day1
tags: ["DeFi", "Lending", "Sui", "Aggregator", "TypeScript"]
categories: ["Technical Research"]
series: ["DefiDash Technical Journal"]
math: false
---

> DefiDash 개발 과정을 기록하는 테크니컬 저널 시리즈. Day 1에서는 프로젝트의 동기와 목표, Sui 생태계의 렌딩 프로토콜 현황, 그리고 레버리지 렌딩 어그리게이터의 아키텍처 설계를 다룬다.
>
> **Team:** [curg-13](https://github.com/curg-13)

---

## 왜 DefiDash인가

DeFi 렌딩 시장은 이미 성숙해있다. Ethereum에는 Aave, Compound, MakerDAO가 있고, 다른 체인에도 포크된 프로토콜들이 넘쳐난다. 그런데 **Sui 생태계**는 다르다.

Sui는 Move 기반의 Object-centric 모델을 사용한다. EVM의 Account-based 모델과 근본적으로 다른 패러다임이다. 이 차이는 DeFi 프로토콜 설계에도 영향을 미친다:

- **Object Ownership**: 자산이 계정이 아닌 오브젝트로 관리된다
- **Parallel Execution**: 독립적인 오브젝트 간 트랜잭션은 병렬 실행 가능
- **PTB (Programmable Transaction Blocks)**: 하나의 트랜잭션에서 여러 DeFi 연산을 원자적으로 실행

특히 PTB는 레버리지 렌딩에 결정적이다. EVM에서는 Flash Loan으로 여러 트랜잭션을 하나로 묶지만, Sui에서는 PTB로 **네이티브하게** 복합 연산이 가능하다.

문제는 Sui의 렌딩 프로토콜들이 아직 파편화되어 있다는 것이다. 각 프로토콜마다 다른 인터페이스, 다른 이자율 모델, 다른 담보 비율. 일반 사용자가 최적의 레버리지 전략을 찾는 것은 사실상 불가능하다.

**DefiDash는 이 문제를 해결한다.** Sui 생태계의 렌딩 프로토콜들을 하나의 인터페이스로 어그리게이트하여, 사용자에게 최적의 레버리지 전략을 제공한다.

---

## 프로젝트 구조

curg-13 팀으로 3개의 레포지토리를 구성했다.

```
curg-13/
├── defidash-sdk          # 핵심 SDK - 프로토콜 통합 레이어
├── defidash-frontend     # 사용자 facing DApp
└── defidash-website      # 랜딩 페이지 & 문서
```

### defidash-sdk

프로토콜 어그리게이션의 핵심이다. 각 렌딩 프로토콜의 인터페이스를 추상화하고, 통합된 API를 제공한다.

**주요 책임:**
- 각 프로토콜의 온체인 데이터 조회 (이자율, 담보 비율, 유동성)
- 레버리지 포지션 시뮬레이션
- PTB 구성 및 트랜잭션 빌딩
- 최적 경로 계산 (어떤 프로토콜 조합이 가장 유리한지)

### defidash-frontend

일반 사용자를 위한 DApp이다. 복잡한 레버리지 전략을 직관적인 UI로 제공한다.

**핵심 UX 목표:**
- 원클릭 레버리지 포지션 오픈/클로즈
- 실시간 Health Factor 모니터링
- 프로토콜 간 이자율 비교 대시보드

### defidash-website

프로젝트 소개와 문서를 담는 마케팅 사이트다.

---

## Sui 렌딩 생태계 현황

현재 Sui에서 활동 중인 주요 렌딩 프로토콜들을 정리했다.

| Protocol | Type | Key Feature |
|----------|------|-------------|
| Scallop | Pool-based | Sui 최초의 렌딩 프로토콜, sCoin 모델 |
| NAVI Protocol | Pool-based | Dynamic interest rate, Flash Loan 지원 |
| Suilend | Pool-based | Solend 팀의 Sui 버전, Obligation 기반 |
| Bucket Protocol | CDP-based | BUCK 스테이블코인 발행 |

EVM 생태계와 비교하면 아직 초기 단계지만, 각 프로토콜이 Sui의 특성을 살린 독자적인 설계를 가지고 있다. 이 차이점이 곧 어그리게이션의 가치다.

---

## 아키텍처 설계: 어그리게이션 레이어

레버리지 렌딩 어그리게이터의 핵심은 **Protocol Adapter Pattern**이다.

```
사용자 → DefiDash Frontend
              ↓
         DefiDash SDK
              ↓
    ┌─────────┼─────────┐
    ↓         ↓         ↓
 Scallop   NAVI     Suilend    ← Protocol Adapters
 Adapter   Adapter  Adapter
    ↓         ↓         ↓
    └─────────┼─────────┘
              ↓
         Sui Network
```

각 프로토콜 Adapter는 동일한 인터페이스를 구현한다:

```typescript
interface LendingProtocolAdapter {
  // 프로토콜 상태 조회
  getMarkets(): Promise<Market[]>;
  getInterestRates(market: string): Promise<InterestRate>;
  getUserPosition(address: string): Promise<Position>;

  // 트랜잭션 빌딩
  buildSupplyTx(params: SupplyParams): TransactionBlock;
  buildBorrowTx(params: BorrowParams): TransactionBlock;
  buildLeverageTx(params: LeverageParams): TransactionBlock;
}
```

이 패턴의 장점은 새로운 프로토콜 추가가 Adapter 하나만 구현하면 된다는 것이다. SDK의 코어 로직이나 프론트엔드를 수정할 필요 없다.

---

## 레버리지 렌딩의 원리

일반 사용자를 위해 레버리지 렌딩이 어떻게 작동하는지 정리한다.

### 기본 개념

1. **담보 예치**: 1,000 USDC를 렌딩 프로토콜에 담보로 예치
2. **대출**: 담보 대비 700 SUI를 대출 (LTV 70%)
3. **재예치**: 대출받은 SUI를 다시 담보로 예치
4. **반복**: 이 과정을 반복하면 실효 레버리지가 증가

```
초기 자본: 1,000 USDC
1차 대출: 700 SUI → 재예치
2차 대출: 490 SUI → 재예치
3차 대출: 343 SUI → 재예치
...
실효 노출: ~3,333 USDC 상당 (약 3.3x 레버리지)
```

### Sui PTB의 이점

EVM에서는 이 과정을 Flash Loan + 여러 컨트랙트 호출로 구현해야 한다. 가스비도 높고 실패 리스크도 있다.

Sui의 PTB에서는 **하나의 트랜잭션 블록 안에서** 모든 단계를 원자적으로 실행할 수 있다:

```typescript
const txb = new TransactionBlock();

// 1. 담보 예치
const receipt = txb.moveCall({ target: `${PROTOCOL}::deposit`, arguments: [...] });

// 2. 대출
const borrowed = txb.moveCall({ target: `${PROTOCOL}::borrow`, arguments: [...] });

// 3. 재예치 (대출 결과를 바로 사용)
txb.moveCall({ target: `${PROTOCOL}::deposit`, arguments: [borrowed, ...] });

// 하나의 트랜잭션으로 실행
await client.signAndExecuteTransactionBlock({ transactionBlock: txb });
```

Flash Loan 없이도 원자적 레버리지가 가능하다. 이것이 Sui에서 렌딩 어그리게이터를 만드는 핵심 이유다.

---

## Day 1 정리

| 항목 | 결정 사항 |
|------|----------|
| 프로젝트명 | DefiDash |
| 팀 | curg-13 |
| 타겟 체인 | Sui |
| 핵심 기술 | PTB 기반 레버리지 렌딩 어그리게이션 |
| SDK 언어 | TypeScript |
| 아키텍처 | Protocol Adapter Pattern |
| 첫 통합 대상 | Scallop, NAVI, Suilend |

---

## Next: Day 2

다음 저널에서는 실제 SDK 개발을 시작한다.

- Sui 렌딩 프로토콜 온체인 데이터 구조 분석
- Protocol Adapter 구현 (Scallop부터)
- PTB 기반 레버리지 트랜잭션 빌딩

---

*DefiDash의 전체 코드는 [curg-13](https://github.com/curg-13) 조직에서 확인할 수 있다.*
