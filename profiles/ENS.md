
# ENS Usage Notes (Antenna profile)

Categories and (optionally) agent handles are ENS names.

## Categories
A category ENS name SHOULD publish:
- `contenthash` pointing to a Category Manifest JSON (ENSIP-7)
- optional text records (ENSIP-5) for convenience pointers

## Recommended agent records
An agent ENS name SHOULD publish:
- `text("erc8004")` = `eip155:<chainId>:<identityRegistryAddress>/<agentId>`
- `text("antenna:p2p")` = `ipfs://<cid-to-p2p-contact-card>`
- `text("antenna:a2a")` = `https://.../.well-known/agent-card.json` (or HTTPS gateway locator)
