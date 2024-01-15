import { ethers, network, run, upgrades } from "hardhat";

import { getContracts } from "./utils/deploy-helper";

async function main() {
  const contracts = getContracts(network.name)[network.name];

  const LockonVesting = await ethers.getContractFactory("LockonVesting");

  //Upgrade proxy
  const lockonVesting = await upgrades.upgradeProxy(
    contracts.lockonVesting,
    LockonVesting
  );
  await lockonVesting.waitForDeployment();
  console.log(`Upgraded Lockon Vesting to ${lockonVesting.target}`);

  // Get implementation address to verify
  const implementationAddress = await upgrades.erc1967.getImplementationAddress(
    String(lockonVesting.target)
  );
  console.log("Implementation contract address:", implementationAddress);

  setTimeout(async () => {
    await run("verify:verify", {
      address: implementationAddress,
      constructorArguments: [],
    });
    console.log("Completed!");
  }, 10000);

}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
