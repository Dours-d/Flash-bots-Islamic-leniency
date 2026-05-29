const hre = require("hardhat");

async function main() {
  console.log("=== Checking WETH/USDC Pools on Arbitrum Sepolia ===");
  
  const WETH_ADDRESS = "0x4200000000000000000000000000000000000006";
  const USDC_ADDRESS = "0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d";
  const FACTORY_ADDRESS = "0x4200000000000000000000000000000000000010";
  
  const factoryAbi = [
    'function getPool(address,address,uint24) view returns (address)'
  ];
  const factory = new hre.ethers.Contract(FACTORY_ADDRESS, factoryAbi, hre.ethers.provider);
  
  const feeTiers = [100, 500, 3000, 10000]; // 0.01%, 0.05%, 0.3%, 1%
  
  console.log("\n=== Pool Addresses ===");
  for (const fee of feeTiers) {
    try {
      const pool = await factory.getPool(WETH_ADDRESS, USDC_ADDRESS, fee);
      console.log(`Fee ${fee} bps: ${pool}`);
    } catch (e) {
      console.log(`Fee ${fee} bps: Pool does not exist`);
    }
  }
}

main().catch((error) => {
  console.error("FAILED:", error);
  process.exit(1);
});
