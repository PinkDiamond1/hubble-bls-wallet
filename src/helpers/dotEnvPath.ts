import { exists, parseArgs } from "../../deps/index.ts";

const args = parseArgs(Deno.args);

const envName = args.env;
const dotEnvPath = envName ? `.env.${envName}` : ".env";

if (!await exists(dotEnvPath)) {
  console.log("Couldn't find env file", dotEnvPath);
  console.log("(See #configuration in README.md)");

  Deno.exit(1);
}

export default dotEnvPath;