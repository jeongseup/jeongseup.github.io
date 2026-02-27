---
title: "DefiDash 시작 계기: Defi Saver for Sui"
date: 2025-12-11
draft: false
authors: ["Jeongseup"]
description: "DefiDash 프로젝트가 탄생하기까지의 과정. CURG 13기에서 Sui 생태계 방향성을 논의하고, Defi Saver를 분석하여 Sui 버전 레버리지 렌딩 어그리게이터를 구상한 이야기."
slug: defidash-journal-origin
tags: ["DeFi", "Lending", "Sui", "Defi Saver", "Leverage"]
categories: ["Technical Research"]
series: ["DefiDash Technical Journal"]
math: true
---

> CURG 13기 활동 중 DefiDash 프로젝트가 시작된 배경과, 레퍼런스인 Defi Saver를 분석한 기록.
>
> **Team:** [curg-13](https://github.com/curg-13)

---

## 1. 프로젝트 히스토리

이 프로젝트는 [CURG(Crypto United Research Group)](https://www.curg.co/)라는 한국 블록체인 스터디에서 출발했다. 퇴사 후 13기로 합류했고, 이번 기수의 활동기간은 2025.10.11부터 2026.3.28이었다. DefiDash는 2025.12부터 본격적으로 개발을 시작한 프로젝트다.

### 초기 방향 탐색

처음에는 Sui Stack(Walrus, Seal, Nautilus, DeepBook 등)을 활용해서 재미있는 것들을 만들어보려 했다. 하지만 팀원들과 나 모두 Sui Stack 자체에 크게 흥미를 잃었다.

간단히 써본 결과, 해당 스택은 커머셜한 Web2 비즈니스를 Web3화하는 방향에 초점이 맞춰진다고 느꼈기 때문이다.

EVM 생태계에서는 필요한 인프라를 유저(커뮤니티)가 직접 개발하고 비즈니스화하면서 상호작용하는 반면, Sui에서는 필요한 인프라를 재단 레벨에서 미리 구상하고 생태계 툴로 자리잡아둔 구조다. 블록체인을 구축하고 개발자를 유치하는 전략적 차이라고 생각한다.

### 방향성 좁히기

이후 팀원들과의 회의를 통해 초기 방향을 아래 3가지로 좁혔다.

1. **Pendle to Sui + Lucky Gaming** — 기존에 Walrus Haultout 해커톤에서 Sui random module을 활용해 나간 경험을 확장
2. **Defi Saver to Sui** — Sui에 렌딩 프로토콜이 여럿 있으니 이를 aggregation 하는 것으로 출발
3. **Academic Research in Sui** — 오픈소스 Move DeFi 컨트랙트를 분석하면서 EVM과 MoveVM 차이를 비교

약 2주간의 논의를 거쳐, 2025.12.11 시점에 **Defi Saver for Sui**로 방향을 결정지었다.

---

## 2. Defi Saver 분석

### Defi Saver란?

[Defi Saver](https://defisaver.com/)를 간단히 말하면, **crypto portfolio dashboard + leverage yield farming(looping)** 플랫폼이다. 추후 포지션 규모가 크면 자동으로 포지션을 조절해주는 기능도 제공한다.

가령 담보로 맡긴 BTC가 급락하는 경우, liquidation을 방지하기 위해 leverage multiplier를 자동으로 줄여준다는 뜻이다.

Defi Saver 말고도 비슷한 crypto asset dashboard 서비스는 다양하다.

- [Defi Saver 공식 소개](https://help.defisaver.com/general/what-is-defi-saver)
- [DefiLlama - Defi Saver](https://defillama.com/protocol/defi-saver)
- [Alchemy - Best Crypto Portfolio Dashboards](https://www.alchemy.com/dapps/best/crypto-portfolio-dashboards)

### 특장점

- **Safe(Gnosis) Smart Wallet 사용**: 처음 접속 시 유저에게 Smart Wallet을 생성하도록 한다.
  - Automation 기능 지원을 위해서이며, `execTransaction` 같은 여러 트랜잭션을 하나로 묶어서 실행하기 위함이다.
  - 이걸 보고 **Sui에서는 PTB가 네이티브하게 지원되니까 오히려 만들기 편하겠다**는 생각을 했다.
- **Looping 레버리지**: 유저가 BTC를 맡기면 LTV에 따라 최대 레버리지까지 USDC를 빌려서 → 그 금액으로 BTC를 다시 사서 → 재예치하는 looping 방식을 지원한다.
- **직관적인 UX**: Liquidation price, 여러 리스크 팩터 등이 한눈에 보인다. 처음에는 별것 아닌 것 같았지만, 막상 만들어보니 이런 디테일한 정보를 잘 관리하고 UX로 풀어내는 게 쉽지 않다는 걸 뒤늦게 알게 되었다.

### Defi Saver 직접 사용해보기

아래는 직접 써본 예시다.

![Defi Saver leverage 포지션 오픈 화면](/img/defidash/defisaver-leverage-example.png)

가격이 변동함에 따라, 담보 자산(여기선 cbBTC) 상승 시 레버리지 효과를 가질 수 있게 된다.

![가격 변동에 따른 레버리지 효과](/img/defidash/defisaver-leverage-result.png)

기본적으로 내 EOA(MetaMask 지갑 주소)에서 호출한 컨트랙트 메소드는 다음과 같다. 해당 rollup tx 안에는 여러 로직이 포함되어 있는 구조다.

```solidity
Function: execTransaction(
  address to, uint256 value, bytes data, uint8 operation,
  uint256 safeTxGas, uint256 baseGas, uint256 gasPrice,
  address gasToken, address refundReceiver, bytes signatures
)
```

Net Transfer로 보면 로직이 보다 명확해진다.

![Net Transfer 상세](/img/defidash/defisaver-net-transfer.png)

> 실제 트랜잭션: [basescan.org/tx/0x0869a6...](https://basescan.org/tx/0x0869a6913cda22441ec9ed568f72336602969d214db690dac6e22e23102073ef)

참고로 Defi Saver에서는 Flash Loan으로 빌린 금액의 **0.25%를 서비스 수수료**로 받는 비즈니스 모델을 가진다.

![서비스 수수료 구조](/img/defidash/defisaver-service-fee.png)

포지션을 다음과 같이 preview 형태로도 제공해준다.

![포지션 프리뷰](/img/defidash/defisaver-position-preview.png)

포지션을 종료하면 기존 로직을 역행하는 과정을 거친다. 기본적으로 looping 과정에서 Morpho Flash Loan을 사용한다.

![포지션 종료(close position)](/img/defidash/defisaver-close-position.png)

> Close position tx: [basescan.org/tx/0xe04ccb...](https://basescan.org/tx/0xe04ccbbd780f79de493dca0a000a0bfcf63c26bedbb1f078abb4d12413e09e5d)

---

## 3. 구조 분석

### Leverage Max Multiplier

최대 레버리지 배수는 다음과 같이 결정된다.

![Max multiplier 산출 공식](/img/defidash/defisaver-max-multiplier.png)

$$\text{Max Multiplier} = \frac{1}{1 - \text{LTV}}$$

### Leverage 내부 트랜잭션 구조

롤업된 트랜잭션을 의미별로 구조화하면 3가지 컴포넌트로 나뉜다.

1. **Flash Loan** — 레버리지에 필요한 초기 자금 확보
2. **Swap** — 빌린 스테이블코인을 담보 자산으로 교환
3. **Deposit & Lending** — 렌딩 프로토콜에 담보 예치 및 대출

---

## 4. DefiDash 프로젝트 구상

위 분석을 바탕으로, 이번 13기 과정에서는 **leverage, deleverage(포지션 on/off) 정도만 지원하는 MVP**를 만들기로 했다.

각 컴포넌트별로 Sui 생태계에서 사용할 프로토콜을 매핑하면 다음과 같다.

### Flash Loan

레버리지 루핑에 필요한 스테이블코인을 어디서 빌려올 것인가?

- Scallop
- NAVI

### Swap (Aggregator / DEX)

Flash Loan으로 빌려온 스테이블코인을 최적 비율로 담보 자산으로 교환할 곳은?

- Aftermath
- Cetus
- 7k Protocol

### Deposit & Lending

레버리지 포지션의 유지 비용(Supply APR - Borrow APR)이 가장 저렴한 곳은?

- Suilend
- NAVI
- Scallop
- Bluefin

> Flash Loan 출처가 Scallop이라고 해서 렌딩 프로토콜도 반드시 Scallop일 필요는 없다. 각 컴포넌트는 독립적으로 최적의 조합을 선택할 수 있다.

---

## 5. 프로젝트 목표 정의

**목표:** 3개 렌딩 프로토콜(Suilend, NAVI, Scallop)을 통합하는 leverage lending protocol aggregator 만들기.

### 최종 워크플로우

PTB 하나에 다음 5단계를 원자적으로 실행한다.

```
1. Flash Loan    ← Scallop
2. Swap          ← 7k Aggregator
3. Deposit       ← Lending Protocol (Suilend / NAVI / Scallop)
4. Borrow        ← 같은 Lending Protocol
5. Repay         ← Scallop (Flash Loan 상환)
```

각 컴포넌트를 TypeScript SDK 레벨로 먼저 만들어보고, 필요하다면 컨트랙트도 파헤쳐보는 것으로 방향을 잡았다.

프로젝트 완성 후에는 실제 레버리지 포지션을 통해 서비스 이용의 수익성을 검증할 계획이다.

---

## Next

다음 글에서는 실제 SDK 개발에 착수한다. Sui 렌딩 프로토콜의 온체인 데이터 구조를 분석하고, Protocol Adapter 패턴을 설계한 과정을 다룬다.

- [DefiDash Journal Day 1: 프로젝트 킥오프와 Sui 렌딩 생태계 분석](/p/defidash-technical-journal-day1/)

---

*DefiDash의 전체 코드는 [curg-13](https://github.com/curg-13) 조직에서 확인할 수 있다.*
