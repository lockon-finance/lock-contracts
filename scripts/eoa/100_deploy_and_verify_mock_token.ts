import { ethers, network, run } from "hardhat";
import { getContracts, getEnvParams, saveContract } from "../utils/deploy-helper";

async function main() {
  const envParams = getEnvParams();
  const name = "MockToken";
  const symbol = "MT";
  const initialOwner = envParams.ownerAddress;

  const contracts = getContracts(network.name)[network.name];
  let mockTokenAddr;
  if (!contracts.mockToken) {
    console.log("initialOwner", initialOwner);

    const MockToken = await ethers.getContractFactory("MockToken");
    const mockToken = await MockToken.deploy(name, symbol, initialOwner);

    await mockToken.waitForDeployment();

    mockTokenAddr = await mockToken.getAddress();

    console.log("MockToken deployed to:", mockTokenAddr);
    saveContract(network.name, "mockToken", mockTokenAddr);
  } else {
    mockTokenAddr = contracts.mockToken;
  }

  console.log("Verifying contract...");
  try {
    await run("verify:verify", {
      address: mockTokenAddr,
      constructorArguments: [name, symbol, initialOwner],
    });

    console.log("Contract verified successfully");
  } catch (error) {
    console.error("Error verifying contract:", error);
  }
}

main().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
