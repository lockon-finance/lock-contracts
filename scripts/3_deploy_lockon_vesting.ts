import { ethers, network, run, upgrades } from "hardhat";

import { getContracts, saveContract } from "./utils/deploy-helper";

async function main() {
  const contracts = getContracts(network.name)[network.name];

  const LockonVesting = await ethers.getContractFactory("LockonVesting");
  const lockonVesting = await upgrades.deployProxy(
    LockonVesting,
    [contracts.ownerAddress, contracts.lockToken],
    {
      kind: "uups",
    }
  );

  await lockonVesting.waitForDeployment();
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

  setTimeout(async () => {
    await run("verify:verify", {
      address: implementationAddress,
      constructorArguments: [],
    });
    console.log(`Complete!`);
  }, 10000);

}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
