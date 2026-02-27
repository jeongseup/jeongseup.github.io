---
title: "Seal Protocol: Sui 위의 탈중앙화 비밀 관리(DSM) 프로토콜 분석"
date: 2026-02-27
draft: false
authors: ["Jeongseup"]
description: "Sui 블록체인의 접근 제어를 활용한 탈중앙화 키 관리 프로토콜 Seal의 아키텍처, IBE·Threshold Cryptography 기반 동작 원리, 그리고 코드 레벨 분석."
slug: seal-protocol-study
tags: ["Sui", "Cryptography", "Seal", "IBE", "Walrus"]
categories: []
math: true
---

> Seal은 Sui 블록체인의 접근 제어(Access Control) 기능을 활용하여 데이터를 안전하게 암호화·복호화하는 **탈중앙화 키 관리 프로토콜**이다. Walrus와 같은 분산 스토리지나 온체인/오프체인 스토리지에 저장된 민감한 데이터를 보호하기 위해 설계되었으며, 중앙화된 키 저장소 없이 **수학적 파생(Derivation)**과 **Threshold Cryptography**로 보안을 유지한다.

---

## 1. 핵심 아키텍처

Seal은 데이터를 지키는 것이 아니라, 데이터를 잠근 **열쇠(AES Key)**를 지키는 역할을 수행한다.

### 하이브리드 암호화 모델 (Envelope Encryption)

Seal은 대용량 데이터 처리를 위해 **봉투 암호화(Envelope Encryption)** 방식을 채택했다.

- **데이터 암호화**: 빠르고 강력한 **AES-256(대칭키)** 알고리즘으로 실제 데이터를 암호화한다. 키는 매번 랜덤 생성된다.
- **키 암호화**: 생성된 AES Key를 Seal 프로토콜(IBE)을 통해 암호화하여 데이터 옆에 붙여둔다.

비유하자면, Seal은 금고(데이터)를 직접 지키는 게 아니라 **금고 열쇠(AES Key)를 지키는 경비원**이다.

### Stateless Key Server

Seal의 Key Server는 AWS KMS와 달리 사용자 키를 DB에 저장하지 않는다.

- **Master Key Only**: 서버는 오직 자신의 **Master Key Pair** 하나만 관리한다.
- **Key Derivation**: 복호화 요청이 오면 `Master Key + User ID`를 결합하여 사용자용 키를 **즉석에서 계산(Derive)**한다.

유저가 수백만 명으로 늘어나도 서버의 DB 용량은 증가하지 않으며, 해킹을 당해도 특정 유저의 키가 저장되어 있지 않아 상대적으로 안전하다.

---

## 2. 기술적 배경

### IBE (Identity-Based Encryption)

기존 PKI(인증서 방식)와 달리, **사용자의 신원(ID String, 이메일 등)** 그 자체를 **Public Key**로 사용하는 암호화 방식이다. 복잡한 인증서 발급·관리 절차가 필요 없으며, ID만 알면 누구나 데이터를 암호화해서 보낼 수 있다.

### Threshold Cryptography

단일 서버 실패(SPOF)를 방지하기 위해 비밀을 $n$개의 조각(Share)으로 나눈다. $n$개의 서버 중 **$t$개 이상**이 살아있고 승인해야만 원본 키를 복구할 수 있다. 예를 들어, 3개 서버 중 2개 승인 시 복호화가 가능하다. 이를 통해 고가용성(Liveness)과 보안성(Privacy)을 동시에 보장한다.

---

## 3. 작동 플로우

모든 암호화 및 복호화 연산은 **Client-Side(사용자 환경)**에서 이루어진다.

### 1단계: 수집 (Collection)

사용자는 복호화를 위해 분산된 Key Server들에게 접근 권한을 증명한다.

- Client → Server A: "나 권한 있어(Proof)" → **키 조각 A** 획득
- Client → Server B: "나 권한 있어(Proof)" → **키 조각 B** 획득
- Server C가 응답하지 않아도 Threshold가 충족되면 진행 가능

### 2단계: 재조립 (Reconstruction)

클라이언트는 로컬 메모리 상에서 수집한 조각들을 합친다.

**라그랑주 보간법(Lagrange Interpolation)** 등 수학 공식을 통해 `[조각 A + 조각 B]`를 결합하고, 그 결과로 데이터를 잠갔던 **원본 대칭키(AES Key)**가 복구된다.

### 3단계: 해제 (Decryption)

복구된 AES Key를 사용하여 암호화된 객체(Encrypted Object)를 풀고, 최종적으로 원본 데이터(Plaintext)를 획득한다.

---

## 4. AWS KMS vs Seal 비교

| 특징 | AWS KMS (저장소 모델) | Seal (파생 모델) |
|------|----------------------|-----------------|
| **키 관리 방식** | Stateful — 키를 DB/HSM에 영구 저장 | Stateless — 유저 키를 저장하지 않음 |
| **스토리지 부담** | 유저/앱이 늘어날수록 관리할 키 데이터 증가 | 유저가 늘어나도 **Master Key 1개**만 관리 |
| **보안 리스크** | 저장소가 털리면 저장된 모든 키 유출 위험 | 저장소를 털어도 유저 키 데이터가 없음 |
| **백업/복구** | 모든 개별 키(CMK, DEK)를 백업해야 함 | Master Key 하나만 백업하면 모든 유저 키 복구 가능 |
| **작동 원리** | Key Lookup (DB 조회) | Key Derivation (수학적 계산) |

---

## 5. Seal 내부 구조: 두 가지 핵심 컴포넌트

Seal은 크게 두 가지 컴포넌트로 구성된다.

### Access Policies (On-chain, Sui)

Move 패키지(`PkgId`)가 IBE identity의 subdomain `[PkgId]*`를 제어한다. 패키지가 Move 코드를 통해 누가 해당 identity subdomain의 키에 접근할 수 있는지를 정의한다.

### Off-chain Key Servers

각 Key Server는 단일 IBE Master Secret Key를 보유한다. 사용자가 특정 identity에 대한 파생 키를 요청하면, 온체인 접근 정책이 승인한 경우에만 파생 키를 반환한다.

---

## 6. 코드 레벨 분석

### Encryption 과정

사용자 측에서 Seal Client SDK를 통해 데이터를 암호화하는 과정이다.

```typescript
const mysecret = "mysupersecret";
const encoder = new TextEncoder();
const mysecretBz = encoder.encode(mysecret);

const { encryptedObject, key } = await sealClient.encrypt({
  threshold: 1,
  packageId: PACKAGE_ID,
  id: "0000",
  data: mysecretBz,
});
```

### encrypt 내부 로직

SDK 내부에서는 다음 과정을 거친다.

1. **랜덤 Base Key 생성**: `encryptionInput.generateKey()`로 AES-256 키를 랜덤 생성
2. **키 분할**: `split(baseKey, threshold, keyServers.length)`로 Shamir Secret Sharing 수행
3. **Share 암호화**: 각 Key Server의 Public Key로 개별 Share를 IBE 암호화
4. **DEM Key 파생**: Base Key + 암호화된 Share 정보로 실제 데이터 암호화용 키를 파생
5. **데이터 암호화**: 파생된 DEM Key로 원본 데이터를 AES-GCM 암호화
6. **직렬화**: 모든 메타데이터와 ciphertext를 BCS 포맷으로 직렬화하여 반환

```typescript
// 핵심 흐름 요약
const baseKey = await encryptionInput.generateKey();
const shares = split(baseKey, threshold, keyServers.length);
const encryptedShares = encryptBatched(keyServers, kemType, fullId, shares, baseKey, threshold);
const demKey = deriveKey(KeyPurpose.DEM, baseKey, encryptedShares, threshold, serverIds);
const ciphertext = await encryptionInput.encrypt(demKey);
```

---

## 7. Limitations

`seal_approve*` 함수는 풀 노드에서 `dry_run_transaction_block` RPC 호출을 통해 평가된다. 풀 노드는 비동기적으로 동작하기 때문에 다음 사항에 유의해야 한다.

- 온체인 상태 변경이 전파되는 데 시간이 걸릴 수 있어, 풀 노드가 항상 최신 상태를 반영하지는 않는다.
- `seal_approve*` 함수는 모든 Key Server에 걸쳐 원자적으로 평가되지 않는다. 자주 변경되는 상태에 의존하여 접근 권한을 결정하면 안 된다.
- `seal_approve*` 함수는 side-effect가 없어야 하며, 온체인 상태를 수정할 수 없다.
- `Random` 모듈은 사용 가능하지만, 풀 노드 간에 결정적이지 않으므로 `seal_approve*` 함수 내에서 사용하면 안 된다.

---

## 8. 결론

Seal은 메시지를 encrypt & decrypt 해주는 프로토콜이다. IBE(Identity-Based Encryption)에 기초해서 동작하며, 이 모델이 서비스되기 위해 필요한 핵심 컴포넌트는 Key Server다.

Key Server들은 Master Key를 보유하고, 클라이언트의 ID를 바탕으로 파생 키를 만든다(이 형태가 IBE). 다만 Seal에서는 실제 고용량 데이터를 직접 IBE로 암호화하지 않고, 매번 랜덤하게 새로운 AES Key를 생성한 뒤 이 키를 각 Key Server들이 나눠 갖는 형태(Envelope Encryption + Secret Sharing)로 운영된다.

**Sui 블록체인**을 접근 제어 레이어로, **IBE**와 **Threshold Cryptography**를 키 관리 레이어로 사용하는 Stateless 아키텍처를 통해 보안성과 확장성을 동시에 달성한 프로토콜이다.

---

## References

- [Seal Official](https://seal.mystenlabs.com/)
- [Seal Documentation](https://seal-docs.wal.app/)
- [Only Fins (Demo App)](https://only-fins.wal.app/)
- [Identity-Based Encryption — Wikipedia](https://en.wikipedia.org/wiki/Identity-based_encryption)
- [MystenLabs/ts-sdks — Seal Package](https://github.com/MystenLabs/ts-sdks/tree/main/packages/seal)
