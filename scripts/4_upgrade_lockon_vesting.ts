import { ethers, network, run, defender } from "hardhat";

import { getContracts } from "./utils/deploy-helper";

async function main() {
  const contracts = getContracts(network.name)[network.name];

  const LockonVesting = await ethers.getContractFactory("LockonVesting");

  const proposal = await defender.proposeUpgradeWithApproval(contracts.lockonVesting, LockonVesting);

  console.log(`Lockon Vesting Upgrade proposed with URL: ${proposal.url}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
