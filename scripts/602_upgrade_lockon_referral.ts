import { ethers, network, upgrades } from "hardhat";
import { getContracts, proposeSafeUpgrade } from "./utils/deploy-helper";

async function main() {
  const contracts = getContracts(network.name)[network.name];
  const proxyAddress = contracts.lockonReferral;

  const LockonReferral = await ethers.getContractFactory("LockonReferral");

  const newImpl = await upgrades.prepareUpgrade(proxyAddress, LockonReferral);

  console.log(`New implementation deployed at: ${newImpl}`);

  const proposalUrl = await proposeSafeUpgrade(
    proxyAddress,
    newImpl.toString(),
  );

  console.log(`Lockon Referral Upgrade proposed with URL: ${proposalUrl}`);
}

main().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
