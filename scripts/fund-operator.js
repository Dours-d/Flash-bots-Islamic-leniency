const hre = require("hardhat");

async function main() {
  console.log("=== Funding Operator Wallet ===");
  
  const [owner] = await hre.ethers.getSigners();
  console.log("Owner account:", owner.address);
  console.log("Owner balance:", hre.ethers.formatEther(await hre.ethers.provider.getBalance(owner.address)), "ETH");

  const operatorAddress = "0xB429057aD392ea5564E47297F49f506039f55200";
  const fundAmount = hre.ethers.parseEther("0.2"); // 0.2 ETH for gas

  console.log("\n=== Funding Operator ===");
  console.log("Operator address:", operatorAddress);
  console.log("Amount:", hre.ethers.formatEther(fundAmount), "ETH");

  const tx = await owner.sendTransaction({
    to: operatorAddress,
    value: fundAmount
  });

  console.log("Transaction hash:", tx.hash);
  await tx.wait();
  console.log("Funding complete");

  console.log("\n=== Verifying Operator Balance ===");
  const operatorBalance = await hre.ethers.provider.getBalance(operatorAddress);
  console.log("Operator balance:", hre.ethers.formatEther(operatorBalance), "ETH");
}

main().catch((error) => {
  console.error("FAILED:", error);
  process.exit(1);
});
