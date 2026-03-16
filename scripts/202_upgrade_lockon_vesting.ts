import { ethers, network, upgrades } from "hardhat";
import { getContracts, proposeSafeUpgrade } from "./utils/deploy-helper";

async function main() {
  const contracts = getContracts(network.name)[network.name];
  const proxyAddress = contracts.lockonVesting;

  const LockonVesting = await ethers.getContractFactory("LockonVesting");

  const newImpl = await upgrades.prepareUpgrade(proxyAddress, LockonVesting);

  console.log(`New implementation deployed at: ${newImpl}`);

  const proposalUrl = await proposeSafeUpgrade(
    proxyAddress,
    newImpl.toString(),
  );

  console.log(`Lockon Vesting Upgrade proposed with URL: ${proposalUrl}`);
}

main().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
