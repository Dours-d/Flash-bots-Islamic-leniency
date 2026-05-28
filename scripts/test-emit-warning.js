const hre = require("hardhat");

async function main() {
  console.log("=== Testing emitWarning Function ===");
  
  const [deployer] = await hre.ethers.getSigners();
  console.log("Testing with account:", deployer.address);

  const proxyAddress = "0xc9C90F18631bc5C4F39EF816a83463A12a218776";

  // Load contract ABI
  const abi = [
    'function emitWarning(address indexed target, string reason, bytes data) external',
    'function operator() view returns (address)'
  ];

  const proxy = new hre.ethers.Contract(proxyAddress, abi, deployer);

  console.log("\n=== Checking Operator ===");
  const operator = await proxy.operator();
  console.log("Contract operator:", operator);
  console.log("Current account:", deployer.address);
  console.log("Is operator:", operator.toLowerCase() === deployer.address.toLowerCase());

  if (operator.toLowerCase() !== deployer.address.toLowerCase()) {
    console.log("\n=== Cannot test emitWarning ===");
    console.log("Current account is not the operator.");
    console.log("To test emitWarning, use the operator's private key:", operator);
    console.log("\nThe emitWarning function is implemented in HalalBotV1.sol");
    console.log("It can be called by the operator to log warnings about suspicious activity.");
    return;
  }

  console.log("\n=== Testing emitWarning ===");
  const target = "0x0000000000000000000000000000000000000001";
  const reason = "Test warning from deployment script";
  const data = "0x1234";

  try {
    const tx = await proxy.emitWarning(target, reason, data);
    console.log("Transaction hash:", tx.hash);
    await tx.wait();
    console.log("Warning emitted successfully!");
  } catch (error) {
    console.error("Failed to emit warning:", error.message);
  }
}

main().catch((error) => {
  console.error("FAILED:", error);
  process.exit(1);
});
