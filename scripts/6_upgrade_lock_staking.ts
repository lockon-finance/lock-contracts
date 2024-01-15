import { ethers, network, run, defender } from "hardhat";

import { getContracts } from "./utils/deploy-helper";

async function main() {
  const contracts = getContracts(network.name)[network.name];

  const LockStaking = await ethers.getContractFactory("LockStaking");

  const proposal = await defender.proposeUpgradeWithApproval(contracts.lockStaking, LockStaking);

  console.log(`Lock Staking Upgrade proposed with URL: ${proposal.url}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
