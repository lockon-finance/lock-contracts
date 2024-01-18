import { ethers, network, run, defender } from "hardhat";

import {getContracts, getEnvParams, saveContract} from "./utils/deploy-helper";

async function main() {
  const envParams = getEnvParams();
  const contracts = getContracts(network.name)[network.name];
  const IndexStaking = await ethers.getContractFactory("IndexStaking");

  const upgradeApprovalProcess = await defender.getUpgradeApprovalProcess();

  if (upgradeApprovalProcess.address === undefined) {
    throw new Error(`Upgrade approval process with id ${upgradeApprovalProcess.approvalProcessId} has no assigned address`);
  }

  const timestamp = Math.floor(Date.now() / 1000)
  const indexStaking = await defender.deployProxy(IndexStaking, [
    upgradeApprovalProcess.address,
    envParams.operatorAddress,
    contracts.lockonVesting,
    contracts.lockToken,
    BigInt(2 * 10 ** 9) * BigInt(10 ** 18), // Number of lock tokens to use as index staking reward
    "INDEX_STAKING",
    "1",
    envParams.initialIndexTokenAddresses.map(address => [address, timestamp]), // Initial pool info (Index token address, timestamp)
  ], { initializer: "initialize", kind: "uups" });

  await indexStaking.waitForDeployment();
  const indexStakingAddr = await indexStaking.getAddress();
  console.log("Index Staking contract deployed to address:", indexStakingAddr);
  saveContract(network.name, "indexStaking", indexStakingAddr);
}
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
