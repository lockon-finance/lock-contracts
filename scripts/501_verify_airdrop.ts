import { ethers, network, run } from "hardhat";

import { getContracts } from "./utils/deploy-helper";

async function main() {
  const contracts = getContracts(network.name)[network.name];
  await run("verify:verify", {
    address: contracts.airdrop,
  });
}

main().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
