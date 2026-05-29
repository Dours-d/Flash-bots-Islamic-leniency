const hre = require("hardhat");

async function main() {
  console.log("=== Finding WETH/USDC Pools on Ethereum Sepolia ===");
  
  // Try multiple possible factory addresses
  const FACTORY_ADDRESSES = [
    "0x0227628f3F023bb0B980b67D5DC579cC2eDd08f8",
    "0x1F98431c8aD98523631AE4a59f267346ea31F984", // Mainnet factory (might work on Sepolia)
    "0x4752ba5dbc23f44d8782627616c60cfa58177663"  // Alternative
  ];
  
  const WETH_ADDRESS = "0xfff9976782d46cc05630d1f6ebab18b2324d6b14"; // WETH on Sepolia from Uniswap docs
  const USDC_ADDRESS = "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238"; // USDC on Sepolia
  
  const factoryAbi = [
    'function getPool(address,address,uint24) view returns (address)'
  ];
  
  const feeTiers = [100, 500, 3000, 10000]; // 0.01%, 0.05%, 0.3%, 1%
  
  console.log("\n=== Testing Factory Addresses ===");
  
  for (const FACTORY_ADDRESS of FACTORY_ADDRESSES) {
    console.log(`\nTrying factory: ${FACTORY_ADDRESS}`);
    const factory = new hre.ethers.Contract(FACTORY_ADDRESS, factoryAbi, hre.ethers.provider);
    
    const foundPools = [];
    
    for (const fee of feeTiers) {
      try {
        const pool = await factory.getPool(WETH_ADDRESS, USDC_ADDRESS, fee);
        if (pool !== "0x0000000000000000000000000000000000000000") {
          foundPools.push({ fee, address: pool });
          console.log(`  ✓ Fee ${fee} bps: ${pool}`);
        }
      } catch (e) {
        // Pool doesn't exist or factory is wrong
      }
    }
    
    if (foundPools.length >= 2) {
      console.log(`\n✅ ${foundPools.length} pools found - suitable for cross-pool arbitrage!`);
      console.log(`Using factory: ${FACTORY_ADDRESS}`);
      return;
    } else if (foundPools.length === 1) {
      console.log(`\n⚠ Only 1 pool found - not suitable for cross-pool arbitrage`);
    } else {
      console.log(`  ❌ No pools found with this factory`);
    }
  }
  
  console.log(`\n❌ No suitable pools found with any factory address`);
}

main().catch((error) => {
  console.error("FAILED:", error);
  process.exit(1);
});
