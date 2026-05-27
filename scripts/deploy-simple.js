const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying with account:", deployer.address);
  console.log("Balance:", (await ethers.provider.getBalance(deployer.address)).toString());

  // Parameters
  const charityWallet = "0x2EDBF113E633430eD1ba776F961da2D06AAb7735";
  const operator = "0x63fb57a83bcbe2243fa4380ef00a79239ee51c3a7c53c2e36dc85ad289cf955b";
  const victimRefundBps = 2000;
  const charityBps = 0;
  const uniswapV3Factory = "0x4200000000000000000000000000000000000010"; // Arbitrum Sepolia

  console.log("\n=== Step 1: Deploy HalalBotAdmin ===");
  const Admin = await ethers.getContractFactory("HalalBotAdmin");
  const admin = await Admin.deploy(charityWallet, operator);
  await admin.waitForDeployment();
  const adminAddress = await admin.getAddress();
  console.log("HalalBotAdmin deployed to:", adminAddress);

  console.log("\n=== Step 2: Deploy HalalBotV1 (Implementation) ===");
  const Implementation = await ethers.getContractFactory("HalalBotV1");
  const implementation = await Implementation.deploy();
  await implementation.waitForDeployment();
  const implAddress = await implementation.getAddress();
  console.log("HalalBotV1 deployed to:", implAddress);

  console.log("\n=== Step 3: Deploy HalalBotProxy ===");
  const Proxy = await ethers.getContractFactory("HalalBotProxy");
  
  // Encode initializer call
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

  // Verify initialization
  console.log("\n=== Verifying Initialization ===");
  const proxyAsV1 = Implementation.attach(proxyAddress);
  const config = await proxyAsV1.getAuditConfig();
  console.log("Victim Refund BPS:", config.victimRefundBps_.toString());
  console.log("Charity BPS:", config.charityBps_.toString());
  console.log("Operator BPS:", config.operatorBps_.toString());
  console.log("Charity Wallet:", config.charityWallet_);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
