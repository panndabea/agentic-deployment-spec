# Implementers Guide

This guide is for people building an independent ADS processor. An ADS
processor is any tool, agent, platform controller, CI job, or deployment system
that reads an ADS document and attempts to validate, plan, deploy, or operate
the described system.

The normative requirements remain in [SPEC.md](SPEC.md). This guide explains a
practical implementation path and how to compare behavior against the repository
fixtures and the Ruby reference processor documented in
[REFERENCE_PROCESSOR.md](REFERENCE_PROCESSOR.md).

## Implementation Layers

Build processors in layers. Each layer should produce diagnostics without
silently dropping required ADS behavior.

1. Parse YAML safely.
2. Validate structural schema requirements.
3. Normalize authoring shortcuts.
4. Run document-level conformance checks.
5. Run target-context compatibility checks.
6. Emit stable diagnostics.
7. Decide whether planning can continue.

## Parsing And Schema Validation

Processors should parse ADS YAML with a safe parser that rejects unsupported
aliases, unexpected object deserialization, and malformed YAML.

After parsing, validate the document against
[schemas/ads.schema.json](schemas/ads.schema.json). JSON Schema should handle
local structural rules such as required sections, field types, enum-like string
values, and basic document shape.

Schema validation should happen before deployment planning. A processor may
continue collecting additional diagnostics after a schema error when practical,
but it must not emit a deployment plan for a structurally invalid ADS document.

## Normalization

Normalize authoring shortcuts before compatibility checks:

- Convert string capability entries to objects with `name`.
- Treat missing optional collections as empty lists or maps where the spec allows them.
- Preserve document paths for diagnostics after normalization.
- Preserve original names and casing for component names, capability names, approval actions, policy decision points, audit events, and extension keys.

Normalization must not weaken or remove required behavior.

## Document-Level Checks

Document-level checks do not require a target context. Implement at least these
checks from [SPEC.md](SPEC.md#processor-conformance):

- component name uniqueness
- `dependsOn` resolution
- component-scoped secret reference resolution
- component-scoped capability reference resolution
- policy decision point reference resolution
- policy decision point `appliesTo` coverage
- recommended capability coverage for secrets, state, telemetry, approvals, egress, and supply chain
- standard audit event names and namespaced custom audit events
- recommended audit event coverage
- production threat-model coverage
- conflicting `security.outbound` and `networking.egress` defaults
- digest pinning when `supplyChain.images.requireDigest` is `true`
- namespaced extension keys and unsupported required extensions

Document-level errors block deployment planning. Warnings should be visible to
authors and may block planning when the processor is running in a strict mode.

## Target Context Checks

Target contexts describe what the selected deployment environment can satisfy.
They are non-normative fixtures in this repository, but the model is useful for
real processors that need to validate against a concrete environment.

A processor should check whether the target context can satisfy:

- required capabilities
- required secret bindings
- approval handlers for each approval mode
- policy decision points referenced by policy-based approvals
- observability sinks for required traces, metrics, logs, and audit events
- required ingress, internal traffic, egress destinations, and default-deny policies
- sandbox, tool-policy, identity, hardening, and trust-boundary requirements
- required digest pinning, signature verification, SBOM availability, and provenance controls

If a required behavior cannot be preserved, the processor must emit an error and
must not emit a deployment plan.

## Diagnostics

Diagnostics should use stable machine-readable categories from
[SPEC.md](SPEC.md#diagnostic-categories). A diagnostic should include:

- `category`
- `severity`
- `path`
- `message`

When useful, include additional machine-readable fields such as:

- `requirement`
- `targetProfile`
- `capability`
- `component`
- `remediation`

Processors should surface all detected errors in one validation response when
practical. Diagnostics must never include secret values, credentials, tokens,
private keys, or decrypted secret payloads.

## Planning Boundary

Validation and planning are separate phases.

A processor must not emit a deployment plan when:

- the ADS document is structurally invalid
- a required reference cannot be resolved
- a required capability is unsupported
- a required secret binding is missing
- a required approval or policy handler is unavailable
- a required network, security, observability, or supply-chain behavior cannot be preserved
- a required extension is unsupported

When planning is allowed, the plan must preserve the declared ADS behavior. It
must not silently replace required behavior with a weaker platform behavior.

For the repository reference implementation, planning is gated by
`Ads::Processor.validate_for_planning(file:, context_file:, strict_warnings:)`.
That gate requires exactly one ADS document and exactly one target context. The
target context must declare `targetProfile`, and if the ADS document declares
`profiles`, the selected target profile must be listed there. Profile mismatch
is a blocking `processor-limitation` diagnostic at `$.profiles`.

## Deployment Plan Artifact

`bin/ads plan` emits an `ADSDeploymentPlan` processor artifact. It is not an ADS
source document and should not be validated with `schemas/ads.schema.json`.

The plan uses `apiVersion: ads.dev/v1`, `kind: ADSDeploymentPlan`, and
`planVersion: 1`. It includes:

- source document and target context paths
- selected target profile and normalized target capabilities
- runtime components in dependency-safe order, preserving original ADS names and generated resource names
- required and optional capabilities with `sourcePath`
- required secrets with redacted target binding metadata only
- networking, security, approvals, observability, supply-chain, and reliability intent
- deterministic planned actions with source paths
- non-blocking warning diagnostics carried forward

Plans must not include timestamps by default. They must not include secret
values, tokens, credentials, private keys, decrypted payloads, or native secret
data.

## Agent JSON Envelope

`bin/ads` is the stable agent-facing CLI for `validate`, `explain`, `plan`, and
`emit`. Every command emits one JSON object with:

- `ok`
- `phase`
- `file`
- `context`
- `target`
- `targetProfile`
- `diagnostics`
- `errors`
- `warnings`
- `plan`
- `artifacts`
- `nextActions`

Agents should branch on `ok`, `errors`, and `nextActions`, not on human prose.
CLI invocation failures use `invocation-invalid` and exit `2`. ADS validation,
compatibility, strict-warning, planning, and emit failures exit `1`.

## Artifact Adapters

Adapters consume only an `ADSDeploymentPlan` object or parsed plan JSON. They
must not reread the ADS YAML or target context YAML. The repository includes:

- `compose`, for `compose-single-host`
- `kubernetes`, for `kubernetes-production`

Target contexts such as `serverless-auxiliary`, `air-gapped`,
`managed-container-runtime`, and future `gpu-serving` contexts may validate or
plan when their required support exists, but this repository does not currently
include local emit adapters for those profiles. An unsupported profile for a
known adapter is a processor or adapter limitation, not an ADS document-format
error. For example, a `serverless-auxiliary` plan passed to the `kubernetes`
adapter should be rejected with a JSON envelope containing a
`processor-limitation` diagnostic rather than silently emitted as Kubernetes
resources.

Adapters must verify plan kind, API version, target profile, and blocking
diagnostics before writing. They write deterministically into an empty output
directory and refuse output-directory conflicts. Generated artifacts preserve
requirements as native resources when possible and as explicit built-in-resource
or extension stubs otherwise. They never apply artifacts to Docker,
Kubernetes, cloud runtimes, policy engines, registries, observability systems,
or secret stores.

## Conformance Fixtures

Use [conformance/expectations.yaml](conformance/expectations.yaml) as the
machine-readable fixture expectation manifest. It defines expected behavior for:

- schema-positive documents
- schema-negative documents
- document-level conformance failures
- warning fixtures under strict warning behavior
- target-context compatibility outcomes
- planning-gate rejects and exact plan snapshots
- exact artifact bundle snapshots

Independent processors should validate the fixture groups in the same order as
the repository suite:

1. Accept every file in `schema.accepts` under JSON Schema validation.
2. Reject every file in `schema.rejects` before deployment planning.
3. Accept every file in `conformance.accepts` under document-level checks.
4. Reject every file in `conformance.rejects` with compatible diagnostics.
5. Surface every file in `conformance.warns` when warnings are treated as
   failures.
6. Evaluate each `targetContexts` entry against its declared context and match
   the expected accept or reject outcome.
7. Compare each plan fixture as exact deterministic pretty-printed JSON.
8. Compare artifact fixture directories file-by-file.

Independent processors should be able to reproduce equivalent pass/fail outcomes
and compatible diagnostic categories for the reference fixtures. Exact wording
does not need to match the Ruby reference processor, but diagnostics should be
specific enough for authors and tools to locate and fix the issue. For fixture
entries with `expectedDiagnostics`, processors should emit diagnostics that
contain equivalent categories and point to equivalent document paths or target
requirements, even when message text differs.

Rejecting conformance fixtures, strict-warning fixtures, and rejecting
target-context expectations declare `expectedDiagnostics` substrings that the
repository test suite checks. Treat those substrings as the stable compatibility
contract for fixture reasons, especially diagnostic categories and document
paths.

## Compatibility Matrix

[COMPATIBILITY.md](COMPATIBILITY.md) summarizes the public target-context matrix.
Use it as the human-readable companion to
[conformance/expectations.yaml](conformance/expectations.yaml).

When adding processor support for a new target class, make sure the processor can
explain both positive and negative compatibility outcomes. A smaller target
context should fail clearly when it cannot satisfy a richer production example.

## Extension Handling

Unknown extension keys may be ignored only when they are namespaced and not
marked as required. Required extensions must be supported explicitly by the
processor or target context.

Vendor-specific extensions must not redefine normative ADS fields. If an
extension changes deployment behavior, the processor should include enough
diagnostic and planning information for reviewers to see whether required ADS
behavior is preserved.

## Security Expectations

Processors should assume ADS documents and target contexts may be user-authored.

Implementers should:

- parse input safely
- avoid loading arbitrary classes or executing input content
- avoid logging secret payloads
- redact credentials in diagnostics and plans
- distinguish secret references from secret values
- fail closed for unavailable policy or approval controls unless the ADS document explicitly allows another behavior
- avoid planning network, security, or supply-chain behavior that the target environment cannot enforce

## Comparing Against The Reference Processor

The Ruby reference processor is documented in
[REFERENCE_PROCESSOR.md](REFERENCE_PROCESSOR.md). Use it to understand the
repository fixture behavior and diagnostic categories.

An independent processor does not need to share the same language, architecture,
CLI, or exact messages. It should match the specification semantics and the
fixture outcomes.

For local comparison:

```sh
ruby scripts/test-examples.rb
```

For a second, non-Ruby implementation path over the same fixture expectations:

```sh
go run ./cmd/ads-fixture-validator
```

The Go fixture validator is intentionally small and dependency-free. It parses
the repository fixture YAML, applies stable ADS v1 structural and semantic checks,
evaluates target contexts, and compares diagnostics against
[conformance/expectations.yaml](conformance/expectations.yaml) without invoking
the Ruby reference processor.

For a single document:

```sh
ruby scripts/ads-conformance-check.rb --format json --context contexts/kubernetes-production.yaml examples/minimal.yaml
```

Use `--format sarif --output FILE` when publishing reference-processor
diagnostics into CI or code scanning systems.

## Stable ADS v1 Readiness For Independent Processors

For stable ADS v1, an independent processor should demonstrate that it can:

- validate the current reference examples
- reject the schema-negative fixtures
- reject the conformance-negative fixtures with compatible diagnostic categories
- surface warning fixtures when running in strict warning mode
- evaluate target-context compatibility using the current context fixtures
- preserve required ADS behavior during planning or decline to plan
- avoid exposing secrets in diagnostics or plans

The in-repository Ruby reference processor does not satisfy the independent
processor release criterion by itself. It is the executable reference used to
help other implementations converge.
