import { ethers, network, run, upgrades } from "hardhat";

import { getContracts, saveContract } from "./utils/deploy-helper";

async function main() {
  const contracts = getContracts(network.name)[network.name];
  const LockStaking = await ethers.getContractFactory("LockStaking");
  const lockStaking = await upgrades.deployProxy(
    LockStaking,
    [
      contracts.ownerAddress,
      contracts.lockonVesting,
      contracts.feeReceiver,
      contracts.lockToken,
      1700739080, // Staking start timestamp
      BigInt(4 * 10 ** 8) * BigInt(10 ** 18), // Number of lock tokens to use as lock staking reward
      34730, // Basic rate divider
      2900, // Bonus rate per second
    ],
    {
      kind: "uups",
    }
  );
  await lockStaking.waitForDeployment();
  console.log("Lock Staking contract deployed to address:", lockStaking.target);
  saveContract(network.name, "lockStaking", lockStaking.target);

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

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
