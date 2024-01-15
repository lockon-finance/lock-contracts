import { ethers, network, run, upgrades } from "hardhat";

import { getContracts } from "./utils/deploy-helper";

async function main() {
  const contracts = getContracts(network.name)[network.name];

  const LockToken = await ethers.getContractFactory("LockToken");

  //Upgrade proxy
  const lockToken = await upgrades.upgradeProxy(contracts.lockToken, LockToken);
  await lockToken.waitForDeployment();
  console.log(`Upgraded Lock Token to ${lockToken.target}`);

  // Get implementation address to verify
  const implementationAddress = await upgrades.erc1967.getImplementationAddress(
    String(lockToken.target)
  );
  console.log("Implementation contract address:", implementationAddress);

  await run("verify:verify", {
    address: implementationAddress,
    constructorArguments: [],
  });

  console.log("Completed!");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
