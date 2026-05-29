const hre = require("hardhat");

async function main() {
  console.log("=== Executing Victim Swap Transaction ===");
  
  const [owner] = await hre.ethers.getSigners();
  console.log("Owner account:", owner.address);

  // Token addresses
  const WETH_ADDRESS = "0x4200000000000000000000000000000000000006";
  const USDC_ADDRESS = "0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d";
  const POOL_FEE = 500; // 0.05% fee tier
  
  // Use known pool address for WETH/USDC on Arbitrum Sepolia
  const POOL_ADDRESS = "0x31b4e4452c843c6a6705e3878434230553c64393";
  console.log("WETH/USDC Pool:", POOL_ADDRESS);

  // Swap Router (use quoter for price estimation, swap router for execution)
  const SWAP_ROUTER = "0xE592427A0AEce92De3Edee1F18E0157C05861564"; // Uniswap V3 SwapRouter
  
  const routerAbi = [
    'function exactInputSingle((address tokenIn, address tokenOut, uint24 fee, address recipient, uint256 deadline, uint256 amountIn, uint256 amountOutMinimum, uint160 sqrtPriceLimitX96)) payable returns (uint256 amountOut)'
  ];

  const router = new hre.ethers.Contract(SWAP_ROUTER, routerAbi, owner);

  // Approve WETH
  const wethAbi = [
    'function approve(address,uint256) returns (bool)'
  ];
  const weth = new hre.ethers.Contract(WETH_ADDRESS, wethAbi, owner);
  
  const swapAmount = hre.ethers.parseEther("0.01"); // Swap 0.01 WETH
  console.log("Swap amount:", hre.ethers.formatEther(swapAmount), "WETH");

  console.log("\n=== Approving WETH ===");
  const approveTx = await weth.approve(SWAP_ROUTER, swapAmount);
  console.log("Approve tx:", approveTx.hash);
  await approveTx.wait();
  console.log("Approved");

  console.log("\n=== Executing Swap ===");
  const deadline = Math.floor(Date.now() / 1000) + 60 * 20; // 20 minutes
  
  const params = {
    tokenIn: WETH_ADDRESS,
    tokenOut: USDC_ADDRESS,
    fee: POOL_FEE,
    recipient: owner.address,
    deadline: deadline,
    amountIn: swapAmount,
    amountOutMinimum: 0, // Accept any amount for test
    sqrtPriceLimitX96: 0 // No price limit for test
  };

  const swapTx = await router.exactInputSingle(params);
  console.log("Swap tx:", swapTx.hash);
  const receipt = await swapTx.wait();
  console.log("Swap complete");
  console.log("Gas used:", receipt.gasUsed.toString());

  console.log("\n=== Transaction Details ===");
  console.log("Transaction hash:", swapTx.hash);
  console.log("Block number:", receipt.blockNumber);
  console.log("This tx hash will be used as victimTx for backrun test");
}

main().catch((error) => {
  console.error("FAILED:", error);
  process.exit(1);
});
