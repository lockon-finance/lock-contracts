import { ethers, network, run, defender } from "hardhat";

import { getContracts, getEnvParams, validateDefenderUpgradeApprovalOwnerAddress } from "./utils/deploy-helper";

async function main() {
  const envParams = getEnvParams();
  const contracts = getContracts(network.name)[network.name];

  const IndexStaking = await ethers.getContractFactory("IndexStaking");
  await validateDefenderUpgradeApprovalOwnerAddress();

  const proposal = await defender.proposeUpgradeWithApproval(contracts.indexStaking, IndexStaking);

  console.log(`Index Staking Upgrade proposed with URL: ${proposal.url}`);
}

main().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
