import fs from "fs";
import path from "path";
import { ethers } from "ethers";
import {
  startLocalFunctionsTestnet,
  SubscriptionManager,
} from "@chainlink/functions-toolkit";

// Loads environment variables from .env.enc file (if it exists)
require("@chainlink/env-enc").config("../.env.enc");

(async () => {
  // const requestConfigPath = path.join(__dirname, "cf-request-config.ts"); // @dev Update this to point to your desired request config file
  // console.log(`Using Functions request config file ${requestConfigPath}\n`);

  const localFunctionsTestnetInfo = await startLocalFunctionsTestnet(
    undefined,
    {
      logging: {
        debug: false,
        verbose: false,
        quiet: true, // Set this to `false` to see logs from the local testnet
      },
    } // Ganache server options (optional),
  );

  console.table({
    "FunctionsRouter Contract Address":
      localFunctionsTestnetInfo.functionsRouterContract.address,
    "DON ID": localFunctionsTestnetInfo.donId,
    "Mock LINK Token Contract Address":
      localFunctionsTestnetInfo.linkTokenContract.address,
  });

  // Fund wallets with ETH and LINK
  const anvilDefaultKey = process.env["PRIVATE_KEY"];
  console.log("PRIVATE_KEY: ", anvilDefaultKey);
  if (!anvilDefaultKey) {
    throw new Error("PRIVATE_KEY is not defined in the environment variables.");
  }

  const signer = new ethers.Wallet(anvilDefaultKey);

  const addressToFund = signer.address;
  await localFunctionsTestnetInfo.getFunds(addressToFund, {
    weiAmount: ethers.utils.parseEther("100").toString(), // 100 ETH
    juelsAmount: ethers.utils.parseEther("100").toString(), // 100 LINK
  });
  if (process.env["SECOND_PRIVATE_KEY"]) {
    const secondAddressToFund = new ethers.Wallet(
      process.env["SECOND_PRIVATE_KEY"]
    ).address;
    await localFunctionsTestnetInfo.getFunds(secondAddressToFund, {
      weiAmount: ethers.utils.parseEther("100").toString(), // 100 ETH
      juelsAmount: ethers.utils.parseEther("100").toString(), // 100 LINK
    });
  }

  // Update values in networks.js
  let networksConfig = fs
    .readFileSync(path.join(__dirname, "networks.js"))
    .toString();
  const regex = /localFunctionsTestnet:\s*{\s*([^{}]*)\s*}/s;
  const newContent = `localFunctionsTestnet: {
    url: "http://localhost:8545/",
    accounts,
    confirmations: 1,
    nativeCurrencySymbol: "ETH",
    linkToken: "${localFunctionsTestnetInfo.linkTokenContract.address}",
    functionsRouter: "${localFunctionsTestnetInfo.functionsRouterContract.address}",
    donId: "${localFunctionsTestnetInfo.donId}",
  }`;
  networksConfig = networksConfig.replace(regex, newContent);
  fs.writeFileSync(path.join(__dirname, "networks.js"), networksConfig);

  // Update values in cf-network-config.json
  const cfNetworkConfig = {
    donID: `${localFunctionsTestnetInfo.donId}`,
    functionsRouter: `${localFunctionsTestnetInfo.functionsRouterContract.address}`,
    linkToken: `${localFunctionsTestnetInfo.linkTokenContract.address}`,
  };

  fs.writeFileSync(
    path.join(__dirname, "cf-network-config.json"),
    JSON.stringify(cfNetworkConfig)
  );
})();
