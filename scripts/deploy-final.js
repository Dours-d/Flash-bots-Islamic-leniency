const hre = require("hardhat");

async function main() {
  console.log("=== Deploying Three-Contract System ===");
  
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying with account:", deployer.address);
  console.log("Balance:", hre.ethers.formatEther(await hre.ethers.provider.getBalance(deployer.address)), "ETH");

  const charityWallet = "0x861c0Fab00E75e82CEfAfC5D4390395F45aE4c80";
  // NOTE: Using temporary operator address - user needs to provide valid 42-char address
  const operator = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8";
  const victimRefundBps = 2000;
  const charityBps = 0;
  const uniswapV3Factory = "0x4200000000000000000000000000000000000010";

  console.log("\n=== Step 1: Deploy HalalBotAdmin ===");
  const Admin = await hre.ethers.getContractFactory("HalalBotAdmin");
  const admin = await Admin.deploy(charityWallet, operator);
  await admin.waitForDeployment();
  const adminAddress = await admin.getAddress();
  console.log("HalalBotAdmin deployed to:", adminAddress);

  console.log("\n=== Step 2: Deploy HalalBotV1 (Implementation) ===");
  const Implementation = await hre.ethers.getContractFactory("HalalBotV1");
  const implementation = await Implementation.deploy();
  await implementation.waitForDeployment();
  const implAddress = await implementation.getAddress();
  console.log("HalalBotV1 deployed to:", implAddress);

  console.log("\n=== Step 3: Deploy HalalBotProxy ===");
  const Proxy = await hre.ethers.getContractFactory("HalalBotProxy");
  
  const initializerData = implementation.interface.encodeFunctionData("initialize", [
    operator,
    adminAddress,
    charityWallet,
    victimRefundBps,
    charityBps,
    uniswapV3Factory,
  ]);

  const proxy = await Proxy.deploy(implAddress, adminAddress, initializerData);
  await proxy.waitForDeployment();
  const proxyAddress = await proxy.getAddress();
  console.log("HalalBotProxy deployed to:", proxyAddress);

  console.log("\n=== Deployment Summary ===");
  console.log("Admin:", adminAddress);
  console.log("Implementation:", implAddress);
  console.log("Proxy:", proxyAddress);
  console.log("Operator:", operator);
  console.log("Charity Wallet:", charityWallet);

  console.log("\n=== Verifying Initialization ===");
  const proxyAsV1 = Implementation.attach(proxyAddress);
  const config = await proxyAsV1.getAuditConfig();
  console.log("Victim Refund BPS:", config.victimRefundBps_.toString());
  console.log("Charity BPS:", config.charityBps_.toString());
  console.log("Operator BPS:", config.operatorBps_.toString());
  console.log("Charity Wallet:", config.charityWallet_);
}

main().catch((error) => {
  console.error("FAILED:", error);
  process.exit(1);
});
