import { ethers, network, run, defender } from "hardhat";

import { getContracts, saveContract } from "./utils/deploy-helper";

async function main() {
  const contracts = getContracts(network.name)[network.name];
  const LockStaking = await ethers.getContractFactory("LockStaking");

  const upgradeApprovalProcess = await defender.getUpgradeApprovalProcess();

  if (upgradeApprovalProcess.address === undefined) {
    throw new Error(`Upgrade approval process with id ${upgradeApprovalProcess.approvalProcessId} has no assigned address`);
  }

  const lockStaking = await defender.deployProxy(LockStaking, [
    upgradeApprovalProcess.address,
    upgradeApprovalProcess.address,
    contracts.lockonVesting,
    contracts.feeReceiver,
    contracts.lockToken,
    1700739080, // Staking start timestamp
    BigInt(4 * 10 ** 8) * BigInt(10 ** 18), // Number of lock tokens to use as lock staking reward
    34730, // Basic rate divider
    2900, // Bonus rate per second
  ], { initializer: "initialize", kind: "uups" });

  await lockStaking.waitForDeployment();
  const lockStakingAddr = await lockStaking.getAddress();
  console.log("Lock Staking contract deployed to address:", lockStakingAddr);
  saveContract(network.name, "lockStaking", lockStakingAddr);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
