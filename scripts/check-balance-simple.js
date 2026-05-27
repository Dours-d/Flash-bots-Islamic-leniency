const { ethers } = require("ethers");
require("dotenv").config();

async function main() {
  const privateKey = process.env.PRIVATE_KEY;
  const sepoliaRpc = process.env.ARBITRUM_SEPOLIA_RPC_URL;
  const mainnetRpc = process.env.ARBITRUM_RPC_URL;
  
  if (!privateKey) {
    console.error("PRIVATE_KEY not found in .env");
    process.exit(1);
  }
  
  const wallet = new ethers.Wallet(privateKey);
  const address = wallet.address;
  
  console.log("Wallet address:", address);
  console.log();
  
  // Check Arbitrum Sepolia
  if (sepoliaRpc) {
    console.log("=== Arbitrum Sepolia ===");
    const sepoliaProvider = new ethers.JsonRpcProvider(sepoliaRpc);
    const sepoliaBalance = await sepoliaProvider.getBalance(address);
    console.log("Balance:", ethers.formatEther(sepoliaBalance), "ETH");
    console.log();
  }
  
  // Check Arbitrum Mainnet
  if (mainnetRpc) {
    console.log("=== Arbitrum Mainnet ===");
    const mainnetProvider = new ethers.JsonRpcProvider(mainnetRpc);
    const mainnetBalance = await mainnetProvider.getBalance(address);
    console.log("Balance:", ethers.formatEther(mainnetBalance), "ETH");
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
