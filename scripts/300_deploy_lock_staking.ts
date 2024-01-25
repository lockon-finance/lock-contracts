import { ethers, network, run, defender } from "hardhat";

import {getContracts, getEnvParams, saveContract, getDefenderUpgradeApprovalOwnerAddress} from "./utils/deploy-helper";

async function main() {
  const envParams = getEnvParams();
  const contracts = getContracts(network.name)[network.name];
  const LockStaking = await ethers.getContractFactory("LockStaking");
  const ownerAddress = await getDefenderUpgradeApprovalOwnerAddress();

  const startTimestamp = Math.floor(Date.now() / 1000)
  const lockStaking = await defender.deployProxy(LockStaking, [
    ownerAddress,
    envParams.operatorAddress,
    contracts.lockonVesting,
    envParams.feeReceiverAddress,
    contracts.lockToken,
    startTimestamp, // Staking start timestamp
    BigInt(4 * 10 ** 8) * BigInt(10 ** 18), // Number of lock tokens to use as lock staking reward
    34730, // Basic rate divider(decimals=1e12)
    2900, // Bonus rate per second(decimals=1e12)
  ], { initializer: "initialize", kind: "uups" });

  await lockStaking.waitForDeployment();
  const lockStakingAddr = await lockStaking.getAddress();
  console.log("Lock Staking contract deployed to address:", lockStakingAddr);
  saveContract(network.name, "lockStaking", lockStakingAddr);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
