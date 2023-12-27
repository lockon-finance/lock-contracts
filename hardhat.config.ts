import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-foundry"
import "@openzeppelin/hardhat-upgrades";
import "hardhat-contract-sizer";
import "hardhat-gas-reporter";
import dotenv from "dotenv";
dotenv.config();

const privateKey = process.env.PRIVATE_KEY;
const infuraKey = process.env.INFURA_KEY;
const alchemyKey = process.env.ALCHEMY_KEY;
const polygonApiKey = process.env.POLYGON_API_KEY;
const ethereumApiKey = process.env.ETHEREUM_API_KEY;

export const solidity = {
  version: "0.8.23",
  settings: {
    optimizer: {
      enabled: true,
      runs: 200,
    },
  },
};
export const networks = {
  hardhat: {
    gas: 12000000,
    blockGasLimit: 0x1fffffffffffff,
    allowUnlimitedContractSize: true,
    forking: {
      url: `https://goerli.infura.io/v3/${infuraKey}`,
    },
  },
  goerli: {
    url: `https://goerli.infura.io/v3/${infuraKey}`,
    accounts: [privateKey],
  },
  mumbai: {
    url: `https://polygon-mumbai.g.alchemy.com/v2/${alchemyKey}`,
    accounts: [privateKey],
    chainId: 80001,
    gasPrice: 20000000000,
    timeout: 20000,
  },
  ethereum: {
    chainId: 1,
    gasPrice: 18000000000,
    url: `https://mainnet.infura.io/v3/${infuraKey}`,
    accounts: [privateKey],
    timeout: 20000,
  },
  polygon: {
    chainId: 137,
    gasPrice: 140000000000,
    url: `https://polygon-rpc.com/`,
    accounts: [privateKey],
    timeout: 20000,
  },
};
export const gasReporter = {
  enabled: process.env.REPORT_GAS !== undefined,
  currency: "USD",
};
export const etherscan = {
  apiKey: { goerli: ethereumApiKey, sepolia: ethereumApiKey, polygonMumbai: polygonApiKey }
};
export const mocha = {
  timeout: 50000,
};
export const contractSizer = {
  alphaSort: true,
  runOnCompile: true,
  disambiguatePaths: false,
};
