const hre = require("hardhat");

async function main() {
  console.log("=== Checking USDC Balance ===");
  
  const [owner] = await hre.ethers.getSigners();
  console.log("Owner account:", owner.address);

  const USDC_ADDRESS = "0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d"; // Correct Arbitrum Sepolia USDC
  
  const usdcAbi = [
    'function balanceOf(address) view returns (uint256)',
    'function decimals() view returns (uint8)',
    'function symbol() view returns (string)'
  ];

  const usdc = new hre.ethers.Contract(USDC_ADDRESS, usdcAbi, owner);

  console.log("\n=== USDC Contract Info ===");
  console.log("USDC address:", USDC_ADDRESS);
  const symbol = await usdc.symbol();
  const decimals = await usdc.decimals();
  console.log("Symbol:", symbol);
  console.log("Decimals:", decimals);

  console.log("\n=== USDC Balance ===");
  const balance = await usdc.balanceOf(owner.address);
  console.log("Balance:", hre.ethers.formatUnits(balance, decimals), "USDC");
}

main().catch((error) => {
  console.error("FAILED:", error);
  process.exit(1);
});
