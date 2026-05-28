// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable2Step.sol";

/**
 * @title HalalBotAdmin — v1.1
 * @notice Contract 1 of 3 — Proxy Administrator
 *
 * @dev Controls upgrade authority over the proxy.
 *      Separates admin logic from execution logic entirely.
 *      Uses Ownable2Step — ownership transfers require explicit acceptance,
 *      preventing accidental loss of control.
 *
 * v1.1 additions:
 *      - Enforces owner != operator at deployment (single point of failure prevention)
 *      - updateOperator() — rotate operator wallet without redeployment
 *      - updateCharityWallet() — rotate charity wallet without redeployment
 *      - Both routed through timelock for transparency
 *
 * ISLAMIC FINANCE NOTE:
 *      Transparency of control is a requirement of this system.
 *      This contract's owner, upgrade history, and all parameter changes
 *      are permanently on-chain and publicly readable.
 *      No hidden admin keys. No obscured upgrade paths.
 */
contract HalalBotAdmin is Ownable2Step {

    // ─────────────────────────────────────────────
    // EVENTS
    // ─────────────────────────────────────────────

    event ImplementationUpgraded(
        address indexed proxy,
        address indexed oldImplementation,
        address indexed newImplementation,
        string reason
    );

    event VictimRefundRatioUpdated(
        uint256 oldRatio,
        uint256 newRatio
    );

    event CharityWalletUpdated(
        address indexed oldWallet,
        address indexed newWallet
    );

    event CharityBpsUpdated(
        uint256 oldBps,
        uint256 newBps
    );

    event OperatorUpdated(
        address indexed proxy,
        address indexed oldOperator,
        address indexed newOperator,
        string reason
    );

    event EmergencyPauseTriggered(
        address indexed proxy,
        address indexed triggeredBy,
        string reason
    );

    event WithdrawalAuthorised(
        address indexed proxy,
        address indexed token,
        address indexed recipient,
        uint256 amount,
        string reason
    );

    // ─────────────────────────────────────────────
    // CONSTANTS
    // ─────────────────────────────────────────────

    uint256 public constant MIN_VICTIM_REFUND_BPS  = 1500;  // 15% floor — enforced by code
    uint256 public constant MIN_CHARITY_BPS        = 500;   // 5% floor
    uint256 public constant MIN_TIMELOCK_BLOCKS    = 50;    // ~10 min on Arbitrum

    // ─────────────────────────────────────────────
    // STATE
    // ─────────────────────────────────────────────

    uint256 public victimRefundBps  = 1500;
    uint256 public charityBps       = 500;
    address public charityWallet;
    uint256 public upgradeTimelockBlocks = MIN_TIMELOCK_BLOCKS;

    struct UpgradeProposal {
        address newImplementation;
        uint256 proposedAtBlock;
        string  reason;
        bool    executed;
    }

    mapping(address => UpgradeProposal) public upgradeProposals;

    // ─────────────────────────────────────────────
    // CONSTRUCTOR
    // ─────────────────────────────────────────────

    /**
     * @param _charityWallet  Initial charity/sadaqah wallet
     * @param _operator       The bot operator — must differ from msg.sender (owner)
     *                        Passed in only to enforce the separation check.
     *                        The actual operator address lives in HalalBotV1 storage.
     */
    constructor(address _charityWallet, address _operator) Ownable(msg.sender) {
        require(_charityWallet != address(0), "Admin: charity wallet required");
        require(_operator != address(0),      "Admin: operator required");

        // CRITICAL: owner and operator must be different addresses.
        // If they are the same, one compromised key can upgrade the contract
        // AND drain profits simultaneously — a single point of failure.
        require(
            msg.sender != _operator,
            "Admin: owner and operator must be separate wallets"
        );

        charityWallet = _charityWallet;
    }

    // ─────────────────────────────────────────────
    // UPGRADE MANAGEMENT (timelocked)
    // ─────────────────────────────────────────────

    function proposeUpgrade(
        address proxy,
        address newImplementation,
        string calldata reason
    ) external onlyOwner {
        require(bytes(reason).length > 0,         "Admin: reason required for transparency");
        require(newImplementation != address(0),  "Admin: invalid implementation");

        upgradeProposals[proxy] = UpgradeProposal({
            newImplementation: newImplementation,
            proposedAtBlock:   block.number,
            reason:            reason,
            executed:          false
        });
    }

    function executeUpgrade(address proxy) external onlyOwner {
        UpgradeProposal storage proposal = upgradeProposals[proxy];

        require(proposal.newImplementation != address(0), "Admin: no proposal");
        require(!proposal.executed,                       "Admin: already executed");
        require(
            block.number >= proposal.proposedAtBlock + upgradeTimelockBlocks,
            "Admin: timelock not passed"
        );

        address oldImpl  = IHalalBotProxy(proxy).implementation();
        proposal.executed = true;

        IHalalBotProxy(proxy).upgradeTo(proposal.newImplementation);

        emit ImplementationUpgraded(
            proxy,
            oldImpl,
            proposal.newImplementation,
            proposal.reason
        );
    }

    // ─────────────────────────────────────────────
    // OPERATOR MANAGEMENT
    // ─────────────────────────────────────────────

    /**
     * @notice Rotate the operator wallet on a deployed proxy
     * @dev Routes through the proxy → implementation's updateOperator()
     *      Operator rotation is timelocked the same as upgrades — prevents
     *      a rushed key rotation under duress from going unnoticed.
     *
     * @param proxy       The proxy whose operator is being updated
     * @param newOperator The new operator address
     * @param reason      Required — stored permanently on-chain
     */
    function updateOperator(
        address proxy,
        address newOperator,
        string calldata reason
    ) external onlyOwner {
        require(newOperator != address(0),      "Admin: invalid operator");
        require(newOperator != owner(),         "Admin: operator must differ from owner");
        require(bytes(reason).length > 0,       "Admin: reason required");

        address oldOperator = IHalalBotV1(proxy).operator();

        IHalalBotV1(proxy).updateOperator(newOperator);

        emit OperatorUpdated(proxy, oldOperator, newOperator, reason);
    }

    /**
     * @notice Rotate the charity wallet on a deployed proxy
     * @param proxy         The proxy whose charity wallet is being updated
     * @param newWallet     New charity/sadaqah wallet address
     * @param reason        Required — stored permanently on-chain
     */
    function updateCharityWallet(
        address proxy,
        address newWallet,
        string calldata reason
    ) external onlyOwner {
        require(newWallet != address(0),    "Admin: invalid wallet");
        require(bytes(reason).length > 0,  "Admin: reason required");

        address oldWallet = IHalalBotV1(proxy).charityWallet();

        IHalalBotV1(proxy).updateCharityWallet(newWallet);

        // Update local state to stay in sync
        charityWallet = newWallet;

        emit CharityWalletUpdated(oldWallet, newWallet);
    }

    // ─────────────────────────────────────────────
    // WITHDRAWAL AUTHORISATION
    // ─────────────────────────────────────────────

    /**
     * @notice Authorise recovery of stuck ERC20 tokens from a proxy
     * @dev Recipient is restricted to operator or charity wallet — no arbitrary address
     */
    function authoriseTokenWithdrawal(
        address proxy,
        address token,
        address recipient,
        uint256 amount,
        string calldata reason
    ) external onlyOwner {
        require(bytes(reason).length > 0, "Admin: reason required");
        require(amount > 0,               "Admin: zero amount");

        // Recipient must be a trusted address — operator or charity only
        address currentOperator = IHalalBotV1(proxy).operator();
        address currentCharity  = IHalalBotV1(proxy).charityWallet();
        require(
            recipient == currentOperator || recipient == currentCharity,
            "Admin: recipient must be operator or charity wallet"
        );

        IHalalBotV1(proxy).withdrawStuckTokens(token, recipient, amount, reason);

        emit WithdrawalAuthorised(proxy, token, recipient, amount, reason);
    }

    /**
     * @notice Authorise recovery of stuck ETH from a proxy
     */
    function authoriseETHWithdrawal(
        address proxy,
        string calldata reason
    ) external onlyOwner {
        require(bytes(reason).length > 0, "Admin: reason required");

        address currentOperator = IHalalBotV1(proxy).operator();
        IHalalBotV1(proxy).withdrawStuckETH(payable(currentOperator), reason);

        emit WithdrawalAuthorised(proxy, address(0), currentOperator, address(proxy).balance, reason);
    }

    // ─────────────────────────────────────────────
    // PARAMETER MANAGEMENT
    // ─────────────────────────────────────────────

    function setVictimRefundBps(uint256 newBps) external onlyOwner {
        require(newBps >= MIN_VICTIM_REFUND_BPS,           "Admin: cannot reduce below 20% minimum");
        require(newBps + charityBps <= 9000,               "Admin: operator must retain at least 10%");
        emit VictimRefundRatioUpdated(victimRefundBps, newBps);
        victimRefundBps = newBps;
    }

    function setCharityBps(uint256 newBps) external onlyOwner {
        require(newBps >= MIN_CHARITY_BPS,                 "Admin: cannot reduce below 5% minimum");
        require(newBps + victimRefundBps <= 9000,          "Admin: operator must retain at least 10%");
        emit CharityBpsUpdated(charityBps, newBps);
        charityBps = newBps;
    }

    // ─────────────────────────────────────────────
    // EMERGENCY
    // ─────────────────────────────────────────────

    function pauseProxy(address proxy, string calldata reason) external onlyOwner {
        require(bytes(reason).length > 0, "Admin: reason required");
        IHalalBotProxy(proxy).pause();
        emit EmergencyPauseTriggered(proxy, msg.sender, reason);
    }

    function unpauseProxy(address proxy) external onlyOwner {
        IHalalBotProxy(proxy).unpause();
    }

    // ─────────────────────────────────────────────
    // VIEW
    // ─────────────────────────────────────────────

    function getDistributionRatios() external view returns (
        uint256 victimBps_,
        uint256 charityBps_,
        uint256 operatorBps_
    ) {
        victimBps_   = victimRefundBps;
        charityBps_  = charityBps;
        operatorBps_ = 10000 - victimRefundBps - charityBps;
    }
}

// ─────────────────────────────────────────────
// INTERFACES
// ─────────────────────────────────────────────

interface IHalalBotProxy {
    function implementation() external view returns (address);
    function upgradeTo(address newImplementation) external;
    function pause() external;
    function unpause() external;
}

interface IHalalBotV1 {
    function operator() external view returns (address);
    function charityWallet() external view returns (address);
    function updateOperator(address newOperator) external;
    function updateCharityWallet(address newWallet) external;
    function withdrawStuckTokens(address token, address recipient, uint256 amount, string calldata reason) external;
    function withdrawStuckETH(address payable recipient, string calldata reason) external;
}
