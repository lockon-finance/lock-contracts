import { ethers, network, upgrades } from "hardhat";
import { getContracts, proposeSafeUpgrade } from "./utils/deploy-helper";

async function main() {
  const contracts = getContracts(network.name)[network.name];
  const proxyAddress = contracts.airdrop;

  const Airdrop = await ethers.getContractFactory("Airdrop");

  const newImpl = await upgrades.prepareUpgrade(proxyAddress, Airdrop);

  console.log(`New implementation deployed at: ${newImpl}`);

  const proposalUrl = await proposeSafeUpgrade(
    proxyAddress,
    newImpl.toString(),
  );

  console.log(`Airdrop Upgrade proposed with URL: ${proposalUrl}`);
}

main().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
