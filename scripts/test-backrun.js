const hre = require("hardhat");

async function main() {
  console.log("=== Testing executeBackrun ===");
  
  // Operator wallet from seed phrase
  const operatorPrivateKey = "0x63fb57a83bcbe2243fa4380ef00a79239ee51c3a7c53c2e36dc85ad289cf955b";
  const operator = new hre.ethers.Wallet(operatorPrivateKey, hre.ethers.provider);
  
  console.log("Operator address:", operator.address);
  console.log("Operator balance:", hre.ethers.formatEther(await hre.ethers.provider.getBalance(operator.address)), "ETH");

  // Contract addresses
  const PROXY_ADDRESS = "0x148699471b17D1Bf895D0e68ecC4eD4C277cd3Af";
  const WETH_ADDRESS = "0x4200000000000000000000000000000000000006";
  const USDC_ADDRESS = "0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d";
  const POOL_ADDRESS = "0x31b4e4452c843c6a6705e3878434230553c64393";
  
  // Victim transaction hash
  const victimTx = "0x900fd4b1198dd6e15464a5afb338bbf1d9f9b350eaebcd513d4500fdeb50ca48";
  
  // Backrun parameters
  const borrowAmount0 = hre.ethers.parseEther("0.001"); // 0.001 WETH to borrow (smaller amount)
  const borrowAmount1 = 0; // Not borrowing USDC
  const feeTier = 500; // 0.05% fee tier
  const minProfit = 0; // No minimum profit for test
  const victimAddress = "0x2EDBF113E633430eD1ba776F961da2D06AAb7735"; // Owner wallet as victim
  
  // Encode callback data with FlashCallbackData struct
  const FlashCallbackData = [
    "address",  // victim
    "bytes32",  // targetTxHash
    "address",  // tokenBorrow
    "address",  // tokenArb
    "address",  // poolBuy
    "address",  // poolSell
    "uint24",   // feeTier
    "uint256",  // amountBorrowed
    "uint256",  // minProfit
    "bool"      // warningWasAttempted
  ];
  
  const callbackData = hre.ethers.AbiCoder.defaultAbiCoder().encode(
    FlashCallbackData,
    [
      victimAddress,   // victim
      victimTx,        // targetTxHash
      WETH_ADDRESS,    // tokenBorrow
      USDC_ADDRESS,    // tokenArb
      POOL_ADDRESS,    // poolBuy
      POOL_ADDRESS,    // poolSell (same pool for single-pool arbitrage)
      feeTier,         // feeTier
      borrowAmount0,   // amountBorrowed
      minProfit,       // minProfit
      true             // warningWasAttempted
    ]
  );
  
  console.log("\n=== Backrun Parameters ===");
  console.log("Flash Pool:", POOL_ADDRESS);
  console.log("Borrow Amount 0 (WETH):", hre.ethers.formatEther(borrowAmount0), "WETH");
  console.log("Borrow Amount 1 (USDC):", borrowAmount1);
  console.log("Victim Tx:", victimTx);
  console.log("Victim Address:", victimAddress);
  console.log("Fee Tier:", feeTier);
  console.log("Min Profit:", hre.ethers.formatEther(minProfit), "ETH");

  // Load contract
  const HalalBotV1 = await hre.ethers.getContractFactory("HalalBotV1");
  const proxy = HalalBotV1.attach(PROXY_ADDRESS).connect(operator);

  console.log("\n=== Executing Backrun ===");
  try {
    const tx = await proxy.executeBackrun(
      POOL_ADDRESS,    // flashPool
      callbackData,    // callbackData (encoded swap params)
      borrowAmount0,    // borrowAmount0 (WETH)
      borrowAmount1     // borrowAmount1 (USDC - 0)
    );
    console.log("Transaction hash:", tx.hash);
    const receipt = await tx.wait();
    console.log("Backrun complete");
    console.log("Gas used:", receipt.gasUsed.toString());
    
    // Parse events
    console.log("\n=== Events ===");
    for (const log of receipt.logs) {
      try {
        const parsed = proxy.interface.parseLog(log);
        if (parsed) {
          console.log(`Event: ${parsed.name}`);
          console.log("Args:", parsed.args);
        }
      } catch (e) {
        // Skip logs that don't match our interface
      }
    }
  } catch (error) {
    console.error("Backrun failed:", error.message);
    if (error.reason) {
      console.error("Reason:", error.reason);
    }
    if (error.data) {
      console.error("Error data:", error.data);
    }
    console.error("\nFull error:", error);
  }
}

main().catch((error) => {
  console.error("FAILED:", error);
  process.exit(1);
});
