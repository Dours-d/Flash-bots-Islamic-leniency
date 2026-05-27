const hre = require("hardhat");

async function main() {
  console.log("=== Testing minimal deployment (1 contract) ===");
  
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying with account:", deployer.address);
  console.log("Balance:", hre.ethers.formatEther(await hre.ethers.provider.getBalance(deployer.address)), "ETH");

  console.log("\n=== Deploying HalalBotAdmin ===");
  const Admin = await hre.ethers.getContractFactory("HalalBotAdmin");
  const charityWallet = "0x861c0Fab00E75e82CEfAfC5D4390395F45aE4c80";
  // NOTE: Operator address was malformed (66 chars), using temporary valid address
  const operator = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8";
  
  const admin = await Admin.deploy(charityWallet, operator);
  await admin.waitForDeployment();
  const adminAddress = await admin.getAddress();
  console.log("HalalBotAdmin deployed to:", adminAddress);
  
  console.log("\n=== SUCCESS ===");
  process.exit(0);
}

main().catch((error) => {
  console.error("FAILED:", error);
  process.exit(1);
});
