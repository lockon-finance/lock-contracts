import { ethers, network, run, upgrades } from "hardhat";

import { getContracts, saveContract } from "./utils/deploy-helper";

async function main() {
  const contracts = getContracts(network.name)[network.name];

  const LockToken = await ethers.getContractFactory("LockToken");
  const lockToken = await upgrades.deployProxy(LockToken, [
    "LockToken",
    "LOCK",
    contracts.ownerAddress,
    contracts.operatorAddress,
  ]);

  await lockToken.waitForDeployment();
  console.log("Lock Token contract deployed to address:", lockToken.target);
  saveContract(network.name, "lockToken", lockToken.target);

  // Get implementation address to verify
  const implementationAddress = await upgrades.erc1967.getImplementationAddress(
    String(lockToken.target)
  );
  console.log("Implementation contract address:", implementationAddress);

  await run("verify:verify", {
    address: implementationAddress,
    constructorArguments: [],
  });

  console.log(`Complete!`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
