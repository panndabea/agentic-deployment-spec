# Agentic Deployment Specification

<p align="center">
  <img src="assets/ads-hero.png" alt="Agentic Deployment Specification logo with a friendly deployment agent, layered infrastructure, and the words Deploy, Scale, Observe, Govern.">
</p>

> A vendor-neutral deployment contract for self-hosted applications and agentic systems.

The Agentic Deployment Specification (ADS) lets an application describe how it should be deployed, secured, observed, and governed. Instead of forcing deployment agents or platform teams to reverse-engineer a repository, ADS makes operational intent explicit and machine-readable.

## Status

ADS v1 is stable. The current release target is `v1.1.0`, a compatible release of the stable `ads.dev/v1` API. The reference examples and JSON Schema target that API version. v1.1-sized additions on `main` include the agent-facing CLI, deterministic planning, local artifact bundle emission, additional target contexts, and expanded conformance snapshots.

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

## Documentation Map

For ADS authors:

- [SPEC.md](SPEC.md) is the normative stable ADS v1 specification.
- [examples/minimal.yaml](examples/minimal.yaml) is the standalone canonical minimal ADS example.
- [examples/approval-policy.yaml](examples/approval-policy.yaml), [examples/air-gapped.yaml](examples/air-gapped.yaml), [examples/serverless-auxiliary.yaml](examples/serverless-auxiliary.yaml), [examples/multi-agent.yaml](examples/multi-agent.yaml), [examples/stateful-agent.yaml](examples/stateful-agent.yaml), and [examples/supply-chain.yaml](examples/supply-chain.yaml) show production-oriented patterns.
- [COMPATIBILITY.md](COMPATIBILITY.md) summarizes which examples are expected to pass against the current target contexts.
- [SPEC.md#production-readiness-checklist](SPEC.md#production-readiness-checklist), [SPEC.md#audit-event-taxonomy](SPEC.md#audit-event-taxonomy), and [SPEC.md#example-architecture-diagrams](SPEC.md#example-architecture-diagrams) collect the main review aids inside the spec.

For processor implementers:

- [IMPLEMENTERS.md](IMPLEMENTERS.md) is a practical guide for independent ADS processor implementers.
- [REFERENCE_PROCESSOR.md](REFERENCE_PROCESSOR.md) documents the Ruby reference conformance processor.
- [schemas/ads.schema.json](schemas/ads.schema.json) is the JSON Schema for `ads.dev/v1`.
- [conformance/expectations.yaml](conformance/expectations.yaml) is the machine-readable fixture expectation manifest used by the test suite.
- [contexts/](contexts/) contains reference target contexts used by the reference processor.

For maintainers:

- [ROADMAP.md](ROADMAP.md) tracks planned versions and exit criteria.
- [CONTRIBUTING.md](CONTRIBUTING.md) describes the contribution workflow, fixture expectations, and governance rules.
- [RELEASE.md](RELEASE.md) defines release readiness gates, active `v1.1.0` readiness tracking, and the historical `v1.0.0` release record.
- [deployment-research.md](deployment-research.md) is the non-normative technical research reference used to shape the specification.

## Validation

The JSON Schema validates the structural requirements that can be expressed directly in JSON Schema. Cross-reference and compatibility checks, such as unique component names, `dependsOn` resolution, profile support, secret binding resolution, network feasibility, and security policy enforcement, are defined as ADS processor conformance responsibilities in [SPEC.md](SPEC.md#processor-conformance).

Run the schema and conformance fixture suite with:

```sh
ruby scripts/test-examples.rb
```

The suite uses `uvx check-jsonschema` for structural JSON Schema validation and the local ADS reference conformance processor for cross-reference and compatibility rules. Fixture expectations are declared in [conformance/expectations.yaml](conformance/expectations.yaml), the reference processor is documented in [REFERENCE_PROCESSOR.md](REFERENCE_PROCESSOR.md), and the human-readable target matrix is summarized in [COMPATIBILITY.md](COMPATIBILITY.md).

Run the independent Go fixture validator with:

```sh
go run ./cmd/ads-fixture-validator
```

The Go validator is a second implementation path for the repository fixtures. It
does not call the Ruby reference processor or `check-jsonschema`; it reads the
same fixture expectations and checks schema-negative, conformance-negative,
strict-warning, and target-context outcomes independently.

## Agent Quickstart

Use `bin/ads` when an automation agent needs structured JSON instead of
diagnostic prose:

```sh
bin/ads validate --file examples/minimal.yaml --format json
bin/ads explain --file examples/minimal.yaml --context contexts/kubernetes-production.yaml --format json
bin/ads plan --file examples/minimal.yaml --context contexts/kubernetes-production.yaml --format json
bin/ads emit --file examples/minimal.yaml --context contexts/compose-single-host.yaml --target compose --output-dir "$(mktemp -d /private/tmp/ads-compose.XXXXXX)" --format json
bin/ads emit --file examples/minimal.yaml --context contexts/kubernetes-production.yaml --target kubernetes --output-dir "$(mktemp -d /private/tmp/ads-k8s.XXXXXX)" --format json
```

`plan` emits a deterministic `ADSDeploymentPlan` only after schema,
document-level, target-context, and profile compatibility checks pass. `emit`
consumes that plan and writes artifact bundles only; it never applies changes to
Docker, Kubernetes, clouds, policy engines, registries, or secret stores.

Current local emit adapters are intentionally narrow:

- `compose`, for `compose-single-host`
- `kubernetes`, for `kubernetes-production`

Other target contexts, including `serverless-auxiliary`, `air-gapped`,
`managed-container-runtime`, and future `gpu-serving` contexts, may validate or
plan when their required target-context support exists. This repository does
not yet include local emit adapters for those profiles. Unsupported emit
profiles are processor or adapter limitations, not ADS document-format errors.

For example, this command validates the serverless plan but asks the Kubernetes
adapter to emit a `serverless-auxiliary` target profile:

```sh
tmpdir="$(mktemp -d /private/tmp/ads-serverless.XXXXXX)"
bin/ads emit \
  --file examples/serverless-auxiliary.yaml \
  --context contexts/serverless-auxiliary.yaml \
  --target kubernetes \
  --output-dir "$tmpdir" \
  --format json
```

It exits `1` with a JSON envelope where `ok` is `false`, `phase` is `emit`,
`targetProfile` is `serverless-auxiliary`, `plan` is `null`, `artifacts` is
empty, and `errors` includes a `processor-limitation` diagnostic for the target
adapter mismatch.

The [Conformance GitHub Actions workflow](.github/workflows/conformance.yml) runs the Ruby fixture suite, Go tests, and independent Go fixture validator on pull requests, pushes to `main`, release branches, and version tags. It also publishes reference-processor SARIF diagnostics to GitHub Code Scanning when the workflow token has permission.

Validate the canonical example against only the JSON Schema with:

```sh
uvx check-jsonschema --schemafile schemas/ads.schema.json examples/minimal.yaml
```

Run the reference processor directly with:

```sh
ruby scripts/ads-conformance-check.rb examples/minimal.yaml
```

Use `--format json` or `--format sarif` for machine-readable diagnostics, and
`--output FILE` to write the formatted result to disk.

Validate an ADS document against a target context with:

```sh
ruby scripts/ads-conformance-check.rb --context contexts/kubernetes-production.yaml examples/minimal.yaml
```

The fixture suite also checks profile compatibility expectations: [examples/air-gapped.yaml](examples/air-gapped.yaml) is accepted by the air-gapped target context; [examples/serverless-auxiliary.yaml](examples/serverless-auxiliary.yaml) is accepted by the serverless auxiliary and Kubernetes target contexts; [examples/stateful-agent.yaml](examples/stateful-agent.yaml) is accepted by Kubernetes production and managed container runtime target contexts; and [examples/multi-agent.yaml](examples/multi-agent.yaml) and [examples/supply-chain.yaml](examples/supply-chain.yaml) are accepted only by the Kubernetes production target context.

The top-level files in `examples/*.yaml` are positive examples and should pass schema validation and document-level conformance checks. The files in `examples/invalid/` are negative schema fixtures and should fail schema validation. The files in `examples/conformance/invalid/` should pass schema validation but fail ADS conformance checks, including cross-reference and supply-chain consistency failures. The files in `examples/conformance/warnings/` exercise strict warning behavior for audit coverage, production threat-model coverage, and policy decision point coverage.

The `contexts/*.yaml` files are non-normative target-context fixtures for the reference processor. They describe available target profile capabilities, secret bindings, approval handlers, observability sinks, network controls, security policy enforcement, and supply-chain controls. The files in `contexts/invalid/` intentionally omit required target context support.

## Current Direction

ADS is intended to be a deployment and governance standard for production agentic systems, not another wrapper around `docker-compose.yml`. A conforming ADS document should describe:

- the runtime components that must run
- the platform capabilities required by those components
- the security boundaries, secrets, and network policies that apply
- the production threat model and mitigations reviewers need to evaluate
- the artifact integrity, signature, SBOM, and provenance requirements that apply
- the approval gates and policy decision points required before risky actions
- the observability signals needed for operations and auditability

See [SPEC.md](SPEC.md) for the current ADS model.
