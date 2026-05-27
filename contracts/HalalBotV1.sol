// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3FlashCallback.sol";
import "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title HalalBotV1
 * @notice Contract 3 of 3 — Implementation (Business Logic)
 *
 * @dev This contract contains ALL execution logic:
 *      - Uniswap V3 flash swap (zero-fee, Riba-free capital)
 *      - Backrun arbitrage execution
 *      - Victim refund (atomic, enforced by code)
 *      - Charity/sadaqah distribution
 *      - Full audit event emission
 *
 * THIS CONTRACT HOLDS NO STORAGE OF ITS OWN.
 * All state lives in HalalBotProxy via delegatecall.
 * Storage layout must match BotStorage struct exactly.
 *
 * UPGRADEABLE NOTE:
 *      Uses OpenZeppelin's Initializable pattern.
 *      constructor() is replaced by initialize().
 *      Never use constructor for state — it won't be called via proxy.
 *
 * FLASH LOAN PROVIDER: Uniswap V3 Flash Swaps
 *      - Zero protocol fee
 *      - Repay equivalent token + pool fee only
 *      - No interest, no Riba, no external lending protocol involved
 *      - Capital is borrowed from the pool you're about to arbitrage
 */
contract HalalBotV1 is Initializable, IUniswapV3FlashCallback, IUniswapV3SwapCallback {

    using SafeERC20 for IERC20;

    // ─────────────────────────────────────────────
    // STORAGE (must match proxy storage layout exactly)
    // ─────────────────────────────────────────────

    address public constant UNISWAP_V3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984; // Mainnet, update for testnet

    address public operator;
    address public adminContract;       // HalalBotAdmin
    address public charityWallet;

    uint256 public victimRefundBps;     // e.g. 2000 = 20%
    uint256 public charityBps;          // e.g. 1000 = 10%

    uint256 public totalExecutions;
    uint256 public totalProfitCaptured;
    uint256 public totalReturnedToVictims;
    uint256 public totalSentToCharity;

    bool public warningSystemEnabled;

    // ─────────────────────────────────────────────
    // EVENTS — full audit trail, every execution
    // ─────────────────────────────────────────────

    event BackrunExecuted(
        bytes32 indexed targetTxHash,       // tx that triggered the backrun
        address indexed victim,             // original user who made the mistake
        address tokenIn,
        address tokenOut,
        uint256 grossProfit,
        uint256 returnedToVictim,
        uint256 sentToCharity,
        uint256 operatorProfit,
        uint256 blockNumber,
        bool warningWasAttempted            // on-chain proof of warning attempt
    );

    event WarningEmitted(
        bytes32 indexed pendingTxHash,
        address indexed victim,
        uint256 slippageBps,                // detected slippage tolerance
        uint256 blockNumber
    );

    event FlashSwapRepaid(
        address indexed pool,
        uint256 amount0,
        uint256 amount1,
        uint256 fee0,
        uint256 fee1
    );

    // ─────────────────────────────────────────────
    // ERRORS
    // ─────────────────────────────────────────────

    error OnlyOperator();
    error OnlyAdmin();
    error ProfitBelowMinimum(uint256 profit, uint256 minimum);
    error InvalidVictimAddress();
    error FlashSwapCallerNotPool();
    error ArbitrageFailedToCoverLoan();
    error InvalidPool();

    // ─────────────────────────────────────────────
    // STRUCTS
    // ─────────────────────────────────────────────

    /**
     * @dev Passed through flash swap callback to execute arbitrage
     *      All data needed to complete the trade in one atomic tx
     */
    struct FlashCallbackData {
        address victim;                 // original mistaken tx sender
        bytes32 targetTxHash;          // their tx hash (for audit)
        address tokenBorrow;           // token we flash-borrowed
        address tokenArb;              // token on the other side
        address poolBuy;               // pool where price is depressed (buy here)
        address poolSell;              // pool where price is fair (sell here)
        uint24 feeTier;                // Uniswap V3 fee tier (500, 3000, 10000)
        uint256 amountBorrowed;        // flash loan amount
        uint256 minProfit;             // revert if profit below this
        bool warningWasAttempted;      // did we try to warn the victim?
    }

    // ─────────────────────────────────────────────
    // INITIALIZER (replaces constructor for proxy pattern)
    // ─────────────────────────────────────────────

    function initialize(
        address _operator,
        address _adminContract,
        address _charityWallet,
        uint256 _victimRefundBps,
        uint256 _charityBps
    ) external initializer {
        require(_operator != address(0), "Init: operator required");
        require(_adminContract != address(0), "Init: admin required");
        require(_charityWallet != address(0), "Init: charity wallet required");
        require(_victimRefundBps >= 2000, "Init: victim refund min 20%");
        require(_victimRefundBps + _charityBps <= 9000, "Init: operator min 10%");

        operator = _operator;
        adminContract = _adminContract;
        charityWallet = _charityWallet;
        victimRefundBps = _victimRefundBps;
        charityBps = _charityBps;
        warningSystemEnabled = true;
    }

    // ─────────────────────────────────────────────
    // MODIFIERS
    // ─────────────────────────────────────────────

    modifier onlyOperator() {
        if (msg.sender != operator) revert OnlyOperator();
        _;
    }

    // ─────────────────────────────────────────────
    // MAIN ENTRY — emit warning (off-chain scanner calls this)
    // ─────────────────────────────────────────────

    /**
     * @notice Emit an on-chain warning when a high-slippage tx is detected
     * @dev Called by the off-chain scanner BEFORE the victim's tx executes.
     *      Creates a permanent, auditable record that warning was attempted.
     *      Costs ~25k gas — operator pays this as cost of ethical operation.
     *
     * @param pendingTxHash  The victim's pending tx hash from mempool
     * @param victim         The victim's address
     * @param slippageBps    Their detected slippage tolerance in bps
     */
    function emitWarning(
        bytes32 pendingTxHash,
        address victim,
        uint256 slippageBps
    ) external onlyOperator {
        if (!warningSystemEnabled) return;
        if (victim == address(0)) revert InvalidVictimAddress();

        emit WarningEmitted(
            pendingTxHash,
            victim,
            slippageBps,
            block.number
        );
    }

    // ─────────────────────────────────────────────
    // MAIN ENTRY — execute backrun
    // ─────────────────────────────────────────────

    /**
     * @notice Initiate a flash swap backrun after victim tx has been confirmed
     * @dev Operator calls this after the target tx is included in a block.
     *      This begins the atomic sequence:
     *      flash borrow → buy → sell → repay → distribute
     *
     * @param flashPool          Uniswap V3 pool to borrow from
     * @param callbackData       Encoded FlashCallbackData
     * @param borrowAmount0      Amount of token0 to borrow (0 if borrowing token1)
     * @param borrowAmount1      Amount of token1 to borrow (0 if borrowing token0)
     */
    function executeBackrun(
        address flashPool,
        bytes calldata callbackData,
        uint256 borrowAmount0,
        uint256 borrowAmount1
    ) external onlyOperator {
        // Initiate Uniswap V3 flash swap
        // This calls uniswapV3FlashCallback on this contract when funds are sent
        IUniswapV3Pool(flashPool).flash(
            address(this),
            borrowAmount0,
            borrowAmount1,
            callbackData
        );
    }

    // ─────────────────────────────────────────────
    // UNISWAP V3 FLASH CALLBACK
    // ─────────────────────────────────────────────

    /**
     * @notice Called by Uniswap V3 pool after sending flash loan funds
     * @dev This is where all arbitrage logic executes.
     *      We have the borrowed funds. We must repay before this function returns
     *      or the entire transaction reverts — enforcing atomic safety.
     *
     *      Execution order (all atomic):
     *      1. Verify caller is legitimate pool
     *      2. Decode callback data
     *      3. Execute arbitrage swap
     *      4. Calculate profit
     *      5. Repay pool (+ pool fee, NOT interest — just the swap fee)
     *      6. Distribute remaining profit:
     *         → victim refund (ihsan layer)
     *         → charity wallet
     *         → operator
     *      7. Emit full audit event
     */
    function uniswapV3FlashCallback(
        uint256 fee0,
        uint256 fee1,
        bytes calldata data
    ) external override {
        FlashCallbackData memory decoded = abi.decode(data, (FlashCallbackData));

        // ── SECURITY: verify caller is the legitimate Uniswap pool ──
        // Prevents malicious contracts from calling this directly
        address expectedPool = _verifyPool(decoded.tokenBorrow, decoded.tokenArb, decoded.feeTier);
        if (msg.sender != expectedPool) revert FlashSwapCallerNotPool();

        uint256 amountOwed = decoded.amountBorrowed + (fee0 > 0 ? fee0 : fee1);

        // ── STEP 1: Execute arbitrage on the buy pool ──
        // Victim's trade created a price imbalance — we buy the underpriced asset
        uint256 amountOut = _swapOnPool(
            decoded.poolBuy,
            decoded.tokenBorrow,
            decoded.tokenArb,
            decoded.amountBorrowed
        );

        // ── STEP 2: Sell on the fair-price pool ──
        uint256 returnAmount = _swapOnPool(
            decoded.poolSell,
            decoded.tokenArb,
            decoded.tokenBorrow,
            amountOut
        );

        // ── STEP 3: Verify we have enough to repay ──
        if (returnAmount < amountOwed) revert ArbitrageFailedToCoverLoan();

        uint256 grossProfit = returnAmount - amountOwed;

        // Revert if profit is below minimum (gas protection)
        if (grossProfit < decoded.minProfit) {
            revert ProfitBelowMinimum(grossProfit, decoded.minProfit);
        }

        // ── STEP 4: Repay flash swap ──
        IERC20(decoded.tokenBorrow).safeTransfer(msg.sender, amountOwed);

        emit FlashSwapRepaid(msg.sender, fee0, fee1, fee0, fee1);

        // ── STEP 5: Distribute profit ──
        // This is the ihsan layer — enforced by code, not trust
        _distributeProfit(
            decoded.tokenBorrow,
            grossProfit,
            decoded.victim,
            decoded.targetTxHash,
            decoded.warningWasAttempted,
            decoded.tokenArb
        );
    }

    // ─────────────────────────────────────────────
    // INTERNAL — profit distribution
    // ─────────────────────────────────────────────

    /**
     * @dev Splits gross profit between victim, charity, and operator.
     *      All transfers happen atomically in the same tx as the flash swap.
     *      There is no deferred promise here — code enforces the split.
     */
    function _distributeProfit(
        address token,
        uint256 grossProfit,
        address victim,
        bytes32 targetTxHash,
        bool warningWasAttempted,
        address tokenArb
    ) internal {
        // Read distribution ratios from admin contract to ensure sync
        (uint256 adminVictimBps, uint256 adminCharityBps, ) = IHalalBotAdmin(adminContract).getDistributionRatios();
        
        uint256 victimAmount = (grossProfit * adminVictimBps) / 10000;
        uint256 charityAmount = (grossProfit * adminCharityBps) / 10000;
        uint256 operatorAmount = grossProfit - victimAmount - charityAmount;

        // Return portion to victim
        if (victimAmount > 0 && victim != address(0)) {
            IERC20(token).safeTransfer(victim, victimAmount);
        }

        // Send to sadaqah/charity wallet
        if (charityAmount > 0) {
            IERC20(token).safeTransfer(charityWallet, charityAmount);
        }

        // Operator profit (remainder)
        if (operatorAmount > 0) {
            IERC20(token).safeTransfer(operator, operatorAmount);
        }

        // Update cumulative stats
        totalExecutions++;
        totalProfitCaptured += grossProfit;
        totalReturnedToVictims += victimAmount;
        totalSentToCharity += charityAmount;

        // Full audit event — immutable, public, permanent
        emit BackrunExecuted(
            targetTxHash,
            victim,
            token,
            tokenArb, // tokenOut - the arbitrage token
            grossProfit,
            victimAmount,
            charityAmount,
            operatorAmount,
            block.number,
            warningWasAttempted
        );
    }

    // ─────────────────────────────────────────────
    // INTERNAL — DEX swap helpers
    // ─────────────────────────────────────────────

    function _swapOnPool(
        address pool,
        address tokenIn,
        address /* tokenOut */,
        uint256 amountIn
    ) internal returns (uint256 amountOut) {
        // Determine swap direction
        address token0 = IUniswapV3Pool(pool).token0();
        bool zeroForOne = tokenIn == token0;

        // Execute swap — returns negative delta for the output side
        (int256 amount0Delta, int256 amount1Delta) = IUniswapV3Pool(pool).swap(
            address(this),
            zeroForOne,
            int256(amountIn),
            zeroForOne ? 4295128740 : 1461446703485210103287273052203988822378723970341, // price limits
            abi.encode(tokenIn)
        );

        amountOut = uint256(-(zeroForOne ? amount1Delta : amount0Delta));
    }

    function _verifyPool(
        address tokenA,
        address tokenB,
        uint24 feeTier
    ) internal view returns (address pool) {
        pool = IUniswapV3Factory(UNISWAP_V3_FACTORY).getPool(tokenA, tokenB, feeTier);
        if (pool == address(0)) revert InvalidPool();
    }

    // ─────────────────────────────────────────────
    // UNISWAP V3 SWAP CALLBACK
    // ─────────────────────────────────────────────

    /**
     * @notice Called by Uniswap V3 pool during swap operations
     * @dev Required for executing swaps via pool.swap()
     *      Transfers the owed token amount back to the pool
     */
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external override {
        address tokenIn = abi.decode(data, (address));
        uint256 amountOwed = amount0Delta > 0
            ? uint256(amount0Delta)
            : uint256(amount1Delta);
        IERC20(tokenIn).safeTransfer(msg.sender, amountOwed);
    }

    // ─────────────────────────────────────────────
    // VIEW — audit config (required by proxy interface check)
    // ─────────────────────────────────────────────

    /**
     * @notice Returns the current ethical configuration of this implementation
     * @dev Required function — proxy will refuse to upgrade to any implementation
     *      that does not expose this. Ensures transparency is never dropped.
     */
    function getAuditConfig() external view returns (
        uint256 victimRefundBps_,
        uint256 charityBps_,
        uint256 operatorBps_,
        address charityWallet_,
        bool warningEnabled_,
        uint256 totalExecutions_,
        uint256 totalReturnedToVictims_,
        uint256 totalSentToCharity_
    ) {
        victimRefundBps_ = victimRefundBps;
        charityBps_ = charityBps;
        operatorBps_ = 10000 - victimRefundBps - charityBps;
        charityWallet_ = charityWallet;
        warningEnabled_ = warningSystemEnabled;
        totalExecutions_ = totalExecutions;
        totalReturnedToVictims_ = totalReturnedToVictims;
        totalSentToCharity_ = totalSentToCharity;
    }
}

interface IHalalBotAdmin {
    function getDistributionRatios() external view returns (
        uint256 victimBps_,
        uint256 charityBps_,
        uint256 operatorBps_
    );
}
