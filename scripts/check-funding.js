const hre = require("hardhat");

async function main() {
  console.log("=== Checking Wallet and Contract Funding ===");
  
  const [owner] = await hre.ethers.getSigners();
  console.log("Owner account:", owner.address);

  const proxyAddress = "0xc9C90F18631bc5C4F39EF816a83463A12a218776";
  const operatorAddress = "0xB429057aD392ea5564E47297F49f506039f55200";

  console.log("\n=== Checking Balances ===");
  
  const ownerBalance = await hre.ethers.provider.getBalance(owner.address);
  console.log("Owner balance:", hre.ethers.formatEther(ownerBalance), "ETH");

  const operatorBalance = await hre.ethers.provider.getBalance(operatorAddress);
  console.log("Operator balance:", hre.ethers.formatEther(operatorBalance), "ETH");

  const proxyBalance = await hre.ethers.provider.getBalance(proxyAddress);
  console.log("Proxy contract balance:", hre.ethers.formatEther(proxyBalance), "ETH");

  console.log("\n=== Funding Requirements ===");
  console.log("Proxy contract: Does NOT need ETH balance");
  console.log("  - Flash loans are borrowed from Uniswap V3 pools (zero fee)");
  console.log("  - Only needs ETH for gas when executing transactions");
  console.log("  - Gas is paid by the transaction sender (operator wallet)");
  
  console.log("\nOperator wallet: Needs ETH for gas fees");
  console.log("  - Each backrun execution costs ~0.001-0.01 ETH in gas");
  console.log("  - Should maintain buffer for continuous operation");
  console.log("  - Recommended: 0.1-0.5 ETH buffer on testnet");

  console.log("\n=== Current Configuration ===");
  const abi = [
    'function getAuditConfig() view returns (tuple(uint256 victimRefundBps_, uint256 charityBps_, uint256 operatorBps_, address charityWallet_))'
  ];

  const proxy = new hre.ethers.Contract(proxyAddress, abi, owner);
  const config = await proxy.getAuditConfig();
  
  console.log("Victim Refund BPS:", config.victimRefundBps_.toString(), `(${config.victimRefundBps_.toString() / 100}%)`);
  console.log("Charity BPS:", config.charityBps_.toString(), `(${config.charityBps_.toString() / 100}%)`);
  console.log("Operator BPS:", config.operatorBps_.toString(), `(${config.operatorBps_.toString() / 100}%)`);
  console.log("Charity Wallet:", config.charityWallet_);

  console.log("\n=== Required Configuration Update ===");
  console.log("Current: 20% victim, 0% charity, 80% operator");
  console.log("Target:  15% victim, 5% charity, 80% operator");
  console.log("Action needed: Update charityBps to 500 and victimRefundBps to 1500");
}

main().catch((error) => {
  console.error("FAILED:", error);
  process.exit(1);
});
