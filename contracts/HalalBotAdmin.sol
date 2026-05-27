// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable2Step.sol";

/**
 * @title HalalBotAdmin
 * @notice Contract 1 of 3 — Proxy Administrator
 *
 * @dev Controls upgrade authority over the proxy.
 *      Separates admin logic from execution logic entirely.
 *      Uses Ownable2Step — ownership transfers require explicit acceptance,
 *      preventing accidental loss of control.
 *
 * ISLAMIC FINANCE NOTE:
 *      Transparency of control is a requirement of this system.
 *      This contract's owner, upgrade history, and all parameter changes
 *      are permanently on-chain and publicly readable.
 *      No hidden admin keys. No obscured upgrade paths.
 */
contract HalalBotAdmin is Ownable2Step {

    // ─────────────────────────────────────────────
    // EVENTS — full audit trail of all admin actions
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

    event EmergencyPauseTriggered(
        address indexed triggeredBy,
        string reason
    );

    // ─────────────────────────────────────────────
    // STATE
    // ─────────────────────────────────────────────

    /// @dev Minimum victim refund ratio — cannot be set below this (protects ihsan layer)
    uint256 public constant MIN_VICTIM_REFUND_BPS = 2000; // 20% minimum, always enforced

    /// @dev Minimum upgrade timelock — prevents instant upgrades under duress
    uint256 public constant MIN_TIMELOCK_BLOCKS = 50; // ~10 minutes on Arbitrum

    /// @dev Current victim refund ratio in basis points
    uint256 public victimRefundBps = 2000; // default 20%

    /// @dev Charity/sadaqah wallet — receives zakat portion
    address public charityWallet;

    /// @dev Charity ratio in basis points
    uint256 public charityBps = 1000; // default 10%

    /// @dev Upgrade timelock — minimum blocks between upgrade proposal and execution
    uint256 public upgradeTimelockBlocks = 50; // ~10 minutes on Arbitrum

    /// @dev Pending upgrade proposals
    struct UpgradeProposal {
        address newImplementation;
        uint256 proposedAtBlock;
        string reason;
        bool executed;
    }

    mapping(address => UpgradeProposal) public upgradeProposals; // proxy => proposal

    // ─────────────────────────────────────────────
    // CONSTRUCTOR
    // ─────────────────────────────────────────────

    constructor(address _charityWallet) Ownable(msg.sender) {
        require(_charityWallet != address(0), "Admin: charity wallet required");
        charityWallet = _charityWallet;
        upgradeTimelockBlocks = MIN_TIMELOCK_BLOCKS; // Enforce minimum on deployment
    }

    // ─────────────────────────────────────────────
    // UPGRADE MANAGEMENT (timelocked)
    // ─────────────────────────────────────────────

    /**
     * @notice Propose an implementation upgrade (starts timelock)
     * @param proxy The proxy contract to upgrade
     * @param newImplementation The new logic contract address
     * @param reason Human-readable reason — required, stored on-chain for transparency
     */
    function proposeUpgrade(
        address proxy,
        address newImplementation,
        string calldata reason
    ) external onlyOwner {
        require(bytes(reason).length > 0, "Admin: reason required for transparency");
        require(newImplementation != address(0), "Admin: invalid implementation");

        upgradeProposals[proxy] = UpgradeProposal({
            newImplementation: newImplementation,
            proposedAtBlock: block.number,
            reason: reason,
            executed: false
        });
    }

    /**
     * @notice Execute a proposed upgrade after timelock has passed
     * @param proxy The proxy to upgrade
     */
    function executeUpgrade(address proxy) external onlyOwner {
        UpgradeProposal storage proposal = upgradeProposals[proxy];

        require(proposal.newImplementation != address(0), "Admin: no proposal");
        require(!proposal.executed, "Admin: already executed");
        require(
            block.number >= proposal.proposedAtBlock + upgradeTimelockBlocks,
            "Admin: timelock not passed"
        );

        address oldImpl = IHalalBotProxy(proxy).implementation();
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
    // PARAMETER MANAGEMENT
    // ─────────────────────────────────────────────

    /**
     * @notice Update victim refund ratio — cannot go below MIN_VICTIM_REFUND_BPS
     * @dev The ihsan (goodness) layer is protected by code, not trust
     */
    function setVictimRefundBps(uint256 newBps) external onlyOwner {
        require(newBps >= MIN_VICTIM_REFUND_BPS, "Admin: cannot reduce below 20% minimum");
        require(newBps + charityBps <= 9000, "Admin: operator must retain at least 10%");

        emit VictimRefundRatioUpdated(victimRefundBps, newBps);
        victimRefundBps = newBps;
    }

    function setCharityWallet(address newWallet) external onlyOwner {
        require(newWallet != address(0), "Admin: invalid wallet");
        emit CharityWalletUpdated(charityWallet, newWallet);
        charityWallet = newWallet;
    }

    function setCharityBps(uint256 newBps) external onlyOwner {
        require(newBps >= 500, "Admin: charity minimum 5% for sadaqah");
        require(newBps + victimRefundBps <= 9000, "Admin: operator must retain at least 10%");
        charityBps = newBps;
    }

    // ─────────────────────────────────────────────
    // VIEW — distribution breakdown (publicly readable)
    // ─────────────────────────────────────────────

    function getDistributionRatios() external view returns (
        uint256 victimBps_,
        uint256 charityBps_,
        uint256 operatorBps_
    ) {
        victimBps_ = victimRefundBps;
        charityBps_ = charityBps;
        operatorBps_ = 10000 - victimRefundBps - charityBps;
    }
}

interface IHalalBotProxy {
    function implementation() external view returns (address);
    function upgradeTo(address newImplementation) external;
}
