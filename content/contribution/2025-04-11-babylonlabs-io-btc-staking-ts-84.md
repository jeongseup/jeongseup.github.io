---
title: "[Babylon] Hotfix: Update Slashing Amount Calculation"
date: 2025-04-11
slug: "babylonlabs-io-btc-staking-ts-84"
categories:
    - "Open Source"
tags:
    - "Babylon"
    - "TypeScript"
externalUrl: "https://github.com/babylonlabs-io/btc-staking-ts/pull/84"
---

### Hotfix Description

Addressed a critical bug in the slashing amount calculation logic within the JavaScript library.
The fix corrects the precision issue where `Math.floor` was used incorrectly to compute penalty amounts, ensuring accurate slashing calculations.

[View on GitHub](https://github.com/babylonlabs-io/btc-staking-ts/pull/84)
