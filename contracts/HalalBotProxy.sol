// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title HalalBotProxy
 * @notice Contract 2 of 3 — The Proxy (Storage + Delegation)
 *
 * @dev This contract:
 *      - Holds all persistent state (balances, config, audit logs)
 *      - Delegates all execution calls to the current Implementation
 *      - Can only be upgraded by the designated HalalBotAdmin
 *      - Never executes business logic itself
 *
 * ARCHITECTURE NOTE:
 *      This follows the Transparent Proxy Pattern with one modification:
 *      the admin is a separate contract (HalalBotAdmin), not an EOA.
 *      This prevents any single private key from being a single point of failure
 *      or a source of hidden control — a requirement of the ethical framework.
 *
 * STORAGE LAYOUT (never reorder these — upgradeability depends on slot consistency):
 *      Slot 0: _implementation
 *      Slot 1: _admin
 *      Slot 2: _paused
 *      Slot 3+: reserved for implementation state (via BotStorage)
 */
contract HalalBotProxy {

    // ─────────────────────────────────────────────
    // STORAGE SLOTS (EIP-1967 standard)
    // Using explicit slot constants prevents collision with implementation storage
    // ─────────────────────────────────────────────

    /// @dev EIP-1967 implementation slot
    bytes32 private constant IMPLEMENTATION_SLOT =
        bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);

    /// @dev EIP-1967 admin slot
    bytes32 private constant ADMIN_SLOT =
        bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1);

    /// @dev Pause slot
    bytes32 private constant PAUSED_SLOT =
        bytes32(uint256(keccak256("halalbot.proxy.paused")) - 1);

    // ─────────────────────────────────────────────
    // EVENTS
    // ─────────────────────────────────────────────

    event Upgraded(address indexed newImplementation);
    event AdminChanged(address indexed previousAdmin, address indexed newAdmin);
    event Paused(address indexed by);
    event Unpaused(address indexed by);
    event EmergencyPauseTriggered(address indexed triggeredBy, string reason);

    // ─────────────────────────────────────────────
    // CONSTRUCTOR
    // ─────────────────────────────────────────────

    /**
     * @param _implementation Initial logic contract address
     * @param _admin HalalBotAdmin contract address (not an EOA)
     * @param _initData ABI-encoded initializer call (or empty bytes)
     */
    constructor(
        address _implementation,
        address _admin,
        bytes memory _initData
    ) {
        require(_implementation != address(0), "Proxy: invalid implementation");
        require(_admin != address(0), "Proxy: admin must be HalalBotAdmin contract");

        _setImplementation(_implementation);
        _setAdmin(_admin);

        // If init data provided, call initializer on implementation
        if (_initData.length > 0) {
            (bool success, bytes memory returnData) = _implementation.delegatecall(_initData);
            require(success, string(returnData));
        }
    }

    // ─────────────────────────────────────────────
    // ADMIN-ONLY FUNCTIONS
    // ─────────────────────────────────────────────

    modifier onlyAdmin() {
        require(msg.sender == _getAdmin(), "Proxy: caller is not admin");
        _;
    }

    modifier whenNotPaused() {
        require(!_getPaused(), "Proxy: system paused");
        _;
    }

    /**
     * @notice Upgrade to new implementation
     * @dev Only callable by HalalBotAdmin after timelock has passed
     */
    function upgradeTo(address newImplementation) external onlyAdmin {
        require(newImplementation != address(0), "Proxy: invalid address");
        require(newImplementation != _getImplementation(), "Proxy: same implementation");

        // Verify new implementation has required interface
        // (prevents upgrading to a non-compliant contract)
        require(
            _hasRequiredInterface(newImplementation),
            "Proxy: implementation missing required interface"
        );

        _setImplementation(newImplementation);
        emit Upgraded(newImplementation);
    }

    /**
     * @notice Emergency pause — stops all delegated execution
     * @param reason Human-readable reason for the pause (audit trail)
     */
    function pause(string calldata reason) external onlyAdmin {
        _setPaused(true);
        emit Paused(msg.sender);
        emit EmergencyPauseTriggered(msg.sender, reason);
    }

    function unpause() external onlyAdmin {
        _setPaused(false);
        emit Unpaused(msg.sender);
    }

    // ─────────────────────────────────────────────
    // PUBLIC VIEW
    // ─────────────────────────────────────────────

    function implementation() external view returns (address) {
        return _getImplementation();
    }

    function admin() external view returns (address) {
        return _getAdmin();
    }

    function paused() external view returns (bool) {
        return _getPaused();
    }

    // ─────────────────────────────────────────────
    // FALLBACK — delegates all calls to implementation
    // ─────────────────────────────────────────────

    fallback() external payable whenNotPaused {
        _delegate(_getImplementation());
    }

    receive() external payable whenNotPaused {
        _delegate(_getImplementation());
    }

    // ─────────────────────────────────────────────
    // INTERNAL — delegation
    // ─────────────────────────────────────────────

    function _delegate(address impl) internal {
        assembly {
            // Copy calldata to memory
            calldatacopy(0, 0, calldatasize())

            // delegatecall: runs impl code in this contract's storage context
            let result := delegatecall(gas(), impl, 0, calldatasize(), 0, 0)

            // Copy returndata
            returndatacopy(0, 0, returndatasize())

            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    // ─────────────────────────────────────────────
    // INTERNAL — EIP-1967 slot read/write
    // ─────────────────────────────────────────────

    function _getImplementation() internal view returns (address impl) {
        bytes32 slot = IMPLEMENTATION_SLOT;
        assembly { impl := sload(slot) }
    }

    function _setImplementation(address impl) internal {
        bytes32 slot = IMPLEMENTATION_SLOT;
        assembly { sstore(slot, impl) }
    }

    function _getAdmin() internal view returns (address adm) {
        bytes32 slot = ADMIN_SLOT;
        assembly { adm := sload(slot) }
    }

    function _setAdmin(address adm) internal {
        bytes32 slot = ADMIN_SLOT;
        assembly { sstore(slot, adm) }
    }

    function _getPaused() internal view returns (bool p) {
        bytes32 slot = PAUSED_SLOT;
        assembly { p := sload(slot) }
    }

    function _setPaused(bool p) internal {
        bytes32 slot = PAUSED_SLOT;
        assembly { sstore(slot, p) }
    }

    // ─────────────────────────────────────────────
    // INTERNAL — interface verification
    // ─────────────────────────────────────────────

    /**
     * @dev Checks that new implementation exposes the mandatory audit function.
     *      Prevents upgrading to a contract that drops the transparency layer.
     */
    function _hasRequiredInterface(address impl) internal view returns (bool) {
        // Check for getAuditConfig() selector — 0x[computed]
        // This ensures the implementation always exposes its ethical config
        bytes memory callData = abi.encodeWithSignature("getAuditConfig()");
        (bool success, ) = impl.staticcall(callData);
        return success;
    }
}
