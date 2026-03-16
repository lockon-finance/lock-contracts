import fs from "fs";
import path from "path";
import util from "util";
import { ethers, network } from "hardhat";
import SafeApiKit from "@safe-global/api-kit";
import Safe from "@safe-global/protocol-kit";
import { MetaTransactionData, OperationType } from "@safe-global/types-kit";
import { Ownable__factory, UUPSUpgradeable__factory } from "../../typechain-types";

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
  const lockTokenName = getEnvRequired("LOCK_TOKEN_NAME");
  const lockTokenSymbol = getEnvRequired("LOCK_TOKEN_SYMBOL");
  const operatorAddress = getEnvRequired("OPERATOR_ADDRESS");
  const managementAddress = getEnvRequired("MANAGEMENT_ADDRESS");
  const feeReceiverAddress = getEnvRequired("FEE_RECEIVER_ADDRESS");
  const initialIndexTokenAddresses = getEnvRequired("INITIAL_INDEX_TOKEN_ADDRESSES");
  const initialIndexTokenVestingCategoryIds = getEnvRequired("INITIAL_INDEX_TOKEN_VESTING_CATEGORY_IDS");
  const stableTokenAddress = getEnvRequired("STABLE_TOKEN_ADDRESS");
  const ownerAddress = getEnvRequired("OWNER_ADDRESS");
  const safeApiKey = getEnvRequired("SAFE_API_KEY");
  const safeProposerAddress = getEnvRequired("SAFE_PROPOSER_ADDRESS");
  const safeProposerPrivateKey = getEnvRequired("SAFE_PROPOSER_PRIVATE_KEY");

  const initialIndexTokenAddressArray = initialIndexTokenAddresses.split(",");
  const initialIndexTokenVestingCategoryIdArray = initialIndexTokenVestingCategoryIds.split(",");
  if (initialIndexTokenAddressArray.length !== initialIndexTokenVestingCategoryIdArray.length) {
    throw new Error(
      "INITIAL_INDEX_TOKEN_ADDRESSES and INITIAL_INDEX_TOKEN_VESTING_CATEGORY_IDS must have the same number of elements",
    );
  }

  return {
    lockTokenName,
    lockTokenSymbol,
    operatorAddress,
    managementAddress,
    feeReceiverAddress,
    initialIndexTokenAddresses: initialIndexTokenAddressArray,
    initialIndexTokenVestingCategoryIds: initialIndexTokenVestingCategoryIdArray,
    stableTokenAddress,
    ownerAddress,
    safeApiKey,
    safeProposerAddress,
    safeProposerPrivateKey,
  };
}

export function getContracts(network: string) {
  let json: string | Buffer;
  try {
    const env = process.env.NODE_ENV;
    json = fs.readFileSync(path.join(__dirname, `../../deployed-addresses/${env}.${network}.contract-addresses.json`));
  } catch (err) {
    json = `{"${network}":{}}`;
  }
  return JSON.parse(String(json));
}

export function getExplorers(network: string) {
  switch (network) {
    case "sepolia":
      return "https://sepolia.etherscan.io/";
    case "arbitrumSepolia":
      return "https://sepolia.arbiscan.io/";
    case "mainnet":
      return "https://etherscan.io/";
    case "polygon":
      return "https://polygonscan.com/";
    case "arbitrum":
      return "https://arbiscan.io/";
    default:
      throw new Error(`Unknown network: ${network}`);
  }
}

export function saveContract(network: string, contract: string, address: string) {
  const env = process.env.NODE_ENV;

  const addresses = getContracts(network);
  addresses[network] = addresses[network] || {};
  addresses[network][contract] = address;
  fs.writeFileSync(
    path.join(__dirname, `../../deployed-addresses/${env}.${network}.contract-addresses.json`),
    JSON.stringify(addresses, null, "    "),
  );
}

export async function proposeSafeUpgrade(
  proxyAddress: string,
  newImplementationAddress: string,
  initData?: string,
): Promise<string> {
  const envParams = getEnvParams();
  const chainId = BigInt(Number(network.config.chainId));
  const apiKit = new SafeApiKit({ chainId: chainId, apiKey: envParams.safeApiKey });

  const uups = Ownable__factory.connect(proxyAddress, ethers.provider);
  const uupsOwner = await uups.owner();

  if (uupsOwner !== envParams.ownerAddress) {
    throw new Error(`uupsOwner ${uupsOwner} does not match envParams.owner ${envParams.ownerAddress}`);
  }

  const protocolKitOwner = await Safe.init({
    provider: network.provider,
    signer: envParams.safeProposerPrivateKey,
    safeAddress: envParams.ownerAddress,
  });

  const iface = UUPSUpgradeable__factory.createInterface();

  const calldata = initData
    ? iface.encodeFunctionData("upgradeToAndCall", [newImplementationAddress, initData])
    : iface.encodeFunctionData("upgradeToAndCall", [newImplementationAddress, "0x"]);

  const safeTransactionData: MetaTransactionData = {
    to: proxyAddress,
    value: "0",
    data: calldata,
    operation: OperationType.Call,
  };

  // Validate TX before proposing.
  await apiKit
    .estimateSafeTransaction(envParams.ownerAddress, {
      ...safeTransactionData,
      operation: Number(OperationType.Call),
    })
    .catch(error => {
      throw new Error(`Gas Estimation (TX Validation) failed: ${util.inspect(error, { depth: null })}`);
    });

  const safeTransaction = await protocolKitOwner.createTransaction({
    transactions: [safeTransactionData],
  });

  const safeTxHash = await protocolKitOwner.getTransactionHash(safeTransaction);
  const signature = await protocolKitOwner.signHash(safeTxHash);

  await apiKit.proposeTransaction({
    safeAddress: envParams.ownerAddress,
    safeTransactionData: safeTransaction.data,
    safeTxHash,
    senderAddress: envParams.safeProposerAddress,
    senderSignature: signature.data,
  });

  return `https://app.safe.global/transactions/tx?id=multisig_${envParams.ownerAddress}_${safeTxHash}&safe=${network.name}:${envParams.ownerAddress}`;
}
