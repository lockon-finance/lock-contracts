import fs from "fs";
import path from "path";

export function getEnvParams() {
  const lockTokenName = process.env.LOCK_TOKEN_NAME;
  const lockTokenSymbol = process.env.LOCK_TOKEN_SYMBOL;
  const operatorAddress = process.env.OPERATOR_ADDRESS;
  const feeReceiverAddress = process.env.FEE_RECEIVER_ADDRESS;
  const initialIndexTokenAddresses = process.env.INITIAL_INDEX_TOKEN_ADDRESSES;
  if (!lockTokenName || !lockTokenSymbol || !operatorAddress || !feeReceiverAddress || !initialIndexTokenAddresses) {
    throw new Error(
      "Please set the LOCK_TOKEN_NAME, LOCK_TOKEN_SYMBOL, OPERATOR_ADDRESS, FEE_RECEIVER_ADDRESS, INITIAL_INDEX_TOKEN_ADDRESSES environment variables"
    );
  }

  const initialIndexTokenAddressArray = initialIndexTokenAddresses.split(",");

  return {
    lockTokenName,
    lockTokenSymbol,
    operatorAddress,
    feeReceiverAddress,
    initialIndexTokenAddresses: initialIndexTokenAddressArray,
  }

}
export function getContracts(network: any) {
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
    json = "{}";
  }
  const addresses = JSON.parse(String(json));
  return addresses;
}

export function saveContract(
  network: string | number,
  contract: string | number,
  address: any
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
