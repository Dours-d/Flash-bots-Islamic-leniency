import { ethers } from 'ethers';
import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
dotenv.config({ path: path.join(__dirname, '../../.env') });

const RPC_URL = process.env.ARBITRUM_SEPOLIA_RPC_URL || 'https://sepolia-rollup.arbitrum.io/rpc';
const PRIVATE_KEY = process.env.PRIVATE_KEY.startsWith('0x') 
  ? process.env.PRIVATE_KEY.slice(2) 
  : process.env.PRIVATE_KEY;
const PROXY_ADDRESS = '0xc9C90F18631bc5C4F39EF816a83463A12a218776';

async function testConnection() {
  console.log('=== Testing Scanner Connection ===\n');

  const provider = new ethers.JsonRpcProvider(RPC_URL);
  const wallet = new ethers.Wallet(PRIVATE_KEY, provider);

  console.log('RPC URL:', RPC_URL);
  console.log('Wallet address:', wallet.address);
  console.log('Balance:', ethers.formatEther(await provider.getBalance(wallet.address)), 'ETH');

  const abi = [
    'function operator() view returns (address)',
    'function getAuditConfig() view returns (tuple(uint256 victimRefundBps_, uint256 charityBps_, uint256 operatorBps_, address charityWallet_))'
  ];

  const proxy = new ethers.Contract(PROXY_ADDRESS, abi, wallet);

  console.log('\n=== Contract Info ===');
  console.log('Proxy address:', PROXY_ADDRESS);
  const operator = await proxy.operator();
  console.log('Operator:', operator);
  console.log('Is scanner operator:', operator.toLowerCase() === wallet.address.toLowerCase());

  const config = await proxy.getAuditConfig();
  console.log('\n=== Configuration ===');
  console.log('Victim Refund BPS:', config.victimRefundBps_.toString());
  console.log('Charity BPS:', config.charityBps_.toString());
  console.log('Operator BPS:', config.operatorBps_.toString());
  console.log('Charity Wallet:', config.charityWallet_);

  console.log('\n=== Test Complete ===');
}

testConnection().catch(console.error);
