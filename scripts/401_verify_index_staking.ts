import { ethers, network, run, defender } from "hardhat";

import { getContracts, getEnvParams, saveContract } from "./utils/deploy-helper";

async function main() {
  const contracts = getContracts(network.name)[network.name];
  await run("verify:verify", {
    address: contracts.indexStaking,
  });
}

main().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
