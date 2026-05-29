const hre = require("hardhat");

async function main() {
  console.log("=== Finding WETH/USDC Pools on Arbitrum Mainnet ===");
  
  // Arbitrum mainnet addresses (from Uniswap docs)
  const FACTORY_ADDRESS = "0x1F98431c8aD98523631AE4a59f267346ea31F984"; // Uniswap V3 Factory
  const WETH_ADDRESS = "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1"; // WETH on Arbitrum (from Uniswap docs)
  const USDC_ADDRESS = "0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8"; // USDC on Arbitrum
  
  const factoryAbi = [
    'function getPool(address,address,uint24) view returns (address)'
  ];
  const factory = new hre.ethers.Contract(FACTORY_ADDRESS, factoryAbi, hre.ethers.provider);
  
  const feeTiers = [100, 500, 3000, 10000]; // 0.01%, 0.05%, 0.3%, 1%
  
  console.log("\n=== WETH/USDC Pools ===");
  const foundPools = [];
  
  for (const fee of feeTiers) {
    try {
      const pool = await factory.getPool(WETH_ADDRESS, USDC_ADDRESS, fee);
      if (pool !== "0x0000000000000000000000000000000000000000") {
        foundPools.push({ fee, address: pool });
        console.log(`✓ Fee ${fee} bps: ${pool}`);
      }
    } catch (e) {
      console.log(`✗ Fee ${fee} bps: Pool does not exist`);
    }
  }
  
  if (foundPools.length >= 2) {
    console.log(`\n✅ ${foundPools.length} pools found - suitable for cross-pool arbitrage!`);
    console.log("\nRecommended pool pairs for arbitrage:");
    for (let i = 0; i < foundPools.length - 1; i++) {
      console.log(`  ${foundPools[i].fee} bps ↔ ${foundPools[i+1].fee} bps`);
    }
  } else if (foundPools.length === 1) {
    console.log(`\n⚠ Only 1 pool found - not suitable for cross-pool arbitrage`);
  } else {
    console.log(`\n❌ No pools found`);
  }
}

main().catch((error) => {
  console.error("FAILED:", error);
  process.exit(1);
});
