const hre = require("hardhat");

async function main() {
  console.log("=== Updating Operator Address ===");
  
  const [deployer] = await hre.ethers.getSigners();
  console.log("Updating with account:", deployer.address);

  const adminAddress = "0x49f52CC81207fC378147288ff696BeD664c227BC";
  const proxyAddress = "0xc9C90F18631bc5C4F39EF816a83463A12a218776";
  const newOperator = "0xB429057aD392ea5564E47297F49f506039f55200";

  console.log("\n=== Connecting to HalalBotAdmin ===");
  const Admin = await hre.ethers.getContractFactory("HalalBotAdmin");
  const admin = Admin.attach(adminAddress);

  console.log("\n=== Connecting to Proxy to check current operator ===");
  const V1 = await hre.ethers.getContractFactory("HalalBotV1");
  const proxy = V1.attach(proxyAddress);
  console.log("Current operator:", await proxy.operator());
  console.log("New operator:", newOperator);

  console.log("\n=== Initiating Operator Update ===");
  const tx = await admin.updateOperator(proxyAddress, newOperator, "Update to correct operator address");
  console.log("Transaction hash:", tx.hash);
  await tx.wait();
  console.log("Operator update completed");

  console.log("\n=== Verifying Update ===");
  console.log("New operator:", await proxy.operator());
}

main().catch((error) => {
  console.error("FAILED:", error);
  process.exit(1);
});
