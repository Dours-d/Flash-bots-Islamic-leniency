const hre = require("hardhat");

async function main() {
  console.log("=== Checking Pool Liquidity ===");
  
  const POOL_ADDRESS = "0x31b4e4452c843c6a6705e3878434230553c64393";
  const WETH_ADDRESS = "0x4200000000000000000000000000000000000006";
  const USDC_ADDRESS = "0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d";
  
  const poolAbi = [
    'function token0() view returns (address)',
    'function token1() view returns (address)',
    'function liquidity() view returns (uint128)',
    'function slot0() view returns (uint160 sqrtPriceX96, int24 tick, uint16 observationIndex, uint16 observationCardinality, uint16 observationCardinalityNext, uint8 feeProtocol, bool unlocked)'
  ];
  
  const pool = new hre.ethers.Contract(POOL_ADDRESS, poolAbi, hre.ethers.provider);
  
  try {
    const token0 = await pool.token0();
    const token1 = await pool.token1();
    const liquidity = await pool.liquidity();
    const slot0 = await pool.slot0();
    
    console.log("Pool:", POOL_ADDRESS);
    console.log("Token0:", token0);
    console.log("Token1:", token1);
    console.log("Liquidity:", liquidity.toString());
    console.log("SqrtPriceX96:", slot0.sqrtPriceX96.toString());
    console.log("Tick:", slot0.tick.toString());
    
    if (liquidity.toString() === "0") {
      console.log("\n⚠ Pool has NO liquidity - cannot execute flash loans");
    } else {
      console.log("\n✓ Pool has liquidity");
    }
  } catch (e) {
    console.error("Failed to query pool:", e.message);
  }
}

main().catch((error) => {
  console.error("FAILED:", error);
  process.exit(1);
});
