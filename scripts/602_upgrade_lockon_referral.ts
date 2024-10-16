import { ethers, network, defender } from "hardhat";

import {getContracts, validateDefenderUpgradeApprovalOwnerAddress} from "./utils/deploy-helper";

async function main() {
  const contracts = getContracts(network.name)[network.name];

  const LockonReferral = await ethers.getContractFactory("LockonReferral");
  await validateDefenderUpgradeApprovalOwnerAddress();

  const proposal = await defender.proposeUpgradeWithApproval(contracts.lockonReferral, LockonReferral);

  console.log(`Lockon Referral Upgrade proposed with URL: ${proposal.url}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});