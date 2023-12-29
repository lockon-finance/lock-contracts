import { ethers, network, run, upgrades } from "hardhat";

import { getContracts, saveContract } from "./utils/deploy-helper";

async function main() {
  const contracts = getContracts(network.name)[network.name];
  const IndexStaking = await ethers.getContractFactory("IndexStaking");
  const indexStaking = await upgrades.deployProxy(
    IndexStaking,
    [
      contracts.ownerAddress,
      contracts.operatorAddress,
      contracts.lockonVesting,
      contracts.lockToken,
      BigInt(2 * 10 ** 9) * BigInt(10 ** 18), // Number of lock tokens to use as index staking reward
      "INDEX_STAKING", 
      "1",
      [
        [contracts.LPIToken, 0, Math.floor(Date.now() / 1000)], // First pool info
        [contracts.LBIToken, 0, Math.floor(Date.now() / 1000)]
      ], // Second pool info
    ],
    {
      kind: "uups",
    }
  );

  await indexStaking.waitForDeployment();
  console.log(
    "Index Staking contract deployed to address:",
    indexStaking.target
  );
  saveContract(network.name, "indexStaking", indexStaking.target);

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

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
