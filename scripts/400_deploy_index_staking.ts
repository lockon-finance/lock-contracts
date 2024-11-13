import { ethers, network, run, defender } from "hardhat";

import {
  getContracts,
  getEnvParams,
  saveContract,
  getDefenderUpgradeApprovalOwnerAddress,
} from "./utils/deploy-helper";

async function main() {
  const envParams = getEnvParams();
  const contracts = getContracts(network.name)[network.name];
  if (contracts.indexStaking) {
    throw new Error("IndexStaking contract already deployed");
  }

  const IndexStaking = await ethers.getContractFactory("IndexStaking");
  const ownerAddress = await getDefenderUpgradeApprovalOwnerAddress();
  const startTimestamp = Math.floor(Date.now() / 1000);
  const bonusRatePerSecond = 2300; // (decimals=1e12)
  const indexStaking = await defender.deployProxy(
    IndexStaking,
    [
      ownerAddress,
      envParams.operatorAddress,
      contracts.lockonVesting,
      contracts.lockToken,
      BigInt(2 * 10 ** 9) * BigInt(10 ** 18), // Number of lock tokens to use as index staking reward
      "INDEX_STAKING",
      "1",
      // Initial pool info (Index token address, bonusRatePerSecond, startTimestamp, vestingCategoryId)
      envParams.initialIndexTokenAddresses.map((address, index) => [
        address,
        bonusRatePerSecond,
        startTimestamp,
        envParams.initialIndexTokenVestingCategoryIds[index],
      ]),
    ],
    { initializer: "initialize", kind: "uups" },
  );

  await indexStaking.waitForDeployment();
  const indexStakingAddr = await indexStaking.getAddress();
  console.log("Index Staking contract deployed to address:", indexStakingAddr);
  saveContract(network.name, "indexStaking", indexStakingAddr);
}
main().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
