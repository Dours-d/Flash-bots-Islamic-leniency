# Three-Contract Proxy Architecture

## Halal Hybrid Protection + Profit Bot

-----

## Why Three Contracts?

A single monolithic contract cannot be upgraded without redeployment —
losing all accumulated state, history, and the address your users trust.
The three-contract proxy pattern separates three distinct concerns:

```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│   Contract 1           Contract 2           Contract 3      │
│   HalalBotAdmin   →    HalalBotProxy   ←→   HalalBotV1      │
│                                                             │
│   WHO can change       WHERE state lives    WHAT logic runs  │
│   the system           (permanent address)  (upgradeable)    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

-----

## Contract Roles

### Contract 1 — HalalBotAdmin.sol

**The gatekeeper. Controls who can upgrade and what parameters are allowed.**

- Owns upgrade authority over the Proxy
- Enforces the 20% minimum victim refund (code-level, cannot be bypassed)
- Timelocks all upgrades (50 blocks minimum before execution)
- Requires a human-readable reason for every upgrade (on-chain transparency)
- Uses Ownable2Step — two-step ownership transfer prevents accidents
- All parameter changes emit events permanently

**Key guarantee:** No single transaction can upgrade the system.
Propose → wait → execute. The timelock is your ethical buffer.

-----

### Contract 2 — HalalBotProxy.sol

**The permanent address. Stores all state. Never contains logic.**

- This is the address you publish and never change
- Delegates all calls to current Implementation via `delegatecall`
- Holds persistent storage: profits, victim refunds, execution counts
- Uses EIP-1967 storage slots (prevents storage collisions on upgrade)
- Emergency pause function — stops execution if something goes wrong
- Verifies new implementations expose `getAuditConfig()` before accepting upgrade
  (cannot be upgraded to a contract that drops the transparency layer)

**Key guarantee:** The proxy refuses upgrades to non-compliant implementations.
The ethical interface is structurally enforced.

-----

### Contract 3 — HalalBotV1.sol

**All business logic. Replaceable without changing the address users interact with.**

- Uniswap V3 flash swap execution (zero-fee, Riba-free)
- Backrun arbitrage logic
- Atomic victim refund (same transaction — no promises, code enforces it)
- Charity distribution
- Full audit event emission on every execution
- `getAuditConfig()` — required function, publicly readable ethical state

**Key guarantee:** Can be upgraded to V2, V3, etc. as DEX integrations evolve,
without losing history or changing the trusted proxy address.

-----

## Upgrade Flow

```
Developer identifies needed change
         ↓
HalalBotAdmin.proposeUpgrade(proxy, newImpl, "reason")
         ↓
Wait 50+ blocks (timelock period — ~10 min on Arbitrum)
         ↓
HalalBotAdmin.executeUpgrade(proxy)
         ↓
Proxy.upgradeTo(newImpl) — verifies getAuditConfig() exists
         ↓
ImplementationUpgraded event emitted (reason stored on-chain)
         ↓
All future calls now delegate to new implementation
All historical state preserved in proxy storage
```

-----

## Flash Loan Provider — Why Uniswap V3

```
Uniswap V3 Flash Swaps vs Aave Flash Loans:
───────────────────────────────────────────
Uniswap V3:  Borrow from pool → repay same token + pool fee
             Pool fee = 0.05% / 0.3% / 1% (swap fee, not interest)
             This is ujrah — a fee for using the service/pool
             No external lending protocol involved
             Capital comes from the liquidity pool you arbitrage

Aave:        Borrow from lending pool → repay + 0.09% premium
             Premium on a monetary loan = structural Riba
             ❌ Do not use
```

-----

## Deployment Order

```bash
# 1. Deploy Admin (with charity wallet address)
HalalBotAdmin admin = new HalalBotAdmin(charityWalletAddress);

# 2. Deploy Implementation (no constructor state)
HalalBotV1 impl = new HalalBotV1();

# 3. Encode initializer call
bytes memory initData = abi.encodeWithSignature(
    "initialize(address,address,address,uint256,uint256)",
    operatorAddress,
    address(admin),
    charityWalletAddress,
    2000,   // 20% victim refund
    1000    // 10% charity
);

# 4. Deploy Proxy (links to impl + admin, calls initializer)
HalalBotProxy proxy = new HalalBotProxy(
    address(impl),
    address(admin),
    initData
);

# 5. Verify on Etherscan/Arbiscan
# All three contracts should be source-verified and publicly readable
```

-----

## Storage Layout Rules (Critical for Upgrades)

When writing HalalBotV2, V3, etc. — **never reorder or remove existing
storage variables**. Only append new ones at the end.

```
Slot 0: operator
Slot 1: adminContract
Slot 2: charityWallet
Slot 3: victimRefundBps
Slot 4: charityBps
Slot 5: totalExecutions
Slot 6: totalProfitCaptured
Slot 7: totalReturnedToVictims
Slot 8: totalSentToCharity
Slot 9: warningSystemEnabled
Slot 10+: NEW variables only — never touch above
```

-----

## What This Architecture Proves

Every execution of this system leaves a permanent, public, on-chain record:

- Which pending tx triggered the detection
- Whether a warning was emitted before execution
- Gross profit captured
- Exactly how much went to the victim
- Exactly how much went to charity
- Exactly how much the operator kept
- That no frontrunning occurred (block ordering is verifiable)

This is not just code — it is a transparent, auditable proof of intent.
