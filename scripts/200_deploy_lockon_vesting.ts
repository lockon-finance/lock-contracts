import { ethers, network, run, upgrades, defender } from "hardhat";

import {getContracts, getEnvParams, saveContract, getDefenderUpgradeApprovalOwnerAddress} from "./utils/deploy-helper";

const SECONDS_PER_DAY = 86400;

async function main() {
  const envParams = getEnvParams();
  const contracts = getContracts(network.name)[network.name];
  if (contracts.lockonVesting) {
    throw new Error("LockonVesting contract already deployed");
  }

  const LockonVesting = await ethers.getContractFactory("LockonVesting");
  const ownerAddress = await getDefenderUpgradeApprovalOwnerAddress();

  /**
   * 0: LOCK STAKING
   * 2: AIRDROP
   * 3-22: INDEX STAKING
   * 10000: LOCKON REFERRAL (investor)
   * 10001: LOCKON REFERRAL (affiliate)
   * 10002: LOCKON REFERRAL (special)
   */
  const categoryIds = [
    0, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21,
    22, 10000, 10001, 10002,
  ];
  const vestingPeriods = Array(categoryIds.length).fill(300 * SECONDS_PER_DAY);
  const lockonVesting = await defender.deployProxy(
    LockonVesting,
    [ownerAddress, contracts.lockToken, categoryIds, vestingPeriods],
    { initializer: "initialize", kind: "uups" }
  );
  await lockonVesting.waitForDeployment();
  const lockonVestingAddr = await lockonVesting.getAddress();
  console.log(
    "Lockon Vesting contract deployed to address:",
    lockonVestingAddr
  );
  saveContract(network.name, "lockonVesting", lockonVestingAddr);

  console.log("Note: Set addresses(lockStaking, indexStaking, airdrop) with addAddressDepositPermission.");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
