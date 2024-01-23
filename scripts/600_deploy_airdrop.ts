import { ethers, network, run, defender } from "hardhat";

import { getContracts, saveContract } from "./utils/deploy-helper";

async function main() {
  const contracts = getContracts(network.name)[network.name];
  const Airdrop = await ethers.getContractFactory("Airdrop");
  const upgradeApprovalProcess = await defender.getUpgradeApprovalProcess();

  if (upgradeApprovalProcess.address === undefined) {
    throw new Error(
      `Upgrade approval process with id ${upgradeApprovalProcess.approvalProcessId} has no assigned address`
    );
  }
  const airdrop = await defender.deployProxy(
    Airdrop,
    [
      upgradeApprovalProcess.address,
      contracts.lockonVesting,
      contracts.lockToken,
      1705739080, // Staking start timestamp
    ],
    {
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
