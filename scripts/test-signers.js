const hre = require("hardhat");

async function main() {
  console.log("Testing Hardhat ethers getSigners()...");
  
  try {
    const signers = await hre.ethers.getSigners();
    console.log("SUCCESS: getSigners() returned", signers.length, "signers");
    console.log("First signer address:", signers[0].address);
    process.exit(0);
  } catch (error) {
    console.error("FAILED: getSigners() error:", error.message);
    console.error("Full error:", error);
    process.exit(1);
  }
}

main();
