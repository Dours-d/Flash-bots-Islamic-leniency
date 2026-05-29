const hre = require("hardhat");

async function main() {
  console.log("=== Wrapping ETH to WETH ===");
  
  const [owner] = await hre.ethers.getSigners();
  console.log("Owner account:", owner.address);
  console.log("ETH balance:", hre.ethers.formatEther(await hre.ethers.provider.getBalance(owner.address)), "ETH");

  const WETH_ADDRESS = "0x4200000000000000000000000000000000000006";
  const wrapAmount = hre.ethers.parseEther("0.05"); // 0.05 ETH to WETH

  console.log("\n=== WETH Contract ===");
  console.log("WETH address:", WETH_ADDRESS);
  console.log("Amount to wrap:", hre.ethers.formatEther(wrapAmount), "ETH");

  const wethAbi = [
    'function deposit() payable',
    'function balanceOf(address) view returns (uint256)',
    'function withdraw(uint256)'
  ];

  const weth = new hre.ethers.Contract(WETH_ADDRESS, wethAbi, owner);

  console.log("\n=== Wrapping ETH ===");
  const tx = await weth.deposit({ value: wrapAmount });
  console.log("Transaction hash:", tx.hash);
  await tx.wait();
  console.log("Wrap complete");

  console.log("\n=== Wrap Successful ===");
  console.log("Wrapped:", hre.ethers.formatEther(wrapAmount), "ETH to WETH");
  console.log("Note: WETH on Arbitrum Sepolia may use native ETH wrapping");
}

main().catch((error) => {
  console.error("FAILED:", error);
  process.exit(1);
});
