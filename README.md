# CHAINLINK FUNCTIONS STARTER

![Version](https://img.shields.io/badge/version-1.0.0-blue.svg?style=for-the-badge)
![Forge](https://img.shields.io/badge/forge-v0.2.0-blue.svg?style=for-the-badge)
![Solc](https://img.shields.io/badge/solc-v0.8.20-blue.svg?style=for-the-badge)
[![GitHub License](https://img.shields.io/github/license/trashpirate/foundry-starter?style=for-the-badge)](https://github.com/trashpirate/foundry-starter/blob/master/LICENSE)

[![Website: trashpirate.io](https://img.shields.io/badge/Portfolio-00e0a7?style=for-the-badge&logo=Website)](https://trashpirate.io)
[![LinkedIn: nadinaoates](https://img.shields.io/badge/LinkedIn-0a66c2?style=for-the-badge&logo=LinkedIn&logoColor=f5f5f5)](https://linkedin.com/in/nadinaoates)
[![Twitter: 0xTrashPirate](https://img.shields.io/badge/@0xTrashPirate-black?style=for-the-badge&logo=X)](https://twitter.com/0xTrashPirate)


## About
This repo contains a starter kit template for developing and testing smart contracts with [Chainlink Functions](https://docs.chain.link/chainlink-functions/). It includes a basic `FunctionsConsumer` contract and a `FunctionsRouterMock` contract to locally test send and fulfill requests. The repo also includes the [functions-toolkit](https://www.npmjs.com/package/@chainlink/functions-toolkit) to simulate and interact with the Chainlink oracle. Scripts to spin up a local chainlink test network is also included.

## Installation

### Install dependencies
```bash
$ make install
```

## Usage
Before running any commands, create a .env file and add the following environment variables (see .env.example):

```bash
# network configs
RPC_LOCALHOST="http://127.0.0.1:8545"

# ethereum nework
RPC_TEST=<rpc url>
RPC_MAIN=<rpc url>
ETHERSCAN_KEY=<api key>

# accounts to deploy/interact with contracts
ACCOUNT_NAME="account name"
ACCOUNT_ADDRESS="account address"
```

Update chain ids in the `HelperConfig.s.sol` file for the chain you want to configure:

- Ethereum: 1 | Sepolia: 11155111 
- Base: 8453 | Base sepolia: 84532
- Bsc: 56 | Bsc Testnet: 97

Paste Javascript source code for chainlink functions execution into the `source.js` file.

### Run tests
```bash
$ forge test
```

### Deploy contract on testnet
```bash
$ make deploy-testnet
```

### Deploy contract on mainnet
```bash
$ make deploy-mainnet
```

## Deployments

### Testnet
https://sepolia.basescan.org/address/0xee54de507ab45659f7aed9f2bbb624c6abcfe744#code

### Mainnet

## Chainlink Functions Simulations

1. Paste javascript source code for chainlink functions execution into the `source.js` file

2. Run the following command to simulate the chainlink functions execution:
```bash
$ make simulate-response ARGS="arg1 arg2 ..."
```
For example try `make simulate-response ARGS="ipfs://bafybeieokkbwo2hp3eqkfa5chypmevxjii275icwxnuc7dmuexi3qsuvu4/5 Color"`

## Run Local Chainlink Functions Testnet

**__Note: This setup is only works with `shanghai` EVM version or older!__**

1. Setup your environment variables (secrets) by creating a `.env.enc` file and running:

```bash
# set password to encrypt secrets (or create a new env.enc file)
$ npx env-enc set-pw

# set secrets by following the prompts; not that at least you need to set PRIVATE_KEY to run the testnet
$ npx env-enc set
```

2. Start the local testnet by running:

```bash
$ make start-local-network
```

3. Deploy the contracts to the local testnet:

```bash
$ make deploy-local
```

4. Use the `Interactions.s.sol` script to perform interactions with the `FunctionsConsumer` contract. Here are some shortcuts:

- Send a request to the `FunctionsConsumer` contract:
    ```bash
    $ make send-request
    ```
- Read the response from the `FunctionsConsumer` contract (wait a few seconds after you sent the request for it to fulfill):
    ```bash
    $ make get-response
    ```

## Contributing

Contributions are what make the open source community such an amazing place to learn, inspire, and create. Any contributions you make are **greatly appreciated**.

If you have a suggestion that would make this better, please fork the repo and create a pull request. You can also simply open an issue with the tag "enhancement".
Don't forget to give the project a star! Thanks again!

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## Author

👤 **Nadina Oates**

* Website: [trashpirate.io](https://trashpirate.io)
* Twitter: [@N0xTrashPirate](https://twitter.com/0xTrashPirate)
* Github: [@trashpirate](https://github.com/trashpirate)
* LinkedIn: [@nadinaoates](https://linkedin.com/in/nadinaoates)


## 📝 License

Copyright © 2025 [Nadina Oates](https://github.com/trashpirate).

