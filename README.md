# Agentic Deployment Specification

<p align="center">
  <img src="assets/ads-hero.png" alt="Agentic Deployment Specification logo with a friendly deployment agent, layered infrastructure, and the words Deploy, Scale, Observe, Govern.">
</p>

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
- [SPEC.md#example-architecture-diagrams](SPEC.md#example-architecture-diagrams) contains Mermaid diagrams for the current example set.
- [examples/minimal.yaml](examples/minimal.yaml) is the standalone canonical minimal ADS example.
- [examples/approval-policy.yaml](examples/approval-policy.yaml) is a v0.4-oriented approval and policy gate example.
- [examples/multi-agent.yaml](examples/multi-agent.yaml) is the first v0.4-oriented multi-agent production example.
- [examples/stateful-agent.yaml](examples/stateful-agent.yaml) is a v0.4-oriented managed-runtime-compatible stateful agent example.
- [schemas/ads.schema.json](schemas/ads.schema.json) is the initial JSON Schema for `ads.dev/v0alpha1`.
- [examples/invalid/](examples/invalid/) contains negative schema fixtures.
- [examples/conformance/invalid/](examples/conformance/invalid/) contains schema-valid documents that violate ADS processor conformance rules.
- [contexts/](contexts/) contains reference target contexts used by the conformance checker.
- [scripts/ads-conformance-check.rb](scripts/ads-conformance-check.rb) is a small reference checker for document-level conformance rules.

## Validation

The initial JSON Schema validates the structural v0.2 requirements that can be expressed directly in JSON Schema. Cross-reference and compatibility checks, such as unique component names, `dependsOn` resolution, profile support, secret binding resolution, network feasibility, and security policy enforcement, are defined as ADS processor conformance responsibilities in [SPEC.md](SPEC.md#v03-processor-conformance).

Run the schema and conformance fixture suite with:

```sh
ruby scripts/test-examples.rb
```

The suite uses `uvx check-jsonschema` for structural JSON Schema validation and the local ADS conformance checker for cross-reference and compatibility rules.

Validate the canonical example against only the JSON Schema with:

```sh
uvx check-jsonschema --schemafile schemas/ads.schema.json examples/minimal.yaml
```

Run the document-level conformance checker directly with:

```sh
ruby scripts/ads-conformance-check.rb examples/minimal.yaml
```

Validate an ADS document against a target context with:

```sh
ruby scripts/ads-conformance-check.rb --context contexts/kubernetes-production.yaml examples/minimal.yaml
```

The fixture suite also checks profile compatibility expectations: [examples/approval-policy.yaml](examples/approval-policy.yaml) is accepted by all current target contexts, [examples/stateful-agent.yaml](examples/stateful-agent.yaml) is accepted by Kubernetes production and managed container runtime target contexts, and [examples/multi-agent.yaml](examples/multi-agent.yaml) is accepted only by the Kubernetes production target context.

The top-level files in `examples/*.yaml` are positive examples and should pass schema validation and document-level conformance checks. The files in `examples/invalid/` are negative schema fixtures and should fail schema validation. The files in `examples/conformance/invalid/` should pass schema validation but fail ADS conformance checks.

The `contexts/*.yaml` files are non-normative target-context fixtures for the reference checker. They describe available target profile capabilities, secret bindings, approval handlers, observability sinks, network controls, and security policy enforcement. The files in `contexts/invalid/` intentionally omit required target context support.

## Current Direction

ADS should become a deployment and governance standard for production agentic systems, not another wrapper around `docker-compose.yml`. A conforming ADS document should describe:

- the runtime components that must run
- the platform capabilities required by those components
- the security boundaries, secrets, and network policies that apply
- the approval and policy gates required before risky actions
- the observability signals needed for operations and auditability

See [SPEC.md](SPEC.md) for the current draft model.
