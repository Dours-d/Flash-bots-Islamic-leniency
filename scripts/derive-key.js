const { ethers } = require("hardhat");

async function main() {
  const seedPhrase = "iron bone auto dignity judge board boss lyrics negative weird logic rib";
  
  console.log("=== Deriving Private Key from Seed Phrase ===");
  console.log("Seed phrase:", seedPhrase);
  
  const wallet = ethers.Wallet.fromPhrase(seedPhrase);
  console.log("Derived address:", wallet.address);
  console.log("Private key:", wallet.privateKey);
  
  // Verify it matches the operator address
  const operatorAddress = "0xB429057aD392ea5564E47297F49f506039f55200";
  if (wallet.address.toLowerCase() === operatorAddress.toLowerCase()) {
    console.log("✓ Address matches operator wallet");
  } else {
    console.log("✗ Address does NOT match operator wallet");
    console.log("Expected:", operatorAddress);
  }
}

main().catch((error) => {
  console.error("FAILED:", error);
  process.exit(1);
});
