import { ethers, network, defender } from "hardhat";

import {
  getContracts,
  getEnvParams,
  saveContract,
  getDefenderUpgradeApprovalOwnerAddress,
} from "./utils/deploy-helper";
import { encodeBytes32String } from "ethers";

async function main() {
  const envParams = getEnvParams();
  const contracts = getContracts(network.name)[network.name];
  if (contracts.lockonReferral) {
    throw new Error("LockonReferral contract already deployed");
  }

  const LockonReferral = await ethers.getContractFactory("LockonReferral");
  const ownerAddress = await getDefenderUpgradeApprovalOwnerAddress();

  const referralTypes = [
    encodeBytes32String("investor"),
    encodeBytes32String("affiliate"),
    encodeBytes32String("special"),
  ];
  const vestingCategoryIds = [10000, 10001, 10002];
  const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
  const lockonReferral = await defender.deployProxy(
    LockonReferral,
    [
      ownerAddress,
      envParams.operatorAddress,
      ZERO_ADDRESS,
      envParams.stableTokenAddress,
      ZERO_ADDRESS,
      referralTypes,
      vestingCategoryIds,
    ],
    { initializer: "initialize", kind: "uups" },
  );

  await lockonReferral.waitForDeployment();

  const lockonReferralAddr = await lockonReferral.getAddress();
  console.log("Lockon Referral contract deployed to address:", lockonReferralAddr);
  saveContract(network.name, "lockonReferral", lockonReferralAddr);
}

main().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
