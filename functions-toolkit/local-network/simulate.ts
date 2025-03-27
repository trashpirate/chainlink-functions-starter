import {
  decodeResult,
  ReturnType,
  simulateScript,
} from "@chainlink/functions-toolkit";

import fs from "fs";
import path from "path";
import { ethers } from "ethers";

async function simulate() {
  console.log(path.join(path.resolve(__dirname, ".."), "source", "code.js"));
  const source = fs
    .readFileSync(path.join(path.resolve(__dirname, ".."), "source", "code.js"))
    .toString();

  let args: string[] = process.argv.slice(2);

  const response = await simulateScript({
    source: source, // JavaScript source code
    args: args, // Array of string arguments accessible from the source code via the global variable `args`
    bytesArgs: [], // Array of bytes arguments, represented as hex strings, accessible from the source code via the global variable `bytesArgs`
    secrets: {}, // Secret values represented as key-value pairs
    // maxOnChainResponseBytes: undefined, // Maximum size of the returned value in bytes (defaults to 256)
    // maxExecutionTimeMs: undefined, // Maximum execution duration (defaults to 10_000ms)
    // maxMemoryUsageMb: undefined, // Maximum RAM usage (defaults to 128mb)
    // numAllowedQueries: undefined, // Maximum number of HTTP requests (defaults to 5)
    // maxQueryDurationMs: undefined, // Maximum duration of each HTTP request (defaults to 9_000ms)
    // maxQueryUrlLength: undefined, // Maximum HTTP request URL length (defaults to 2048)
    // maxQueryRequestBytes: undefined, // Maximum size of outgoing HTTP request payload (defaults to 2048 == 2 KB)
    // maxQueryResponseBytes: undefined, // Maximum size of incoming HTTP response payload (defaults to 2_097_152 == 2 MB)
  });

  const returnType = ReturnType.string;

  const responseBytesHexstring = ethers.utils.hexValue(
    response.responseBytesHexstring as string
  );

  if (ethers.utils.arrayify(responseBytesHexstring).length > 0) {
    const decodedResponse = decodeResult(
      response.responseBytesHexstring as string,
      returnType
    );
    console.log(`✅ Decoded response to ${returnType}: `, decodedResponse);
  }
}

simulate();
