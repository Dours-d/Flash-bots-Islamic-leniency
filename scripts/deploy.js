const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules");

module.exports = buildModule("HalalFlashLoanBot", (m) => {
  const charityWallet = m.getParameter("charityWallet", "0x0000000000000000000000000000000000000000");
  const victimRefundBps = m.getParameter("victimRefundBps", 2000);
  const charityBps = m.getParameter("charityBps", 0);

  const admin = m.contract("HalalBotAdmin", [charityWallet]);
  const implementation = m.contract("HalalBotV1");
  
  const deployer = m.getAccount(0);
  
  const initializerData = m.encodeFunctionCall(implementation, "initialize", [
    deployer,
    admin,
    charityWallet,
    victimRefundBps,
    charityBps,
  ]);

  const proxy = m.contract("HalalBotProxy", [
    implementation,
    admin,
    initializerData,
  ]);

  return { admin, implementation, proxy };
});
