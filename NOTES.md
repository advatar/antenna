What’s updated for Groth16 (BN254) in this repo
	•	Normative spec update: spec/MBP2P-SPEC.md
	•	Section §12 now standardizes Groth16 / BN254 encoding, including public input ordering and signalHash derivation.
	•	Normative JSON schema update: schemas/antenna.zkcredits.v1.schema.json
	•	proof is now a structured Groth16 object:
	•	proof.system = "groth16"
	•	proof.curve = "bn254"
	•	proof.a, proof.b, proof.c
	•	proof.inputs exactly 5 field elements (0x + 64 hex chars)
	•	Example updated to match schema: examples/event.helprequest.anon.json (and examples/envelope.helprequest.json)
	•	Solidity contracts updated to snarkjs-compatible Groth16 verifier ABI:
	•	contracts/src/interfaces/IZKCreditsVerifier.sol uses verifyProof(...) (snarkjs-style)
	•	contracts/src/MBZKCreditsEscrow.sol:
	•	consume(...) now accepts Groth16 (a,b,c)
	•	derives input[5] internally using the spec’s ordering
	•	contracts/src/VerifierRegistry.sol unchanged (still maps bytes32 verifierId -> verifier address)
	•	test mocks updated accordingly under contracts/src/mocks/

Quick sanity checks (interop)

From repo root:
	•	python ./scripts/run_interop_suite.py
	•	cd js && npm install && npm run build && npm run test:interop
