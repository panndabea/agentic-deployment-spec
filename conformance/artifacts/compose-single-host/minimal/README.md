# ADS Compose Bundle

- ADS deployment: support-agent
- Target profile: compose-single-host
- Source: examples/minimal.yaml

Generated files:

- `compose.yaml`: Compose services and externally satisfied ADS requirements.
- `ads-plan.json`: The exact ADS deployment plan used by this adapter.

Secret bindings are emitted as environment references only; no secret payloads are included.

