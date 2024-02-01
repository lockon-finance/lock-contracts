import fs from "fs";
import path from "path";
import {defender} from "hardhat";

function getEnv(name: string) {
  return process.env[name];
}

function getEnvRequired(name: string): string {
  const value = getEnv(name);
  if (!value) {
    throw new Error(`Please set the ${name} environment variable`);
  }
  return value;
}

export function getEnvParams() {
  const lockTokenName = getEnvRequired("LOCK_TOKEN_NAME")
  const lockTokenSymbol = getEnvRequired("LOCK_TOKEN_SYMBOL")
  const operatorAddress = getEnvRequired("OPERATOR_ADDRESS")
  const managementAddress = getEnvRequired("MANAGEMENT_ADDRESS")
  const feeReceiverAddress = getEnvRequired("FEE_RECEIVER_ADDRESS")
  const merkleRoot = getEnv("MERKLE_ROOT")
  const initialIndexTokenAddresses = getEnvRequired("INITIAL_INDEX_TOKEN_ADDRESSES")

  const initialIndexTokenAddressArray = initialIndexTokenAddresses.split(",");

  return {
    lockTokenName,
    lockTokenSymbol,
    operatorAddress,
    managementAddress,
    feeReceiverAddress,
    merkleRoot,
    initialIndexTokenAddresses: initialIndexTokenAddressArray,
  }
}

export async function getDefenderUpgradeApprovalOwnerAddress() {
  const envOwnerAddress = getEnvRequired("OWNER_ADDRESS")
  const approvalProcess = await defender.getUpgradeApprovalProcess()
  if (approvalProcess.address !== envOwnerAddress) {
    throw new Error(`Upgrade approval process with id ${approvalProcess.approvalProcessId} has an address ${approvalProcess.address} that does not match the expected owner address ${envOwnerAddress}.`);
  }
  return approvalProcess.address;
}

export async function validateDefenderUpgradeApprovalOwnerAddress() {
  await getDefenderUpgradeApprovalOwnerAddress()
}

export function getContracts(network: string) {
  let json: string | Buffer;
  try {
    const env = process.env.NODE_ENV;
    json = fs.readFileSync(
      path.join(
        __dirname,
        `../../deployed-addresses/${env}.${network}.contract-addresses.json`
      )
    );
  } catch (err) {
    json = `{"${network}":{}}`;
  }
  return JSON.parse(String(json));
}

export function saveContract(
  network: string,
  contract: string,
  address: string
) {
  const env = process.env.NODE_ENV;

  const addresses = getContracts(network);
  addresses[network] = addresses[network] || {};
  addresses[network][contract] = address;
  fs.writeFileSync(
    path.join(
      __dirname,
      `../../deployed-addresses/${env}.${network}.contract-addresses.json`
    ),
    JSON.stringify(addresses, null, "    ")
  );
}
