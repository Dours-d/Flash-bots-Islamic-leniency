# Halal Flash Loan Bot

Islamic finance-compliant flash loan bot using a three-contract proxy architecture for backrunning high-slippage transactions on Arbitrum/Base.

## Architecture

**Three-Contract Proxy Pattern:**

1. **HalalBotAdmin** - Controls upgrade authority, enforces minimum 20% victim refund, timelocks upgrades
2. **HalalBotProxy** - Permanent address that stores all state, delegates calls to implementation
3. **HalalBotV1** - Business logic (flash swaps, arbitrage, profit distribution)

## Profit Distribution

- **80% operator** - Your profit share
- **20% victim refund** - Returned atomically to original user
- **0% charity** - You manage charities separately

## Islamic Compliance

- No frontrunning (bot only acts AFTER target transaction is included)
- No Riba-bearing providers (Uniswap V3 flash swaps only - zero fee)
- No oracle manipulation (exploits only naturally occurring price differences)
- Mandatory victim refund (20% enforced by code)
- Full transparency (all events emitted on-chain)

## Setup

1. Install dependencies:
```bash
npm install
```

2. Configure environment variables:
```bash
cp .env.example .env
# Edit .env with your private key and RPC URLs
```

3. Compile contracts:
```bash
npx hardhat compile
```

## Deployment

### Testnet (Arbitrum Sepolia)

```bash
npx hardhat run scripts/deploy.ts --network arbitrumSepolia
```

### Mainnet (Arbitrum)

```bash
npx hardhat run scripts/deploy.ts --network arbitrum
```

## Configuration

**Admin Contract:**
- MIN_VICTIM_REFUND_BPS: 2000 (20% minimum, enforced by code)
- victimRefundBps: 2000 (20% - configurable, cannot go below minimum)
- charityBps: 0 (0% - you manage charities separately)
- upgradeTimelockBlocks: 50 (~10 minutes on Arbitrum)

**V1 Implementation:**
- warningSystemEnabled: true
- Slippage threshold: 15% (off-chain scanner config)
- Minimum trade size: $1000 USD (off-chain scanner config)
- Warning delay: 1-2 blocks (off-chain scanner config)

## Testing

```bash
npx hardhat test
```

## Security

- Emergency pause mechanism in Proxy contract
- Upgrade timelock (50 blocks minimum)
- Admin enforces minimum 20% victim refund
- Proxy verifies new implementations expose getAuditConfig()
- All state in proxy, implementation is replaceable

## Audit Trail

Every execution emits:
- Target tx hash that triggered the backrun
- Block number of detection vs execution
- Whether warning was attempted
- Gross profit captured
- Amount returned to victim
- Amount sent to charity (0 in our case)
- Operator profit
- Flash loan provider used

## Storage Layout

Critical for upgrades - never reorder or remove existing storage variables:

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
Slot 10+: NEW variables only
```

## License

MIT
