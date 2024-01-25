import { ethers, network, run, defender } from "hardhat";

import {getContracts, validateDefenderUpgradeApprovalOwnerAddress} from "./utils/deploy-helper";

async function main() {
  const contracts = getContracts(network.name)[network.name];

  const MerkleAirdrop = await ethers.getContractFactory("MerkleAirdrop");
  await validateDefenderUpgradeApprovalOwnerAddress();

  const proposal = await defender.proposeUpgradeWithApproval(contracts.merkleAirdrop, MerkleAirdrop);

  console.log(`MerkleAirdrop Upgrade proposed with URL: ${proposal.url}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
