import { ethers, network, run, defender } from "hardhat";

import { getContracts, saveContract } from "./utils/deploy-helper";

async function main() {
  const contracts = getContracts(network.name)[network.name];

  const LockToken = await ethers.getContractFactory("LockToken");
  const upgradeApprovalProcess = await defender.getUpgradeApprovalProcess();

  if (upgradeApprovalProcess.address === undefined) {
    throw new Error(`Upgrade approval process with id ${upgradeApprovalProcess.approvalProcessId} has no assigned address`);
  }

  const lockToken = await defender.deployProxy(LockToken, [
    "LockToken",
    "LOCK",
    upgradeApprovalProcess.address, // multisig address
    contracts.operatorAddress,
  ], { initializer: "initialize", kind: "uups" });

  await lockToken.waitForDeployment();
  console.log("Lock Token contract deployed to address:", await lockToken.getAddress());
  saveContract(network.name, "lockToken", await lockToken.getAddress());
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
