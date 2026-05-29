const hre = require("hardhat");

async function main() {
  console.log("=== Finding Token Pools on Arbitrum Sepolia ===");
  
  const FACTORY_ADDRESS = "0x4200000000000000000000000000000000000010";
  
  // Common token addresses on Arbitrum Sepolia
  const tokens = {
    WETH: "0x4200000000000000000000000000000000000006",
    USDC: "0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d",
    USDT: "0x912CE59144191C1204E64559FE8253a0e49E6548",
    DAI: "0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1",
    ARB: "0x912CE59144191C1204E64559FE8253a0e49E6548"
  };
  
  const factoryAbi = [
    'function getPool(address,address,uint24) view returns (address)'
  ];
  const factory = new hre.ethers.Contract(FACTORY_ADDRESS, factoryAbi, hre.ethers.provider);
  
  const feeTiers = [100, 500, 3000, 10000]; // 0.01%, 0.05%, 0.3%, 1%
  
  const pairs = [
    ["WETH", "USDC"],
    ["WETH", "USDT"],
    ["WETH", "DAI"],
    ["USDC", "USDT"],
    ["USDC", "DAI"]
  ];
  
  console.log("\n=== Checking Pool Pairs ===");
  for (const [tokenA, tokenB] of pairs) {
    const addressA = tokens[tokenA];
    const addressB = tokens[tokenB];
    
    console.log(`\n${tokenA}/${tokenB}:`);
    const foundPools = [];
    
    for (const fee of feeTiers) {
      try {
        const pool = await factory.getPool(addressA, addressB, fee);
        if (pool !== "0x0000000000000000000000000000000000000000") {
          foundPools.push({ fee, address: pool });
          console.log(`  ✓ Fee ${fee} bps: ${pool}`);
        }
      } catch (e) {
        // Pool doesn't exist
      }
    }
    
    if (foundPools.length >= 2) {
      console.log(`  ✅ Multiple pools found - suitable for cross-pool arbitrage!`);
    } else if (foundPools.length === 1) {
      console.log(`  ⚠ Only 1 pool found - not suitable for cross-pool arbitrage`);
    } else {
      console.log(`  ❌ No pools found`);
    }
  }
}

main().catch((error) => {
  console.error("FAILED:", error);
  process.exit(1);
});
