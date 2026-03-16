import { ethers, network, run, upgrades } from "hardhat";

import { getContracts, getEnvParams, saveContract } from "./utils/deploy-helper";

async function main() {
  const envParams = getEnvParams();
  const contracts = getContracts(network.name)[network.name];
  if (contracts.lockToken) {
    throw new Error("LockToken contract already deployed");
  }

  const LockToken = await ethers.getContractFactory("LockToken");
  const ownerAddress = envParams.ownerAddress;

  const lockToken = await upgrades.deployProxy(
    LockToken,
    [envParams.lockTokenName, envParams.lockTokenSymbol, ownerAddress, envParams.managementAddress],
    { initializer: "initialize", kind: "uups" },
  );

  await lockToken.waitForDeployment();
  const lockTokenAddr = await lockToken.getAddress();
  console.log("Lock Token contract deployed to address:", lockTokenAddr);
  saveContract(network.name, "lockToken", lockTokenAddr);
}

main().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
