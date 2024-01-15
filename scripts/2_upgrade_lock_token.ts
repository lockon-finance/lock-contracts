import { ethers, network, run, defender } from "hardhat";

import { getContracts } from "./utils/deploy-helper";

async function main() {
  const contracts = getContracts(network.name)[network.name];

  const LockToken = await ethers.getContractFactory("LockToken");

  const proposal = await defender.proposeUpgradeWithApproval(contracts.lockToken, LockToken);

  console.log(`Lock Token Upgrade proposed with URL: ${proposal.url}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
