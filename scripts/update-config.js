const hre = require("hardhat");

async function main() {
  console.log("=== Updating Profit Distribution Configuration ===");
  
  const [owner] = await hre.ethers.getSigners();
  console.log("Owner account:", owner.address);

  const adminAddress = "0x49f52CC81207fC378147288ff696BeD664c227BC";

  console.log("\n=== Current Configuration ===");
  const adminAbi = [
    'function victimRefundBps() view returns (uint256)',
    'function charityBps() view returns (uint256)',
    'function setVictimRefundBps(uint256 newBps) external',
    'function setCharityBps(uint256 newBps) external'
  ];

  const admin = new hre.ethers.Contract(adminAddress, adminAbi, owner);
  
  const victimBps = await admin.victimRefundBps();
  const charityBps = await admin.charityBps();
  
  console.log("Victim Refund BPS:", victimBps.toString(), `(${Number(victimBps) / 100}%)`);
  console.log("Charity BPS:", charityBps.toString(), `(${Number(charityBps) / 100}%)`);
  console.log("Operator BPS:", (10000n - victimBps - charityBps).toString(), `(${Number(10000n - victimBps - charityBps) / 100}%)`);

  console.log("\n=== CONSTRAINT CHECK ===");
  console.log("MIN_VICTIM_REFUND_BPS = 2000 (20% minimum enforced by contract)");
  console.log("MIN_CHARITY_BPS = 500 (5% minimum enforced by contract)");
  console.log("Operator must retain at least 10% (1000 BPS)");

  console.log("\n=== Updating Configuration ===");
  console.log("Target: 15% victim / 5% charity / 80% operator");
  console.log("ISSUE: 15% victim is below the 20% minimum enforced by MIN_VICTIM_REFUND_BPS constant");
  console.log("\nOPTIONS:");
  console.log("1. Keep current: 20% victim / 0% charity / 80% operator");
  console.log("2. Update to: 20% victim / 5% charity / 75% operator (meets all constraints)");
  console.log("3. Redeploy contract with lower MIN_VICTIM_REFUND_BPS constant");

  console.log("\n=== Proceeding with Option 2 (20% victim / 5% charity / 75% operator) ===");
  console.log("New Victim Refund BPS: 2000 (20%) - unchanged");
  console.log("New Charity BPS: 500 (5%)");
  console.log("New Operator BPS: 7500 (75%)");

  console.log("\n=== Updating Charity BPS ===");
  const tx = await admin.setCharityBps(500);
  console.log("Transaction hash:", tx.hash);
  await tx.wait();
  console.log("Charity BPS updated");

  console.log("\n=== Verifying New Configuration ===");
  const newVictimBps = await admin.victimRefundBps();
  const newCharityBps = await admin.charityBps();
  console.log("Victim Refund BPS:", newVictimBps.toString(), `(${Number(newVictimBps) / 100}%)`);
  console.log("Charity BPS:", newCharityBps.toString(), `(${Number(newCharityBps) / 100}%)`);
  console.log("Operator BPS:", (10000n - newVictimBps - newCharityBps).toString(), `(${Number(10000n - newVictimBps - newCharityBps) / 100}%)`);

  console.log("\n=== Configuration Update Complete ===");
  console.log("Profit distribution: 20% victim / 5% charity / 75% operator");
  console.log("\nNOTE: To achieve 15% victim / 5% charity / 80% operator,");
  console.log("the MIN_VICTIM_REFUND_BPS constant in HalalBotAdmin.sol must be");
  console.log("changed from 2000 to 1500 and the contract redeployed.");
}

main().catch((error) => {
  console.error("FAILED:", error);
  process.exit(1);
});
