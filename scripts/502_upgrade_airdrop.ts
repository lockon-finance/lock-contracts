import { ethers, network, run, defender } from "hardhat";

import {getContracts, validateDefenderUpgradeApprovalOwnerAddress} from "./utils/deploy-helper";

async function main() {
  const contracts = getContracts(network.name)[network.name];

  const Airdrop = await ethers.getContractFactory("Airdrop");
  await validateDefenderUpgradeApprovalOwnerAddress();

  const proposal = await defender.proposeUpgradeWithApproval(contracts.airdrop, Airdrop);

  console.log(`Airdrop Upgrade proposed with URL: ${proposal.url}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
