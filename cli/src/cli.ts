export type Subcommand = "tui" | "hook" | "status" | "install";

export type InstallProvider = "claude" | "opencode";

export interface ParsedArgs {
  subcommand: Subcommand;
  provider?: InstallProvider;
}

export function parseArgs(args: string[]): ParsedArgs {
  const positional = args.filter((a) => !a.startsWith("--"));
  const sub = positional[0];

  let subcommand: Subcommand;
  switch (sub) {
    case "hook":
      subcommand = "hook";
      break;
    case "status":
      subcommand = "status";
      break;
    case "install":
      subcommand = "install";
      break;
    default:
      subcommand = "tui";
      break;
  }

  // Parse --provider flag for install subcommand
  let provider: InstallProvider | undefined;
  if (subcommand === "install") {
    const providerIdx = args.indexOf("--provider");
    if (providerIdx !== -1 && providerIdx + 1 < args.length) {
      const val = args[providerIdx + 1];
      if (val === "claude" || val === "opencode") {
        provider = val;
      } else {
        console.error(`Error: unknown provider '${val}'. Must be 'claude' or 'opencode'.`);
        process.exit(1);
      }
    }
  }

  return { subcommand, provider };
}
