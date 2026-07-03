# Agentic Deployment Specification

> A vendor-neutral deployment contract for self-hosted applications and agentic systems.

The Agentic Deployment Specification (ADS) lets an application describe how it should be deployed, secured, observed, and governed. Instead of forcing deployment agents or platform teams to reverse-engineer a repository, ADS makes operational intent explicit and machine-readable.

## Status

Draft v0.3 in progress. v0.2 established the concrete YAML authoring format. The current work makes that model machine-validatable with JSON Schema, fixtures, and processor conformance rules.

## What ADS is

ADS is a specification for describing deployment requirements that downstream tools can satisfy with Kubernetes, Docker Compose, managed container runtimes, GitOps systems, policy engines, or other infrastructure.

ADS is designed for:

- platform engineers operating self-hosted software
- AI deployment agents that need a safe contract to follow
- self-hosting vendors and open-source maintainers
- enterprise security and governance teams
- customers deploying software into their own environments

## What ADS is not

ADS is not a replacement for Kubernetes manifests, Helm charts, CI/CD pipelines, secrets managers, model-serving protocols, or agent frameworks. It describes the operational requirements those systems must satisfy.

## Core Principles

- Vendor neutral: ADS describes intent, not a single platform implementation.
- Human approval by default: risky deployment and tool actions must be explicit.
- Self-hosting first: customer-controlled environments are a primary target.
- AI-native: agents, tools, memory, policy, and observability are first-class concerns.
- Open standard: the specification should be readable by humans and enforceable by machines.

## Repository Navigation

- [SPEC.md](SPEC.md) is the normative draft specification.
- [ROADMAP.md](ROADMAP.md) tracks planned versions and exit criteria.
- [deployment-research.md](deployment-research.md) is the non-normative technical research reference used to shape the specification.
- [examples/minimal.yaml](examples/minimal.yaml) is the standalone canonical minimal ADS example.
- [schemas/ads.schema.json](schemas/ads.schema.json) is the initial JSON Schema for `ads.dev/v0alpha1`.
- [examples/invalid/](examples/invalid/) contains negative schema fixtures.

## Validation

The initial JSON Schema validates the structural v0.2 requirements that can be expressed directly in JSON Schema. Cross-reference and compatibility checks, such as unique component names, `dependsOn` resolution, profile support, and secret binding resolution, remain ADS processor responsibilities.

Validate the canonical example with:

```sh
uvx check-jsonschema --schemafile schemas/ads.schema.json examples/minimal.yaml
```

The files in `examples/invalid/` are negative fixtures and should fail validation.

## Current Direction

ADS should become a deployment and governance standard for production agentic systems, not another wrapper around `docker-compose.yml`. A conforming ADS document should describe:

- the runtime components that must run
- the platform capabilities required by those components
- the security boundaries, secrets, and network policies that apply
- the approval and policy gates required before risky actions
- the observability signals needed for operations and auditability

See [SPEC.md](SPEC.md) for the current draft model.
