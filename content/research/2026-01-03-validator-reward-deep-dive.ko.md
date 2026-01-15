---
title: "Validator Reward Deep Dive Series"
date: 2026-01-03
categories:
    - "Technical Research"
tags: ["research", "blockchain", "validator", "rewards", "archive"]
series: ["Validator Reward Deep Dive"]
math: true
---

## Context & Motivation

This series was originally authored during my tenure at [Cosmostation](https://cosmostation.io/), working with the Validator Team. The primary goal of this research was to provide a technical foundation for developing **in-house validator monitoring and reward management tools**.

To build robust infrastructure, we needed to go beyond the surface and understand the exact mathematical and programmatic flow of rewards across different blockchain architectures. This series documents that journey, covering Cosmos, Sui, Kaia, and Namada.

---

## Series Index

### 1. [Walrus: The Secret of Staking Rewards](https://medium.com/cosmostation/validator-reward-deep-dive-series-1-walrus-the-secret-of-staking-rewards-a-complete-guide-to-87240f4af3af)

- **Focus:** Walrus 프로토콜의 보상 분배 메커니즘, 에포크 변경 및 환율 계산 로직 분석.
- **Key Insight:** `initiate_epoch_change`와 `process_pending_stake`를 심층 분석하여 스테이킹 시점과 출금 시점의 환율 차이로 보상이 결정되는 과정을 설명합니다.

### 2. [Sui: How are Epoch Rewards Delivered to Stakers?](https://medium.com/cosmostation/validator-reward-deep-dive-series-2-sui-how-are-epoch-rewards-delivered-to-stakers-86765ce1c7ae)

- **Focus:** Sui 프로토콜의 네이티브 스테이킹 보상 메커니즘과 `sui_system` Move 패키지를 통한 에포크 단위 보상 분배.
- **Key Insight:** `StakingPool`의 환율(Exchange Rate)이 보상을 통해 어떻게 우상향하는지 설명하고, 스테이킹 및 출금 시점의 환율 차이로 보상이 산정되는 원리를 다룹니다.

### 3. [Cosmos: How do Inflation and Fees become Delegator Rewards?](https://medium.com/cosmostation/validator-reward-deep-dive-series-3-cosmos-how-do-inflation-and-fees-become-delegator-rewards-6d41c781a7b6)

- **Focus:** `x/mint`, `x/auth`, `FeeCollector`, `x/distribution`, `x/staking` 모듈 간의 상호작용을 통한 보상 생성 및 분배의 유기적인 과정.
- **Key Insight:** 인플레이션과 수수료가 `FeeCollector`에 모여 검증인 풀로 이동하고, '누적 보상 비율(Cumulative Reward Ratio)'과 지분(Share)을 기반으로 델리게이터에게 최종 분배되는 F1 모델의 흐름을 설명합니다.

### 4. [Kaia: Staking Rewards in Public Delegation Contract](https://medium.com/cosmostation/validator-reward-deep-dive-series-4-kaia-kaia-staking-rewards-in-public-delegation-contract-7f9f376cdf75)

- **Focus:** `PublicDelegation.sol` 시스템 컨트랙트와 ERC-20 기반 지분(Share) 토큰을 중심으로 한 스테이킹 보상 메커니즘.
- **Key Insight:** `stake()` 호출 시 자동 재예치(Auto-compounding)가 발생하여 풀의 총 KAIA가 증가하고, 이로 인해 지분 가치가 상승(Value Accrual)하여 보상이 실현되는 원리를 설명합니다.

### 5. [Namada: PoS Staking and Inflation in Namada](https://medium.com/cosmostation/validator-reward-deep-dive-series-5-namada-pos-staking-and-inflation-in-namada-5e8a2f061364)

- **Focus:** 나마다(Namada)의 에포크 기반 PoS 인플레이션과 'Reward Product' 방식을 이용한 독창적인 보상 기록 메커니즘.
- **Key Insight:** 매 에포크마다 위임 지분당 보상 비율인 `reward_product`가 기록되며, 이를 통해 델리게이터의 보상이 `위임량 * reward_product`의 합으로 산정되는 원리를 설명합니다.

---

## Reflection

Building tools for a top-tier validator team requires a "don't trust, verify" mindset toward protocol specifications. These articles served as the technical blueprint for our engineering team to ensure reward calculation accuracy and operational excellence.

I hope this archive remains a useful resource for anyone diving deep into the economics of Proof-of-Stake networks.
