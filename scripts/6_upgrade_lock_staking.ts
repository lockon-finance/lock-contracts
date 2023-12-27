import { ethers, network, run, upgrades } from "hardhat";

import { getContracts } from "./utils/deploy-helper";

async function main() {
  const contracts = getContracts(network.name)[network.name];

  const LockStaking = await ethers.getContractFactory("LockStaking");

  //Upgrade proxy
  const lockStaking = await upgrades.upgradeProxy(
    contracts.lockStaking,
    LockStaking
  );
  await lockStaking.waitForDeployment();
  console.log(`Upgraded Lock Staking to ${lockStaking.target}`);

  // Get implementation address to verify
  const implementationAddress = await upgrades.erc1967.getImplementationAddress(
    String(lockStaking.target)
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

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
