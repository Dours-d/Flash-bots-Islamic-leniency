const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules");

module.exports = buildModule("HalalFlashLoanBot", (m) => {
  const charityWallet = m.getParameter("charityWallet", "0x0000000000000000000000000000000000000000");
  const operator = m.getParameter("operator", "0x0000000000000000000000000000000000000000");
  const victimRefundBps = m.getParameter("victimRefundBps", 2000);
  const charityBps = m.getParameter("charityBps", 0);
  
  // Uniswap V3 Factory addresses
  // Arbitrum Sepolia: 0x4200000000000000000000000000000000000010
  // Arbitrum Mainnet: 0x1F98431c8aD98523631AE4a59f267346ea31F984
  const uniswapV3Factory = m.getParameter("uniswapV3Factory", "0x4200000000000000000000000000000000000010");

  // v1.1: Admin constructor now requires both charityWallet AND operator
  // Operator must differ from deployer (owner) to prevent single point of failure
  const admin = m.contract("HalalBotAdmin", [charityWallet, operator]);
  const implementation = m.contract("HalalBotV1");
  
  const deployer = m.getAccount(0);
  
  const initializerData = m.encodeFunctionCall(implementation, "initialize", [
    operator,
    admin,
    charityWallet,
    victimRefundBps,
    charityBps,
    uniswapV3Factory,
  ]);

  const proxy = m.contract("HalalBotProxy", [
    implementation,
    admin,
    initializerData,
  ]);

  return { admin, implementation, proxy };
});
