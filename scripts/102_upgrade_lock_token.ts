import { ethers, network, upgrades } from "hardhat";
import { getContracts, proposeSafeUpgrade } from "./utils/deploy-helper";

async function main() {
  const contracts = getContracts(network.name)[network.name];
  const proxyAddress = contracts.lockToken;

  const LockToken = await ethers.getContractFactory("LockToken");

  const newImpl = await upgrades.prepareUpgrade(proxyAddress, LockToken);
  
  console.log(`New implementation deployed at: ${newImpl}`);

  const proposalUrl = await proposeSafeUpgrade(proxyAddress, newImpl.toString());

  console.log(`Lock Token Upgrade proposed with URL: ${proposalUrl}`);
}

main().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
