// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./MockERC20.sol";

contract MockUniswapV3Pool {
    address public token0;
    address public token1;
    
    constructor(address _token0, address _token1) {
        token0 = _token0;
        token1 = _token1;
    }
    
    function flash(
        address recipient,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external {
        // Mock flash loan - transfer tokens to recipient
        if (amount0 > 0) {
            MockERC20(token0).transfer(recipient, amount0);
        }
        if (amount1 > 0) {
            MockERC20(token1).transfer(recipient, amount1);
        }
        
        // In a real scenario, the callback would be called here
        // For synthetic test, we skip the callback and just verify the transfer
    }
}
