import { ethers, network, run, upgrades } from "hardhat";

import { getContracts } from "./utils/deploy-helper";

async function main() {
  const contracts = getContracts(network.name)[network.name];

  const IndexStaking = await ethers.getContractFactory("IndexStaking");

  //Upgrade proxy
  const indexStaking = await upgrades.upgradeProxy(
    contracts.indexStaking,
    IndexStaking
  );
  await indexStaking.waitForDeployment();
  console.log(`Upgraded Index Staking to ${indexStaking.target}`);

  // Get implementation address to verify
  const implementationAddress = await upgrades.erc1967.getImplementationAddress(
    String(indexStaking.target)
  );
  console.log("Implementation contract address:", implementationAddress);

  setTimeout(async () => {
    await run("verify:verify", {
      address: implementationAddress,
      constructorArguments: [],
    });
    console.log(`Complete!`);
  }, 10000);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
