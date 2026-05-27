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
 * @title HalalBotV1 — v1.1
 * @notice Contract 3 of 3 — Implementation (Business Logic)
 *
 * @dev This contract contains ALL execution logic:
 *      - Uniswap V3 flash swap (zero-fee, Riba-free capital)
 *      - Backrun arbitrage execution
 *      - Victim refund via pull pattern (no blocked txs)
 *      - Charity/sadaqah distribution
 *      - Full audit event emission
 *      - Operator and charity wallet rotation
 *      - Stuck token and ETH recovery
 *      - Direct ETH withdrawal for operator
 *
 * STORAGE LAYOUT (append-only — never reorder):
 *      Slot 0:  UNISWAP_V3_FACTORY
 *      Slot 1:  _activeSwapPool
 *      Slot 2:  operator
 *      Slot 3:  adminContract
 *      Slot 4:  charityWallet
 *      Slot 5:  victimRefundBps
 *      Slot 6:  charityBps
 *      Slot 7:  totalExecutions
 *      Slot 8:  totalProfitCaptured
 *      Slot 9:  totalReturnedToVictims
 *      Slot 10: totalSentToCharity
 *      Slot 11: warningSystemEnabled
 *      Slot 12: unclaimedRefunds  (mapping — v1.1)
 *      Slot 13+: V2 additions only
 */
contract HalalBotV1 is Initializable, IUniswapV3FlashCallback, IUniswapV3SwapCallback {

    using SafeERC20 for IERC20;

    // ─────────────────────────────────────────────
    // STORAGE
    // ─────────────────────────────────────────────

    address public  UNISWAP_V3_FACTORY;
    address private _activeSwapPool;        // transient lock for swap callback

    address public operator;
    address public adminContract;
    address public charityWallet;

    uint256 public victimRefundBps;
    uint256 public charityBps;

    uint256 public totalExecutions;
    uint256 public totalProfitCaptured;
    uint256 public totalReturnedToVictims;
    uint256 public totalSentToCharity;

    bool public warningSystemEnabled;

    /// @dev Pull pattern: victim claims their refund themselves.
    ///      Prevents a bad victim address from blocking the entire tx.
    ///      victim address => token address => claimable amount
    mapping(address => mapping(address => uint256)) public unclaimedRefunds;

    // ─────────────────────────────────────────────
    // SQRT PRICE CONSTANTS (Uniswap V3)
    // ─────────────────────────────────────────────

    uint160 internal constant MIN_SQRT_RATIO = 4295128739;
    uint160 internal constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;

    // ─────────────────────────────────────────────
    // EVENTS
    // ─────────────────────────────────────────────

    event BackrunExecuted(
        bytes32 indexed targetTxHash,
        address indexed victim,
        address tokenIn,
        address tokenOut,
        uint256 grossProfit,
        uint256 returnedToVictim,
        uint256 sentToCharity,
        uint256 operatorProfit,
        uint256 blockNumber,
        bool    warningWasAttempted
    );

    event WarningEmitted(
        bytes32 indexed pendingTxHash,
        address indexed victim,
        uint256 slippageBps,
        uint256 blockNumber
    );

    event FlashSwapRepaid(
        address indexed pool,
        uint256 fee0,
        uint256 fee1
    );

    event RefundAvailable(
        address indexed victim,
        address indexed token,
        uint256 amount
    );

    event RefundClaimed(
        address indexed victim,
        address indexed token,
        uint256 amount
    );

    event OperatorUpdated(
        address indexed oldOperator,
        address indexed newOperator
    );

    event CharityWalletUpdated(
        address indexed oldWallet,
        address indexed newWallet
    );

    event EmergencyWithdrawal(
        address indexed token,
        address indexed recipient,
        uint256 amount,
        string  reason
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
    error InvalidSwapCaller();
    error InvalidArbPool();
    error InvalidRecipient();
    error ZeroAmount();
    error ETHTransferFailed();
    error NoRefundAvailable();

    // ─────────────────────────────────────────────
    // STRUCTS
    // ─────────────────────────────────────────────

    struct FlashCallbackData {
        address  victim;
        bytes32  targetTxHash;
        address  tokenBorrow;
        address  tokenArb;
        address  poolBuy;
        address  poolSell;
        uint24   feeTier;
        uint256  amountBorrowed;
        uint256  minProfit;
        bool     warningWasAttempted;
    }

    // ─────────────────────────────────────────────
    // INITIALIZER
    // ─────────────────────────────────────────────

    function initialize(
        address _operator,
        address _adminContract,
        address _charityWallet,
        uint256 _victimRefundBps,
        uint256 _charityBps,
        address _uniswapV3Factory
    ) external initializer {
        require(_operator        != address(0), "Init: operator required");
        require(_adminContract   != address(0), "Init: admin required");
        require(_charityWallet   != address(0), "Init: charity wallet required");
        require(_uniswapV3Factory != address(0), "Init: factory required");
        require(_victimRefundBps >= 2000,        "Init: victim refund min 20%");
        require(_victimRefundBps + _charityBps <= 9000, "Init: operator min 10%");

        UNISWAP_V3_FACTORY  = _uniswapV3Factory;
        operator            = _operator;
        adminContract       = _adminContract;
        charityWallet       = _charityWallet;
        victimRefundBps     = _victimRefundBps;
        charityBps          = _charityBps;
        warningSystemEnabled = true;
    }

    // ─────────────────────────────────────────────
    // MODIFIERS
    // ─────────────────────────────────────────────

    modifier onlyOperator() {
        if (msg.sender != operator) revert OnlyOperator();
        _;
    }

    modifier onlyAdmin() {
        if (msg.sender != adminContract) revert OnlyAdmin();
        _;
    }

    // ─────────────────────────────────────────────
    // OPERATOR MANAGEMENT
    // ─────────────────────────────────────────────

    /**
     * @notice Rotate the operator wallet
     * @dev Only callable by admin contract (which enforces its own timelock).
     *      Immediately re-routes all future profit distributions.
     */
    function updateOperator(address newOperator) external onlyAdmin {
        require(newOperator != address(0), "Operator: invalid address");
        emit OperatorUpdated(operator, newOperator);
        operator = newOperator;
    }

    /**
     * @notice Rotate the charity/sadaqah wallet
     * @dev Only callable by admin contract.
     */
    function updateCharityWallet(address newWallet) external onlyAdmin {
        require(newWallet != address(0), "Charity: invalid address");
        emit CharityWalletUpdated(charityWallet, newWallet);
        charityWallet = newWallet;
    }

    // ─────────────────────────────────────────────
    // WITHDRAWAL — operator direct ETH
    // ─────────────────────────────────────────────

    /**
     * @notice Operator withdraws any ETH held by this contract
     * @dev Operator calls directly — no admin timelock needed for their own funds.
     *      ETH accumulates only from accidental direct transfers to the proxy.
     *      Normal operation (ERC20 arbitrage) never leaves ETH here.
     */
    function withdrawETH() external onlyOperator {
        uint256 balance = address(this).balance;
        if (balance == 0) revert ZeroAmount();

        (bool success, ) = payable(operator).call{value: balance}("");
        if (!success) revert ETHTransferFailed();

        emit EmergencyWithdrawal(address(0), operator, balance, "Operator ETH withdrawal");
    }

    // ─────────────────────────────────────────────
    // WITHDRAWAL — stuck tokens (admin-gated)
    // ─────────────────────────────────────────────

    /**
     * @notice Recover ERC20 tokens stuck in the contract
     * @dev Only callable by admin contract, which restricts recipient
     *      to operator or charity wallet. Reason is required and stored
     *      permanently on-chain via the WithdrawalAuthorised event in admin.
     */
    function withdrawStuckTokens(
        address token,
        address recipient,
        uint256 amount,
        string calldata reason
    ) external onlyAdmin {
        if (amount == 0) revert ZeroAmount();
        if (bytes(reason).length == 0) revert InvalidRecipient();

        // Recipient validation is enforced by HalalBotAdmin.authoriseTokenWithdrawal()
        // but we double-check here as defence-in-depth
        require(
            recipient == operator || recipient == charityWallet,
            "Withdraw: recipient must be operator or charity wallet"
        );

        IERC20(token).safeTransfer(recipient, amount);
        emit EmergencyWithdrawal(token, recipient, amount, reason);
    }

    /**
     * @notice Recover stuck ETH via admin (alternative to operator self-withdrawal)
     * @dev Admin routes ETH only to current operator address
     */
    function withdrawStuckETH(
        address payable recipient,
        string calldata reason
    ) external onlyAdmin {
        require(recipient == operator, "Withdraw: ETH only to operator");
        uint256 balance = address(this).balance;
        if (balance == 0) revert ZeroAmount();

        (bool success, ) = recipient.call{value: balance}("");
        if (!success) revert ETHTransferFailed();

        emit EmergencyWithdrawal(address(0), recipient, balance, reason);
    }

    // ─────────────────────────────────────────────
    // VICTIM REFUND — pull pattern
    // ─────────────────────────────────────────────

    /**
     * @notice Victim claims their partial refund
     * @dev Uses pull pattern — victim calls this themselves.
     *      This prevents a victim's bad/contract address from
     *      blocking the entire backrun execution.
     */
    function claimRefund(address token) external {
        uint256 amount = unclaimedRefunds[msg.sender][token];
        if (amount == 0) revert NoRefundAvailable();

        unclaimedRefunds[msg.sender][token] = 0;
        totalReturnedToVictims += amount;

        IERC20(token).safeTransfer(msg.sender, amount);
        emit RefundClaimed(msg.sender, token, amount);
    }

    /**
     * @notice Check claimable refund balance for a victim
     */
    function claimableRefund(
        address victim,
        address token
    ) external view returns (uint256) {
        return unclaimedRefunds[victim][token];
    }

    // ─────────────────────────────────────────────
    // WARNING EMISSION
    // ─────────────────────────────────────────────

    function emitWarning(
        bytes32 pendingTxHash,
        address victim,
        uint256 slippageBps
    ) external onlyOperator {
        if (!warningSystemEnabled) return;
        if (victim == address(0)) revert InvalidVictimAddress();

        emit WarningEmitted(pendingTxHash, victim, slippageBps, block.number);
    }

    // ─────────────────────────────────────────────
    // BACKRUN ENTRY
    // ─────────────────────────────────────────────

    function executeBackrun(
        address flashPool,
        bytes calldata callbackData,
        uint256 borrowAmount0,
        uint256 borrowAmount1
    ) external onlyOperator {
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

    function uniswapV3FlashCallback(
        uint256 fee0,
        uint256 fee1,
        bytes calldata data
    ) external override {
        FlashCallbackData memory decoded = abi.decode(data, (FlashCallbackData));

        // Verify caller is the legitimate Uniswap pool
        address expectedPool = _verifyPool(decoded.tokenBorrow, decoded.tokenArb, decoded.feeTier);
        if (msg.sender != expectedPool) revert FlashSwapCallerNotPool();

        uint256 amountOwed = decoded.amountBorrowed + (fee0 > 0 ? fee0 : fee1);

        // Step 1: Buy underpriced asset on affected pool
        _requireLegitPool(decoded.poolBuy);
        uint256 amountOut = _swapOnPool(
            decoded.poolBuy,
            decoded.tokenBorrow,
            decoded.amountBorrowed
        );

        // Step 2: Sell at fair price on second pool
        _requireLegitPool(decoded.poolSell);
        uint256 returnAmount = _swapOnPool(
            decoded.poolSell,
            decoded.tokenArb,
            amountOut
        );

        // Step 3: Verify coverage
        if (returnAmount < amountOwed) revert ArbitrageFailedToCoverLoan();
        uint256 grossProfit = returnAmount - amountOwed;
        if (grossProfit < decoded.minProfit) revert ProfitBelowMinimum(grossProfit, decoded.minProfit);

        // Step 4: Repay flash swap
        IERC20(decoded.tokenBorrow).safeTransfer(msg.sender, amountOwed);
        emit FlashSwapRepaid(msg.sender, fee0, fee1);

        // Step 5: Distribute profit
        _distributeProfit(
            decoded.tokenBorrow,
            decoded.tokenArb,
            grossProfit,
            decoded.victim,
            decoded.targetTxHash,
            decoded.warningWasAttempted
        );
    }

    // ─────────────────────────────────────────────
    // INTERNAL — profit distribution (pull pattern)
    // ─────────────────────────────────────────────

    /**
     * @dev Splits gross profit between victim (pull), charity, and operator.
     *      Victim refund uses pull pattern — stored in unclaimedRefunds mapping.
     *      Charity and operator receive immediately via push (trusted addresses).
     *      All writes are atomic — same transaction as the flash swap.
     */
    function _distributeProfit(
        address token,
        address tokenArb,
        uint256 grossProfit,
        address victim,
        bytes32 targetTxHash,
        bool warningWasAttempted
    ) internal {
        // Read live ratios from admin contract to prevent desync
        (uint256 adminVictimBps, uint256 adminCharityBps, ) =
            IHalalBotAdmin(adminContract).getDistributionRatios();

        uint256 victimAmount   = (grossProfit * adminVictimBps)  / 10000;
        uint256 charityAmount  = (grossProfit * adminCharityBps) / 10000;
        uint256 operatorAmount = grossProfit - victimAmount - charityAmount;

        // Victim refund — pull pattern
        // Stored in mapping; victim calls claimRefund() at their convenience
        if (victimAmount > 0 && victim != address(0)) {
            unclaimedRefunds[victim][token] += victimAmount;
            emit RefundAvailable(victim, token, victimAmount);
        }

        // Charity — push (trusted address, controlled by admin)
        if (charityAmount > 0) {
            IERC20(token).safeTransfer(charityWallet, charityAmount);
        }

        // Operator — push (their earned profit)
        if (operatorAmount > 0) {
            IERC20(token).safeTransfer(operator, operatorAmount);
        }

        // Update cumulative stats (victim amount tracked when claimed, not here)
        totalExecutions++;
        totalProfitCaptured   += grossProfit;
        totalSentToCharity    += charityAmount;

        // Full audit event — immutable, public, permanent
        emit BackrunExecuted(
            targetTxHash,
            victim,
            token,
            tokenArb,
            grossProfit,
            victimAmount,
            charityAmount,
            operatorAmount,
            block.number,
            warningWasAttempted
        );
    }

    // ─────────────────────────────────────────────
    // INTERNAL — swap helpers
    // ─────────────────────────────────────────────

    function _swapOnPool(
        address pool,
        address tokenIn,
        uint256 amountIn
    ) internal returns (uint256 amountOut) {
        _activeSwapPool = pool;

        address token0    = IUniswapV3Pool(pool).token0();
        bool zeroForOne   = tokenIn == token0;

        (int256 amount0Delta, int256 amount1Delta) = IUniswapV3Pool(pool).swap(
            address(this),
            zeroForOne,
            int256(amountIn),
            zeroForOne ? MIN_SQRT_RATIO + 1 : MAX_SQRT_RATIO - 1,
            abi.encode(tokenIn)
        );

        _activeSwapPool = address(0);
        amountOut = uint256(-(zeroForOne ? amount1Delta : amount0Delta));
    }

    function _verifyPool(
        address tokenA,
        address tokenB,
        uint24  feeTier
    ) internal view returns (address pool) {
        pool = IUniswapV3Factory(UNISWAP_V3_FACTORY).getPool(tokenA, tokenB, feeTier);
        if (pool == address(0)) revert InvalidPool();
    }

    function _requireLegitPool(address pool) internal view {
        address token0   = IUniswapV3Pool(pool).token0();
        address token1   = IUniswapV3Pool(pool).token1();
        uint24  fee      = IUniswapV3Pool(pool).fee();
        address expected = IUniswapV3Factory(UNISWAP_V3_FACTORY).getPool(token0, token1, fee);
        if (expected != pool) revert InvalidArbPool();
    }

    // ─────────────────────────────────────────────
    // UNISWAP V3 SWAP CALLBACK
    // ─────────────────────────────────────────────

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external override {
        // Verify caller is the active swap pool — prevents drain attacks
        if (msg.sender != _activeSwapPool) revert InvalidSwapCaller();

        address tokenIn    = abi.decode(data, (address));
        uint256 amountOwed = amount0Delta > 0
            ? uint256(amount0Delta)
            : uint256(amount1Delta);

        IERC20(tokenIn).safeTransfer(msg.sender, amountOwed);
    }

    // ─────────────────────────────────────────────
    // ETH RECEIVE
    // ─────────────────────────────────────────────

    /**
     * @dev Accept ETH sent directly to the contract.
     *      Accumulated ETH is withdrawable by the operator via withdrawETH().
     */
    receive() external payable {}

    // ─────────────────────────────────────────────
    // VIEW — audit config (required by proxy interface check)
    // ─────────────────────────────────────────────

    function getAuditConfig() external view returns (
        uint256 victimRefundBps_,
        uint256 charityBps_,
        uint256 operatorBps_,
        address charityWallet_,
        bool    warningEnabled_,
        uint256 totalExecutions_,
        uint256 totalReturnedToVictims_,
        uint256 totalSentToCharity_
    ) {
        victimRefundBps_        = victimRefundBps;
        charityBps_             = charityBps;
        operatorBps_            = 10000 - victimRefundBps - charityBps;
        charityWallet_          = charityWallet;
        warningEnabled_         = warningSystemEnabled;
        totalExecutions_        = totalExecutions;
        totalReturnedToVictims_ = totalReturnedToVictims;
        totalSentToCharity_     = totalSentToCharity;
    }
}

// ─────────────────────────────────────────────
// INTERFACE
// ─────────────────────────────────────────────

interface IHalalBotAdmin {
    function getDistributionRatios() external view returns (
        uint256 victimBps_,
        uint256 charityBps_,
        uint256 operatorBps_
    );
}
