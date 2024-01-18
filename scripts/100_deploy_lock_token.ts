import { ethers, network, run, defender } from "hardhat";

import {getContracts, getEnvParams, saveContract} from "./utils/deploy-helper";

async function main() {
  const envParams = getEnvParams();
  const contracts = getContracts(network.name)[network.name];

  const LockToken = await ethers.getContractFactory("LockToken");
  const upgradeApprovalProcess = await defender.getUpgradeApprovalProcess();

  if (upgradeApprovalProcess.address === undefined) {
    throw new Error(`Upgrade approval process with id ${upgradeApprovalProcess.approvalProcessId} has no assigned address`);
  }

  const lockToken = await defender.deployProxy(LockToken, [
    envParams.lockTokenName,
    envParams.lockTokenSymbol,
    upgradeApprovalProcess.address, // multisig address
    envParams.operatorAddress,
  ], { initializer: "initialize", kind: "uups"});

  await lockToken.waitForDeployment();
  const lockTokenAddr = await lockToken.getAddress();
  console.log("Lock Token contract deployed to address:", lockTokenAddr);
  saveContract(network.name, "lockToken", lockTokenAddr);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
