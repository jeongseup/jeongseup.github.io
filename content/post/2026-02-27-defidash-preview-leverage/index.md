---
title: "Building a Leverage Position Preview for DeFi on Sui"
date: 2026-02-27
draft: false
authors: ["Jeongseup"]
description: "How I built previewLeverage — a read-only preview engine that calculates leveraged lending position metrics across Suilend, Navi, and Scallop, without executing any on-chain transaction."
slug: defidash-preview-leverage
image: defidash-logo.jpeg
tags: ["DeFi", "Lending", "Sui", "Aggregator", "TypeScript", "Suilend", "Scallop"]
categories: ["Technical Research"]
series: ["DefiDash Technical Journal"]
math: true
---

> How I built `previewLeverage` — a read-only preview engine that calculates leveraged lending position metrics across Suilend, Navi, and Scallop, without executing any on-chain transaction.
>
> **Team:** [curg-13](https://github.com/curg-13) | **SDK:** [defidash-sdk](https://github.com/curg-13/defidash-sdk)

---

## Why Preview Before Leverage?

In DeFi lending, **leverage** means borrowing against your collateral to amplify your position. A 2x leverage on $100 of SUI gives you $200 total exposure — potentially doubling your returns, but also your risk.

Before users click "Confirm", they need to know:
- How much will be borrowed via flash loan?
- What's the liquidation price?
- What's the expected annual return (Net APY)?
- How far can the price drop before liquidation?

That's what `previewLeverage` computes — entirely off-chain, using real-time protocol data.

```typescript
const preview = await sdk.previewLeverage({
  protocol: LendingProtocol.Suilend,
  depositAsset: 'SUI',
  depositValueUsd: 100,
  multiplier: 2.0,
});

// preview.netApy          → 2.33%
// preview.liquidationPrice → $0.63
// preview.priceDropBuffer  → 33%
```

---

## Glossary: Lending Protocol Concepts

If you're a developer without DeFi background, here's what you need to know. I'm also studying these concepts in depth — check the **Lending Protocol Study** series for worked examples:

- [Day 1: DeFi 렌딩의 핵심 개념과 아키텍처](/p/lending-protocol-study-day1/) — Pool-based 중개, Share-Based Accounting, Scaled Balance 패턴
- [Day 2: Compound V2 Deep Dive와 Aave V3 아키텍처](/p/lending-protocol-study-day2/) — Fresh 패턴, Mantissa 연산, 비트맵 스토리지 최적화

### LTV (Loan-to-Value)

**LTV** is the maximum percentage of your collateral's value that you can borrow.

$$\text{LTV} = \frac{\text{Borrowed Value}}{\text{Collateral Value}}$$

If SUI has a 70% LTV on Suilend, depositing $100 of SUI lets you borrow up to $70 of USDC. Each protocol sets different LTV ratios per asset — riskier assets get lower LTV.

| Protocol | SUI LTV | XBTC LTV |
|----------|---------|----------|
| Suilend  | 70%     | 60%      |
| Navi     | 75%     | 67%      |
| Scallop  | 85%     | 75%      |

> For more details on how Health Factor works with LTV, see [Lending Protocol Study Day 1](/p/lending-protocol-study-day1/) — the "Share-Based Accounting" section explains why each protocol tracks collateral differently.

### Liquidation Threshold (LT)

**Liquidation Threshold** is the LTV level at which your position gets liquidated. It's always higher than the borrow LTV, creating a safety buffer.

```
Borrow LTV: 70%  →  You can borrow up to 70%
Liq. Threshold: 75%  →  Liquidation triggers at 75%
Safety buffer: 5%
```

When the market price drops and your position's actual LTV exceeds the liquidation threshold, a liquidator can repay part of your debt and claim your collateral at a discount.

> Liquidation mechanics are a deep topic — the [Lending Protocol Study](/p/lending-protocol-study-day2/) series covers Compound V2's `liquidateBorrowFresh()` and Aave V3's architecture in detail.

### Max Multiplier

Derived directly from LTV:

$$\text{Max Multiplier} = \frac{1}{1 - \text{LTV}}$$

With 70% LTV → max 3.33x leverage. With 85% LTV → max 6.67x. This is a hard protocol limit — you physically cannot borrow more than what the collateral factor allows.

### Flash Loan

A flash loan is an **uncollateralized loan that must be borrowed and repaid within a single atomic transaction**. If you don't repay, the entire transaction reverts as if it never happened.

In our leverage strategy, the flow is:
1. Flash loan USDC from Scallop
2. Swap USDC → deposit asset (e.g., SUI)
3. Deposit all collateral to lending protocol
4. Borrow USDC from protocol (using deposited collateral)
5. Repay flash loan

All 5 steps happen in one Sui [Programmable Transaction Block (PTB)](https://docs.sui.io/concepts/transactions/prog-txn-blocks). If step 5 fails, everything reverts.

> For more on why Sui's PTB model is ideal for this — see [DefiDash Journal Day 1](/p/defidash-technical-journal-day1/) where we compare PTB-based atomic leverage vs EVM Flash Loan patterns.

### Supply APY & Borrow APY

- **Supply APY**: What you earn by depositing assets. Composed of base interest + reward tokens (e.g., sSUI, DEEP).
- **Borrow APY**: What you pay for borrowing. Some protocols give borrowing incentives (rebates).
- **Net APY**: The leveraged return on your equity.

$$\text{Net APY} = \frac{\text{Total Position} \times \text{Supply APY} - \text{Debt} \times \text{Borrow APY}}{\text{Initial Equity}}$$

With 2x leverage: if supply APY > borrow APY, your returns are amplified. If not, you're paying more than you earn (negative Net APY).

> The interest rate models behind these APYs (JumpRateModel, utilization curves) are covered in [Lending Protocol Study Day 1](/p/lending-protocol-study-day1/) and [Day 2](/p/lending-protocol-study-day2/). Especially the Mantissa-based fixed-point arithmetic in Day 2 is directly relevant to how we parse on-chain rate data.

### Liquidation Price

The asset price at which your position hits the liquidation threshold:

$$\text{Liquidation Price} = \frac{\text{Total Debt}}{\text{Total Collateral Amount} \times \text{Liquidation Threshold}}$$

For a $100 SUI position at 2x leverage on Suilend (LT = 75%):
- Debt = $100, Total collateral = ~52.6 SUI (at $3.80)
- Liquidation Price = $100 / (52.6 × 0.75) ≈ $2.53
- That's a ~33% price drop buffer from current price

---

## How It's Built

### Architecture

```
previewLeverage(params)
  │
  ├─ 1. Resolve coin type ('SUI' → '0x2::sui::SUI')
  ├─ 2. Fetch risk params from protocol adapter
  │     └─ getAssetRiskParams(coinType) → { ltv, liquidationThreshold, maxMultiplier }
  ├─ 3. Validate multiplier ≤ maxMultiplier
  ├─ 4. Fetch current price from 7k Protocol aggregator
  │
  ├─ 5. Position calculation
  │     ├─ flashLoanUsdc = equity × (multiplier − 1) × 1.02 buffer
  │     ├─ totalPositionUsd = equity × multiplier
  │     └─ ltvPercent = debt / totalPosition × 100
  │
  ├─ 6. Liquidation calculation
  │     ├─ liquidationPrice = debt / (collateralAmount × LT)
  │     └─ priceDropBuffer = (1 − liqPrice / currentPrice) × 100
  │
  ├─ 7. APY calculation
  │     ├─ Supply APY: base + reward (per protocol adapter)
  │     ├─ Borrow APY: gross − rebate (per protocol adapter)
  │     └─ Net APY = (position × supplyAPY − debt × borrowAPY) / equity
  │
  └─ 8. Swap slippage estimation via 7k DEX aggregator quote
```

### Multi-Protocol Adapter Pattern

Each lending protocol (Suilend, Navi, Scallop) implements the `ILendingProtocol` interface, and the preview engine queries them through a unified API:

```typescript
interface ILendingProtocol {
  getAssetRiskParams(coinType: string): Promise<{
    ltv: number;
    liquidationThreshold: number;
    maxMultiplier: number;
  }>;
  getAssetApy(coinType: string): Promise<{
    supplyApy: number;
    rewardApy: number;
    borrowApy: number;
  }>;
  // ... deposit, borrow, withdraw, etc.
}
```

The same `previewLeverage` call works across all three protocols — just change the `protocol` parameter:

```typescript
// Compare leverage across protocols
for (const protocol of ['suilend', 'navi', 'scallop']) {
  const preview = await sdk.previewLeverage({
    protocol,
    depositAsset: 'SUI',
    depositValueUsd: 100,
    multiplier: 2.0,
  });
  console.log(`${protocol}: Net APY ${(preview.netApy * 100).toFixed(2)}%`);
}
```

> This adapter pattern follows the same principle as Aave V3's modular architecture — separation of concerns with a thin routing layer. The [Day 2 study](/p/lending-protocol-study-day2/) covers how Aave V3 uses `delegatecall + Library pattern` to achieve a similar pluggable design.

### Data Sources

| Data | Source | Notes |
|------|--------|-------|
| Asset price | 7k Protocol `getTokenPrice` | Real-time DEX aggregated price |
| LTV / LT | Protocol on-chain state | Suilend `RateLimiterConfig`, Navi `ReserveData`, Scallop `risk_models` |
| Supply/Borrow APY | Protocol SDK + on-chain query | Includes reward token APY |
| Flash loan fee | Scallop `FLASHLOAN_FEES_TABLE` | Currently 0% for USDC |
| Swap slippage | 7k Protocol `quote()` | Real-time DEX routing |

---

## Challenges & Bugs Fixed

### Reward APY showing 3700% instead of 1.46%

Suilend stores reward coin types without the `0x` prefix internally (e.g., `deeb7a4...::deep::DEEP`). When we passed this to the 7k price API, it returned 0. The fallback code then used the deposit asset's price ($67,987 for LBTC) as a proxy for the reward token (DEEP at $0.027), inflating the reward APY to 3700%.

Fix: normalize the coin type with `0x` prefix before price lookup, and skip the reward if price is still unavailable.

```typescript
// Before (broken)
const rewardPrice = await getTokenPrice(rewardCoinType); // returns 0
// Fallback: uses LBTC price → 3700% APY

// After (fixed)
const normalizedReward = normalizeCoinType(rewardCoinType);
const fetchedPrice = await getTokenPrice(normalizedReward);
if (fetchedPrice <= 0) continue; // skip this reward
```

### Scallop risk params not accessible via SDK

Scallop's TypeScript SDK doesn't expose `risk_models` data. We had to query the on-chain `risk_models` dynamic fields directly using `suiClient.getDynamicFieldObject()` to extract LTV and liquidation threshold values.

---

## Verified Results (2026-02-26, Mainnet)

### SUI 2x Leverage

| | Suilend | Navi | Scallop |
|---|---------|------|---------|
| Asset LTV | 70% | 75% | 85% |
| Liq. Threshold | 75% | 70% | 90% |
| Max Multiplier | 3.33x | 4.00x | 6.67x |
| Liq. Price | $0.63 | $0.68 | $0.53 |
| Price Drop Buffer | 33% | 29% | 44% |
| Supply APY | 2.89% | 2.97% | 2.98% |
| Borrow Net APY | 3.45% | 4.57% | 5.80% |
| **Net APY** | **2.33%** | **1.37%** | **0.15%** |

### XBTC 2x Leverage

| | Suilend | Navi | Scallop |
|---|---------|------|---------|
| Asset LTV | 60% | 67% | 75% |
| Supply APY | 3.78% | 6.73% | 0.00% |
| **Net APY** | **4.10%** | **8.88%** | **-5.80%** |

The negative Net APY on Scallop XBTC means borrowing costs exceed supply earnings — leverage actually loses money in that case.

---

## What's Next

- `leverage()` — Actually execute the leveraged position on-chain
- `deleverage()` — Close/reduce a leveraged position (flash loan → repay debt → withdraw → swap → repay)
- `previewDeleverage()` — Preview the unwinding process
- Cross-protocol position comparison dashboard

---

## Links

- [DefiDash SDK Repository](https://github.com/curg-13/defidash-sdk)
- [Lending Protocol Study Day 1](/p/lending-protocol-study-day1/) — Core lending concepts (LTV, Health Factor, Share-Based Accounting)
- [Lending Protocol Study Day 2](/p/lending-protocol-study-day2/) — Compound V2 internals, Aave V3 architecture
- [Sui PTB Documentation](https://docs.sui.io/concepts/transactions/prog-txn-blocks) — Programmable Transaction Blocks
- [Suilend](https://suilend.fi) | [Navi Protocol](https://naviprotocol.io) | [Scallop](https://scallop.io) — The three protocols supported

---

*DefiDash의 전체 코드는 [curg-13](https://github.com/curg-13) 조직에서 확인할 수 있다.*
