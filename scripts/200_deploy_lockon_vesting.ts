import { ethers, network, run, upgrades, defender } from "hardhat";

import {getContracts, getEnvParams, saveContract, getDefenderUpgradeApprovalOwnerAddress} from "./utils/deploy-helper";

async function main() {
  const envParams = getEnvParams();
  const contracts = getContracts(network.name)[network.name];
  if (contracts.lockonVesting) {
    throw new Error("LockonVesting contract already deployed");
  }

  const LockonVesting = await ethers.getContractFactory("LockonVesting");
  const ownerAddress = await getDefenderUpgradeApprovalOwnerAddress();

  const lockonVesting = await defender.deployProxy(
    LockonVesting,
    [ownerAddress, contracts.lockToken],
    { initializer: "initialize", kind: "uups" }
  );
  await lockonVesting.waitForDeployment();
  const lockonVestingAddr = await lockonVesting.getAddress();
  console.log(
    "Lockon Vesting contract deployed to address:",
    lockonVestingAddr
  );
  saveContract(network.name, "lockonVesting", lockonVestingAddr);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
