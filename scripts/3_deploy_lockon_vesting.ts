import { ethers, network, run, upgrades } from "hardhat";

import { saveContract } from "./utils/deploy-helper";

async function main() {
  const LockonVesting = await ethers.getContractFactory("LockonVesting");
  const lockonVesting = await upgrades.deployProxy(LockonVesting, []);

  await lockonVesting.deployed();
  console.log(
    "Lockon Vesting contract deployed to address:",
    lockonVesting.target
  );
  saveContract(network.name, "lockonVesting", lockonVesting.target);

  // Get implementation address to verify
  const implementationAddress = await upgrades.erc1967.getImplementationAddress(
    String(lockonVesting.target)
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
