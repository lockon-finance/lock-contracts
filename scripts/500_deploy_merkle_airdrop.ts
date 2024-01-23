import { ethers, network, defender } from "hardhat";

import { getContracts, saveContract, getEnvParams } from "./utils/deploy-helper";

async function main() {
  const contracts = getContracts(network.name)[network.name];
  const envParams = getEnvParams();
  const upgradeApprovalProcess = await defender.getUpgradeApprovalProcess();

  if (upgradeApprovalProcess.address === undefined) {
    throw new Error(
      `Upgrade approval process with id ${upgradeApprovalProcess.approvalProcessId} has no assigned address`
    );
  }
  const MerkleAirdrop = await ethers.getContractFactory("MerkleAirdrop");
  const merkleAirdrop = await defender.deployProxy(
    MerkleAirdrop,
    [
      upgradeApprovalProcess.address,
      contracts.lockonVesting,
      contracts.lockToken,
      envParams.merkleRoot,
      1705739080, // Airdrop start timestamp
    ],
    {
      initializer: "initialize",
      kind: "uups",
    }
  );
  await merkleAirdrop.waitForDeployment();
  const merkleAirdropAddr = await merkleAirdrop.getAddress();
  console.log("Merkle Airdrop contract deployed to address:", merkleAirdropAddr);
  saveContract(network.name, "merkleAirdrop", merkleAirdropAddr);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
