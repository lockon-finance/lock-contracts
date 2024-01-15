import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-foundry";
import "@openzeppelin/hardhat-upgrades";
import "hardhat-contract-sizer";
import "hardhat-gas-reporter";
import dotenv from "dotenv";
import { HardhatUserConfig } from "hardhat/config";

dotenv.config();

const privateKey = process.env.PRIVATE_KEY as any;
const infuraKey = process.env.INFURA_KEY as any;
const alchemyKey = process.env.ALCHEMY_KEY as any;
const polygonApiKey = process.env.POLYGON_API_KEY as any;
const ethereumApiKey = process.env.ETHEREUM_API_KEY as any;

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.23",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  defender: {
    apiKey: process.env.DEFENDER_KEY as string,
    apiSecret: process.env.DEFENDER_SECRET as string,
  },
  networks: {
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
      chainId: 5,
    },
    sepolia: {
      url: `https://sepolia.infura.io/v3/${infuraKey}`,
      accounts: [privateKey],
    },
    mumbai: {
      url: `https://polygon-mumbai.g.alchemy.com/v2/${alchemyKey}`,
      accounts: [privateKey],
      chainId: 80001,
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
  },
  etherscan: {
    apiKey: {
      goerli: ethereumApiKey,
      sepolia: ethereumApiKey,
      polygonMumbai: polygonApiKey,
      polygon: polygonApiKey,
    },
  },
};
export const gasReporter = {
  enabled: process.env.REPORT_GAS !== undefined,
  currency: "USD",
};
export const mocha = {
  timeout: 50000,
};
export const contractSizer = {
  alphaSort: true,
  runOnCompile: true,
  disambiguatePaths: false,
};
export default config;
