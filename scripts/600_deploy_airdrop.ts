import { ethers, network, run, defender } from "hardhat";

import {getContracts, saveContract, getDefenderUpgradeApprovalOwnerAddress} from "./utils/deploy-helper";

async function main() {
  const contracts = getContracts(network.name)[network.name];
  const Airdrop = await ethers.getContractFactory("Airdrop");
  const ownerAddress = await getDefenderUpgradeApprovalOwnerAddress();

  const startTimestamp = Math.floor(Date.now() / 1000);
  const airdrop = await defender.deployProxy(
    Airdrop,
    [
      ownerAddress,
      contracts.lockonVesting,
      contracts.lockToken,
      startTimestamp, // Airdrop start timestamp
    ],
    {
      initializer: "initialize",
      kind: "uups",
    }
  );
  await airdrop.waitForDeployment();
  const airdropAddr = await airdrop.getAddress();
  console.log("Airdrop contract deployed to address:", airdropAddr);
  saveContract(network.name, "airdrop", airdropAddr);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
