# LOCK Contracts Repository

This repository contains new features include Lock token, vesting and staking contracts for lockon system

## Using Foundry Framework for Lock contracts

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

- **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
- **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
- **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
- **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

For comprehensive documentation, please refer to the official Foundry documentation: [Foundry Documentation] https://book.getfoundry.sh/

## Usage

### Build

To build your project, use the following command:

```shell
$ forge build
```

### Test

Run tests for your smart contracts with:

```shell
$ forge test
```

### Format

For code formatting, use:

```shell
$ forge fmt
```

### Gas Snapshots

Generate gas usage snapshots, create a snapshot of each test's gas usage with command:

```shell
$ forge snapshot
```

### Anvil

Start a local Ethereum node (Anvil) for development (deploy on a local network, work as Ganache on Hardhat):

```shell
$ anvil
```

### Coverage

Run a coverage for solidity file across all folder

```shell
$ forge coverage
```

### Deploy

To deploy your smart contracts, use the following command:

```shell
$ yarn <deploy_command_in_package.json> scripts/<script_name>
```

Replace <deploy_command_in_package.json> with correspond command define in package.json and <script_name> with name of the deployment script.

### Cast

Interact with EVM smart contracts, send transactions, and access blockchain data using the cast command:

```shell
$ cast <subcommand>
```

### Help

For help and more information on available commands, use these commands:

```shell
$ forge --help
$ anvil --help
$ cast --help
```
### Airdrop Testing
Update file user-airdrop-info-test.json and run file generate_merkle_root_test.ts for generating results use in unit test
Run this command to get merkle tree data: 
```shell
$ ts-node test/airdrop-utils/generate_merkle_root_test.ts
```