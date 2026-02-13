
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
import { computeEventId } from "./eventId.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

function readJson(p: string): any {
  return JSON.parse(fs.readFileSync(p, "utf8"));
}

function main() {
  const repoRoot = path.resolve(__dirname, "../..");
  const suite = readJson(path.join(repoRoot, "interop", "suite.json"));

  let failures: string[] = [];

  for (const vec of suite.eventIdVectors || []) {
    const event = readJson(path.join(repoRoot, vec.eventFile));
    const got = computeEventId(event);
    if (got !== vec.expectedEventId) {
      failures.push(`[eventId] ${vec.name}: expected ${vec.expectedEventId}, got ${got}`);
    }
  }

  if (failures.length) {
    console.error("FAIL");
    for (const f of failures) console.error(" - " + f);
    process.exit(1);
  }
  console.log("OK: JS eventId vectors passed.");
}

main();
