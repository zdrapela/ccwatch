#!/usr/bin/env node
import { parseArgs } from "./cli.js";

const { subcommand, provider } = parseArgs(process.argv.slice(2));

switch (subcommand) {
  case "hook": {
    const { hookCommand } = await import("./hook.js");
    await hookCommand();
    break;
  }
  case "status": {
    const { statusCommand } = await import("./statusline.js");
    await statusCommand();
    break;
  }
  case "install": {
    const { installCommand } = await import("./install.js");
    await installCommand(provider);
    break;
  }
  case "tui": {
    const { startTui } = await import("./tui.js");
    await startTui();
    break;
  }
}
