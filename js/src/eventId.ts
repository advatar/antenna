
import { canonicalize } from "./canonicalize.js";
import { createHash } from "crypto";

export function stripEventForId(event: any): any {
  const e = JSON.parse(JSON.stringify(event));
  delete e.id;
  delete e.auth;
  delete e.thread;   // avoid self-reference (root thread == id)
  delete e.metadata; // metadata is non-normative and can contain derived hints
  return e;
}

export function computeEventId(event: any): string {
  const stripped = stripEventForId(event);
  const canon = canonicalize(stripped);
  const digest = createHash("sha256").update(Buffer.from(canon, "utf8")).digest("hex");
  return "0x" + digest;
}
