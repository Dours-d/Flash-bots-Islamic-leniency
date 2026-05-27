const { ethers } = require("ethers");
require("dotenv").config();

async function main() {
  const privateKey = process.env.PRIVATE_KEY;
  const rpcUrl = process.env.ARBITRUM_SEPOLIA_RPC_URL || "https://sepolia-rollup.arbitrum.io/rpc";
  
  if (!privateKey) {
    throw new Error("PRIVATE_KEY not found in .env");
  }

  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const wallet = new ethers.Wallet(privateKey, provider);
  
  // Disable ENS resolution
  wallet.address = wallet.address;

  console.log("Deploying with account:", wallet.address);
  const balance = await provider.getBalance(wallet.address);
  console.log("Balance:", ethers.formatEther(balance), "ETH");

  // Parameters
  const charityWallet = "0x861c0Fab00E75e82CEfAfC5D4390395F45aE4c80";
  const operator = "0x63fb57a83bcbe2243fa4380ef00a79239ee51c3a7c53c2e36dc85ad289cf955b";
  const victimRefundBps = 2000;
  const charityBps = 0;
  const uniswapV3Factory = "0x4200000000000000000000000000000000000010";

  // Read compiled contracts
  const adminArtifact = require("../artifacts/contracts/HalalBotAdmin.sol/HalalBotAdmin.json");
  const implArtifact = require("../artifacts/contracts/HalalBotV1.sol/HalalBotV1.json");
  const proxyArtifact = require("../artifacts/contracts/HalalBotProxy.sol/HalalBotProxy.json");

  console.log("\n=== Step 1: Deploy HalalBotAdmin ===");
  const AdminFactory = new ethers.ContractFactory(adminArtifact.abi, adminArtifact.bytecode, wallet);
  const admin = await AdminFactory.deploy(charityWallet, operator);
  console.log("Transaction hash:", admin.deploymentTransaction().hash);
  await admin.waitForDeployment();
  const adminAddress = await admin.getAddress();
  console.log("HalalBotAdmin deployed to:", adminAddress);

  console.log("\n=== Step 2: Deploy HalalBotV1 (Implementation) ===");
  const ImplFactory = new ethers.ContractFactory(implArtifact.abi, implArtifact.bytecode, wallet);
  const implementation = await ImplFactory.deploy();
  console.log("Transaction hash:", implementation.deploymentTransaction().hash);
  await implementation.waitForDeployment();
  const implAddress = await implementation.getAddress();
  console.log("HalalBotV1 deployed to:", implAddress);

  console.log("\n=== Step 3: Deploy HalalBotProxy ===");
  const ProxyFactory = new ethers.ContractFactory(proxyArtifact.abi, proxyArtifact.bytecode, wallet);
  
  // Encode initializer call
  const implInterface = new ethers.Interface(implArtifact.abi);
  const initializerData = implInterface.encodeFunctionData("initialize", [
    operator,
    adminAddress,
    charityWallet,
    victimRefundBps,
    charityBps,
    uniswapV3Factory,
  ]);

  const proxy = await ProxyFactory.deploy(implAddress, adminAddress, initializerData);
  console.log("Transaction hash:", proxy.deploymentTransaction().hash);
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
  const proxyAsV1 = new ethers.Contract(proxyAddress, implArtifact.abi, wallet);
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
