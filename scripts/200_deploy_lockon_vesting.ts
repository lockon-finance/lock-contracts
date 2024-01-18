import { ethers, network, run, upgrades, defender } from "hardhat";

import {getContracts, getEnvParams, saveContract} from "./utils/deploy-helper";

async function main() {
  const envParams = getEnvParams();
  const contracts = getContracts(network.name)[network.name];

  const LockonVesting = await ethers.getContractFactory("LockonVesting");
  const upgradeApprovalProcess = await defender.getUpgradeApprovalProcess();

  if (upgradeApprovalProcess.address === undefined) {
    throw new Error(
      `Upgrade approval process with id ${upgradeApprovalProcess.approvalProcessId} has no assigned address`
    );
  }

  const lockonVesting = await defender.deployProxy(
    LockonVesting,
    [upgradeApprovalProcess.address, contracts.lockToken],
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
