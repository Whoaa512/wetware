/**
 * wetware-prime — OpenClaw internal hook
 *
 * Injects wetware resonance state (briefing + priming) into the agent's
 * context at session bootstrap. Fires on every new session.
 *
 * Install:
 *   cp -R example/openclaw/hooks/wetware-prime ~/.openclaw/hooks/
 *
 * Enable in openclaw.json:
 *   { "hooks": { "internal": { "enabled": true, "entries": { "wetware-prime": { "enabled": true } } } } }
 *
 * Environment variables:
 *   WETWARE_BIN              Path to wetware binary (default: wetware on $PATH)
 *   WETWARE_PRIME_ENABLED    "true" (default) or "false" to disable
 *   WETWARE_PRIME_MAX_TOKENS Max tokens for injected content (default: 2000)
 */

import { execFile } from "node:child_process";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

const TIMEOUT_MS = 15_000;
const CHARS_PER_TOKEN = 4;

export default async function handler(event: any): Promise<void> {
  if (event.type !== "agent" || event.action !== "bootstrap") return;

  const enabled = (process.env.WETWARE_PRIME_ENABLED ?? "true") !== "false";
  if (!enabled) return;

  const bin = process.env.WETWARE_BIN ?? "wetware";
  const maxTokens = parseInt(process.env.WETWARE_PRIME_MAX_TOKENS ?? "2000", 10);
  const maxChars = maxTokens * CHARS_PER_TOKEN;

  try {
    const [briefingResult, primingResult] = await Promise.allSettled([
      execFileAsync(bin, ["briefing"], { timeout: TIMEOUT_MS, shell: true }),
      execFileAsync(bin, ["priming"], { timeout: TIMEOUT_MS, shell: true }),
    ]);

    const briefing =
      briefingResult.status === "fulfilled"
        ? briefingResult.value.stdout.trim()
        : (console.error("[wetware-prime] briefing failed:", (briefingResult as PromiseRejectedResult).reason?.message), "");
    const priming =
      primingResult.status === "fulfilled"
        ? primingResult.value.stdout.trim()
        : (console.error("[wetware-prime] priming failed:", (primingResult as PromiseRejectedResult).reason?.message), "");

    if (!briefing && !priming) {
      console.log("[wetware-prime] both commands returned empty, skipping");
      return;
    }

    let content = "[Wetware Resonance State]\n";
    if (briefing) content += briefing + "\n\n";
    if (priming) content += priming + "\n";

    if (content.length > maxChars) {
      content = content.slice(0, maxChars) + "\n[...truncated to token budget]";
    }

    // Inject as a synthetic bootstrap file into the agent's context window.
    // The `name` field is required by OpenClaw's bootstrap file loader.
    const ctx = event.context;
    if (Array.isArray(ctx?.bootstrapFiles)) {
      ctx.bootstrapFiles.push({
        name: "WETWARE_RESONANCE.md",
        path: "WETWARE_RESONANCE.md",
        content,
        source: "hook:wetware-prime",
      });
    }

    console.log(
      `[wetware-prime] injected ${content.length} chars (~${Math.ceil(content.length / CHARS_PER_TOKEN)} tokens)`,
    );
  } catch (err) {
    console.error("[wetware-prime] unexpected error:", err);
  }
}
