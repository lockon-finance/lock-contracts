import { ethers, network, run, defender } from "hardhat";

import { getContracts, saveContract } from "./utils/deploy-helper";

async function main() {
  const contracts = getContracts(network.name)[network.name];
  const IndexStaking = await ethers.getContractFactory("IndexStaking");

  const upgradeApprovalProcess = await defender.getUpgradeApprovalProcess();

  if (upgradeApprovalProcess.address === undefined) {
    throw new Error(`Upgrade approval process with id ${upgradeApprovalProcess.approvalProcessId} has no assigned address`);
  }

  const indexStaking = await defender.deployProxy(IndexStaking, [
    upgradeApprovalProcess.address,
    upgradeApprovalProcess.address,
    contracts.lockonVesting,
    contracts.lockToken,
    BigInt(2 * 10 ** 9) * BigInt(10 ** 18), // Number of lock tokens to use as index staking reward
    "INDEX_STAKING", 
    "1",
    [
      [contracts.LPIToken, Math.floor(Date.now() / 1000)], // First pool info
      [contracts.LBIToken, Math.floor(Date.now() / 1000)] // Second pool info
    ], 
  ], { initializer: "initialize", kind: "uups" });

  await indexStaking.waitForDeployment();
  const indexStakingAddr = await indexStaking.getAddress();
  console.log("Index Staking contract deployed to address:", indexStakingAddr);
  saveContract(network.name, "indexStaking", indexStakingAddr);
}
// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
