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

## Conformance Fixtures

Use [conformance/expectations.yaml](conformance/expectations.yaml) as the
machine-readable fixture expectation manifest. It defines expected behavior for:

- schema-positive documents
- schema-negative documents
- document-level conformance failures
- warning fixtures under strict warning behavior
- target-context compatibility outcomes

Independent processors should be able to reproduce equivalent pass/fail outcomes
and compatible diagnostic categories for the reference fixtures. Exact wording
does not need to match the Ruby reference processor, but diagnostics should be
specific enough for authors and tools to locate and fix the issue.

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

For a single document:

```sh
ruby scripts/ads-conformance-check.rb --format json --context contexts/kubernetes-production.yaml examples/minimal.yaml
```

## v1.0 Readiness For Independent Processors

For v1.0, an independent processor should demonstrate that it can:

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
