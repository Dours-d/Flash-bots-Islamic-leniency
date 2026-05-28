import { ethers } from 'ethers';
import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
dotenv.config({ path: path.join(__dirname, '../../.env') });

// Configuration
const RPC_URL = process.env.ARBITRUM_SEPOLIA_RPC_URL || 'https://sepolia-rollup.arbitrum.io/rpc';
const PRIVATE_KEY = process.env.PRIVATE_KEY.startsWith('0x') 
  ? process.env.PRIVATE_KEY.slice(2) 
  : process.env.PRIVATE_KEY;
const PROXY_ADDRESS = '0xc9C90F18631bc5C4F39EF816a83463A12a218776';
const UNISWAP_V3_FACTORY = '0x4200000000000000000000000000000000000010';
const READ_ONLY_MODE = true; // Set to false if using operator's private key

// Sandwich attack detection thresholds
const MIN_VALUE_THRESHOLD = ethers.parseEther('0.1'); // 0.1 ETH minimum
const PRICE_IMPACT_THRESHOLD = 50; // 50 basis points (0.5%)

class MempoolScanner {
  constructor() {
    this.provider = new ethers.JsonRpcProvider(RPC_URL);
    this.wallet = new ethers.Wallet(PRIVATE_KEY, this.provider);
    this.proxy = null;
    this.isRunning = false;
  }

  async init() {
    console.log('Initializing Mempool Scanner...');
    console.log('Connected to:', RPC_URL);
    console.log('Scanner address:', this.wallet.address);

    // Load contract ABI
    const abi = [
      'function emitWarning(address indexed target, string reason, bytes data) external',
      'function operator() view returns (address)',
      'function getAuditConfig() view returns (tuple(uint256 victimRefundBps_, uint256 charityBps_, uint256 operatorBps_, address charityWallet_))'
    ];

    this.proxy = new ethers.Contract(PROXY_ADDRESS, abi, this.wallet);

    // Verify operator
    const operator = await this.proxy.operator();
    console.log('Contract operator:', operator);
    console.log('Scanner is operator:', operator.toLowerCase() === this.wallet.address.toLowerCase());

    if (operator.toLowerCase() !== this.wallet.address.toLowerCase()) {
      console.warn('WARNING: Scanner is not the operator. emitWarning calls will fail.');
    }
  }

  async monitorBlocks() {
    console.log('\n=== Starting Block Monitor ===');
    this.isRunning = true;

    let currentBlock = await this.provider.getBlockNumber();
    console.log('Starting from block:', currentBlock);

    const pollInterval = setInterval(async () => {
      if (!this.isRunning) {
        clearInterval(pollInterval);
        return;
      }

      try {
        const latestBlock = await this.provider.getBlockNumber();
        
        if (latestBlock > currentBlock) {
          for (let blockNum = currentBlock + 1; blockNum <= latestBlock; blockNum++) {
            await this.analyzeBlock(blockNum);
          }
          currentBlock = latestBlock;
        }
      } catch (error) {
        console.error('Error polling blocks:', error.message);
      }
    }, 2000); // Poll every 2 seconds

    console.log('Monitoring blocks for sandwich patterns...');
    console.log('Press Ctrl+C to stop');
  }

  async analyzeBlock(blockNumber) {
    try {
      const block = await this.provider.getBlock(blockNumber, true);
      if (!block || !block.transactions) return;

      console.log(`\nAnalyzing block ${blockNumber} (${block.transactions.length} transactions)`);

      for (const tx of block.transactions) {
        await this.analyzeTransaction(tx);
      }
    } catch (error) {
      console.error(`Error analyzing block ${blockNumber}:`, error.message);
    }
  }

  async analyzeTransaction(tx) {
    // Filter for transactions to Uniswap V3 pools
    if (!this.isUniswapInteraction(tx.to)) {
      return;
    }

    // Check transaction value
    if (tx.value && tx.value >= MIN_VALUE_THRESHOLD) {
      console.log(`\n[ALERT] Large transaction detected: ${tx.hash}`);
      console.log(`  To: ${tx.to}`);
      console.log(`  Value: ${ethers.formatEther(tx.value)} ETH`);
      console.log(`  From: ${tx.from}`);

      // Emit warning to contract
      await this.emitWarning(tx.from, 'Large value transaction detected', tx.data);
    }

    // Analyze for sandwich patterns
    if (await this.detectSandwichPattern(tx)) {
      console.log(`\n[SUSPICIOUS] Potential sandwich attack: ${tx.hash}`);
      console.log(`  To: ${tx.to}`);
      console.log(`  From: ${tx.from}`);
      console.log(`  Data: ${tx.data.substring(0, 100)}...`);

      await this.emitWarning(tx.from, 'Potential sandwich attack detected', tx.data);
    }
  }

  isUniswapInteraction(address) {
    // Check if transaction is to a known Uniswap V3 pool
    // In production, this would check against a list of monitored pools
    return address && address.toLowerCase().startsWith('0x');
  }

  async detectSandwichPattern(tx) {
    // Simplified sandwich detection:
    // 1. Look for swap operations
    // 2. Check for multiple transactions from same sender in quick succession
    // 3. Analyze price impact

    if (!tx.data || tx.data.length < 10) return false;

    // Check for Uniswap V3 swap function selector (0x...)
    const swapSelectors = [
      '0x414bf389', // exactInputSingle
      '0xdb3e2198', // exactInput
      '0x09b81346', // exactOutputSingle
      '0x09b81346'  // exactOutput
    ];

    const selector = tx.data.substring(0, 10);
    return swapSelectors.includes(selector);
  }

  async emitWarning(target, reason, data) {
    if (READ_ONLY_MODE) {
      console.log(`  [READ-ONLY] Would emit warning: ${reason}`);
      console.log(`  Target: ${target}`);
      return;
    }

    try {
      const tx = await this.proxy.emitWarning(target, reason, data);
      console.log(`  Warning emitted: ${tx.hash}`);
      await tx.wait();
      console.log(`  Warning confirmed in block`);
    } catch (error) {
      console.error(`  Failed to emit warning: ${error.message}`);
    }
  }

  stop() {
    console.log('\n=== Stopping Scanner ===');
    this.isRunning = false;
    this.provider.removeAllListeners();
  }
}

// Main execution
const scanner = new MempoolScanner();

async function main() {
  try {
    await scanner.init();
    await scanner.monitorBlocks();
  } catch (error) {
    console.error('Scanner error:', error);
    process.exit(1);
  }
}

// Handle graceful shutdown
process.on('SIGINT', () => {
  scanner.stop();
  process.exit(0);
});

process.on('SIGTERM', () => {
  scanner.stop();
  process.exit(0);
});

main();
