// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title HalalBotProxy — v1.1
 * @notice Contract 2 of 3 — The Proxy (Storage + Delegation)
 *
 * @dev This contract:
 *      - Holds all persistent state (balances, config, audit logs)
 *      - Delegates all execution calls to the current Implementation
 *      - Can only be upgraded by the designated HalalBotAdmin
 *      - Never executes business logic itself
 *
 * v1.1 additions:
 *      - pause() now requires a reason string (audit trail)
 *      - EmergencyPauseTriggered event emitted on pause
 *      - receive() properly handles ETH and passes to implementation
 *      - admin-only functions now explicitly reject ETH
 *
 * STORAGE LAYOUT (never reorder — upgradeability depends on slot consistency):
 *      EIP-1967 slots used for implementation + admin (collision-safe)
 *      Slot keccak(eip1967.proxy.implementation)-1 : _implementation
 *      Slot keccak(eip1967.proxy.admin)-1           : _admin
 *      Slot keccak(halalbot.proxy.paused)-1         : _paused
 */
contract HalalBotProxy {

    // ─────────────────────────────────────────────
    // EIP-1967 STORAGE SLOTS
    // ─────────────────────────────────────────────

    bytes32 private constant IMPLEMENTATION_SLOT =
        bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);

    bytes32 private constant ADMIN_SLOT =
        bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1);

    bytes32 private constant PAUSED_SLOT =
        bytes32(uint256(keccak256("halalbot.proxy.paused")) - 1);

    // ─────────────────────────────────────────────
    // EVENTS
    // ─────────────────────────────────────────────

    event Upgraded(address indexed newImplementation);
    event AdminChanged(address indexed previousAdmin, address indexed newAdmin);
    event EmergencyPauseTriggered(address indexed triggeredBy, string reason);
    event Unpaused(address indexed by);

    // ─────────────────────────────────────────────
    // CONSTRUCTOR
    // ─────────────────────────────────────────────

    /**
     * @param _implementation   Initial logic contract address
     * @param _admin            HalalBotAdmin contract address (not an EOA)
     * @param _initData         ABI-encoded initializer call (or empty bytes)
     */
    constructor(
        address _implementation,
        address _admin,
        bytes memory _initData
    ) {
        require(_implementation != address(0), "Proxy: invalid implementation");
        require(_admin != address(0),          "Proxy: admin must be HalalBotAdmin contract");

        _setImplementation(_implementation);
        _setAdmin(_admin);

        if (_initData.length > 0) {
            (bool success, bytes memory returnData) = _implementation.delegatecall(_initData);
            require(success, string(returnData));
        }
    }

    // ─────────────────────────────────────────────
    // MODIFIERS
    // ─────────────────────────────────────────────

    modifier onlyAdmin() {
        require(msg.sender == _getAdmin(), "Proxy: caller is not admin");
        _;
    }

    modifier whenNotPaused() {
        require(!_getPaused(), "Proxy: system paused");
        _;
    }

    // ─────────────────────────────────────────────
    // ADMIN FUNCTIONS
    // ─────────────────────────────────────────────

    /**
     * @notice Upgrade to a new implementation
     * @dev Only callable by HalalBotAdmin after timelock has passed.
     *      Verifies the new implementation exposes getAuditConfig() —
     *      the ethical transparency interface cannot be silently dropped.
     */
    function upgradeTo(address newImplementation) external onlyAdmin {
        require(newImplementation != address(0),               "Proxy: invalid address");
        require(newImplementation != _getImplementation(),     "Proxy: same implementation");
        require(
            _hasRequiredInterface(newImplementation),
            "Proxy: implementation missing getAuditConfig() - ethical interface required"
        );

        _setImplementation(newImplementation);
        emit Upgraded(newImplementation);
    }

    /**
     * @notice Emergency pause — stops all delegated execution
     * @param reason  Human-readable reason, required for audit trail
     */
    function pause(string calldata reason) external onlyAdmin {
        require(bytes(reason).length > 0, "Proxy: pause reason required");
        _setPaused(true);
        emit EmergencyPauseTriggered(msg.sender, reason);
    }

    /**
     * @notice Unpause the system
     */
    function unpause() external onlyAdmin {
        _setPaused(false);
        emit Unpaused(msg.sender);
    }

    // ─────────────────────────────────────────────
    // VIEW
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

    /**
     * @dev All non-admin calls are delegated to the current implementation.
     *      msg.value is forwarded so the implementation can handle ETH.
     *      Admin-facing functions (upgradeTo, pause, unpause) are
     *      handled above and never reach the fallback.
     */
    fallback() external payable whenNotPaused {
        _delegate(_getImplementation());
    }

    /**
     * @dev Plain ETH transfers are delegated to implementation.
     *      Implementation's receive() or fallback() handles the logic
     *      (e.g. recording ETH received for later operator withdrawal).
     */
    receive() external payable whenNotPaused {
        _delegate(_getImplementation());
    }

    // ─────────────────────────────────────────────
    // INTERNAL — delegation
    // ─────────────────────────────────────────────

    function _delegate(address impl) internal {
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), impl, 0, calldatasize(), 0, 0)
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
     * @dev Checks that new implementation exposes getAuditConfig().
     *      Prevents upgrading to a contract that removes the transparency layer.
     *      The ethical interface is enforced structurally — not by trust.
     */
    function _hasRequiredInterface(address impl) internal view returns (bool) {
        bytes memory callData = abi.encodeWithSignature("getAuditConfig()");
        (bool success, ) = impl.staticcall(callData);
        return success;
    }
}
