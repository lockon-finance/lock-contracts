import { ethers, network, run } from "hardhat";

import { getContracts, getExplorers } from "./utils/deploy-helper";

async function main() {
  const contracts = getContracts(network.name)[network.name];
  await run("verify:verify", {
    address: contracts.indexStaking,
  });  
}

main().catch(error => {
  console.error(error);
  const contracts = getContracts(network.name)[network.name];
  console.log(
    `Please manually verify the contract at ${getExplorers(network.name)}proxyContractChecker?a=${contracts.indexStaking}`,
  );
  process.exitCode = 1;
});
