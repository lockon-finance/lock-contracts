import { ethers, network, defender } from "hardhat";

import {getContracts, saveContract, getEnvParams, getDefenderUpgradeApprovalOwnerAddress} from "./utils/deploy-helper";

async function main() {
  const contracts = getContracts(network.name)[network.name];
  if (contracts.merkleAirdrop) {
    throw new Error("MerkleAirdrop contract already deployed");
  }

  const envParams = getEnvParams();
  const ownerAddress = await getDefenderUpgradeApprovalOwnerAddress();

  const MerkleAirdrop = await ethers.getContractFactory("MerkleAirdrop");
  const startTimestamp = Math.floor(Date.now() / 1000)
  const merkleAirdrop = await defender.deployProxy(
    MerkleAirdrop,
    [
      ownerAddress,
      contracts.lockonVesting,
      contracts.lockToken,
      envParams.merkleRoot,
      startTimestamp, // Airdrop start timestamp
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
