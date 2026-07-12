# Release Readiness

This document is the operational release checklist for ADS. It is informative:
the normative specification remains [SPEC.md](SPEC.md), and the contribution
and governance process lives in [CONTRIBUTING.md](CONTRIBUTING.md).

## Release Gates

A release is ready only when all of these gates are satisfied:

- [ ] [SPEC.md](SPEC.md) reflects the intended normative behavior for the release.
- [ ] [schemas/ads.schema.json](schemas/ads.schema.json) matches the structural requirements in the spec.
- [ ] Reference examples in [examples/](examples/) match the current authoring guidance.
- [ ] Target contexts in [contexts/](contexts/) match the supported compatibility profiles.
- [ ] [conformance/expectations.yaml](conformance/expectations.yaml) captures all expected schema, conformance, warning, and target-context outcomes.
- [ ] [COMPATIBILITY.md](COMPATIBILITY.md) matches the public example-to-target-context expectations.
- [ ] [IMPLEMENTERS.md](IMPLEMENTERS.md) matches the current conformance model for independent processors.
- [ ] [REFERENCE_PROCESSOR.md](REFERENCE_PROCESSOR.md) matches the behavior and limitations of the Ruby reference processor.
- [ ] [CONTRIBUTING.md](CONTRIBUTING.md) describes the current contribution and governance process.
- [ ] The change log in [SPEC.md](SPEC.md#change-log) summarizes release-impacting changes.
- [ ] `ruby scripts/test-examples.rb` passes locally.
- [ ] The Conformance GitHub Actions workflow passes for the release branch or tag.

## v1.0 Readiness Checklist

Before publishing v1.0, complete this stabilization pass:

- [x] Decide and document the stable ADS API version for v1.0 according to [SPEC.md](SPEC.md#versioning-policy).
- [x] Remove or resolve stale draft-only language that conflicts with v1.0 stability.
- [x] Confirm that recognized profile names without current target context fixtures are intentionally retained.
- [x] Confirm that all required fields and conformance requirements are intentional.
- [x] Confirm that every diagnostic category in [SPEC.md](SPEC.md#diagnostic-categories) is stable enough for processors to depend on.
- [x] Confirm that every standard audit event in [SPEC.md](SPEC.md#audit-event-taxonomy) is stable enough for processors and operators.
- [x] Confirm that at least two deployment targets are covered by reference examples and target-context fixtures.
- [x] Confirm that [IMPLEMENTERS.md](IMPLEMENTERS.md) explains how independent processors should validate those fixtures.
- [x] Confirm that the in-repository reference processor is documented but not counted as the independent ADS processor.
- [ ] Confirm that at least one independent ADS processor can validate the reference examples.
- [ ] Confirm that breaking changes after v1.0 require a new major version unless a field has been explicitly deprecated first.

## v1.0 Required Surface Review

The v1.0 required field set is intentional. Required root fields are
`apiVersion`, `kind`, `metadata`, `runtime`, `capabilities`, `secrets`,
`security`, `approvals`, and `observability`. They match
[SPEC.md](SPEC.md#document-model), [schemas/ads.schema.json](schemas/ads.schema.json),
and the Ruby reference processor's minimal structure checks.

The required nested minima are also intentional: ownership metadata, at least
one runtime component, capability and secret lists, sandbox and tool-policy
defaults, approval and observability lists, and the per-entry fields needed to
make secrets, approvals, components, and policy decision points reviewable. The
schema validates structural requirements; processor conformance covers
cross-reference checks, target-context compatibility, security and network
feasibility, supply-chain checks, observability binding, extension handling, and
diagnostics before planning.

The Ruby reference processor remains a fixture reference rather than a complete
deployment planner. Its documented limitations are acceptable for v1.0 because
independent processors must still preserve or reject required ADS behavior
against their concrete target contexts.

## v1.0 Diagnostic Category Review

The diagnostic categories in [SPEC.md](SPEC.md#diagnostic-categories) are
stable for v1.0. The Ruby reference processor emits only standard categories,
and rejecting or strict-warning fixtures assert representative diagnostic
substrings for document-level errors, warning categories, target-context
compatibility failures, unknown root-field compatibility warnings, and required
extension rejection.

`schema-invalid` is covered by schema-negative fixtures and parser or minimal
structure failures rather than by a conformance-negative fixture with
`expectedDiagnostics`, because structurally invalid ADS documents must fail
before deployment planning.

`processor-limitation` is intentionally reserved for processors and target
platforms that cannot preserve a required runtime model during planning. The
in-repository Ruby reference processor does not currently emit it because it
does not emit deployment plans.

## v1.0 Audit Event Taxonomy Review

The standard audit event taxonomy in [SPEC.md](SPEC.md#audit-event-taxonomy) is
stable for v1.0. The 25 standard event names in the specification match
[schemas/ads.schema.json](schemas/ads.schema.json) and the Ruby reference
processor's `STANDARD_AUDIT_EVENTS` list exactly.

ADS documents may use standard event names or namespaced custom event names.
Unqualified custom event names are intentionally rejected by the schema, as
covered by [examples/invalid/unknown-audit-event.yaml](examples/invalid/unknown-audit-event.yaml).
Some standard events are not emitted by current reference examples; they remain
reserved for deployment, secret-rotation, network, tool, and state lifecycle
events that production processors and operators need to model consistently.

## v1.0 Target Coverage Review

ADS v1.0 covers three reference deployment targets with target-context fixtures:
`compose-single-host`, `managed-container-runtime`, and
`kubernetes-production`. These exceed the v1.0 requirement for at least two
deployment targets.

[COMPATIBILITY.md](COMPATIBILITY.md) is the human-readable compatibility matrix,
and [conformance/expectations.yaml](conformance/expectations.yaml) is the
machine-readable source of truth. The fixture suite verifies positive
compatibility for the minimal and approval-policy examples across all three
targets, richer examples against the targets that claim their required
capabilities, and negative compatibility outcomes when smaller targets cannot
satisfy multi-agent, stateful, or supply-chain requirements.

## v1.0 Implementer Fixture Review

[IMPLEMENTERS.md](IMPLEMENTERS.md) explains how independent ADS processors
should validate the repository fixtures. It identifies the schema-positive,
schema-negative, conformance-positive, conformance-negative, strict-warning, and
target-context fixture groups in [conformance/expectations.yaml](conformance/expectations.yaml),
and it describes the expected comparison contract for pass/fail outcomes,
compatible diagnostic categories, document paths, and `expectedDiagnostics`
substrings.

The guide also makes clear that exact diagnostic wording, language, and internal
architecture do not need to match the Ruby reference processor. Independent
processors must match ADS semantics and fixture outcomes, preserve required ADS
behavior during planning, or decline to plan.

## v1.0 Reference Processor Independence Review

The in-repository Ruby reference processor is documented in
[REFERENCE_PROCESSOR.md](REFERENCE_PROCESSOR.md) as the executable reference for
repository conformance fixtures. It is intentionally small, does not emit
deployment plans, and is not an independent ADS implementation for v1.0 release
purposes.

[IMPLEMENTERS.md](IMPLEMENTERS.md) separately defines what an independent
processor should demonstrate for v1.0. The Ruby reference processor can help
other implementations compare fixture behavior, but it does not satisfy the
independent processor release criterion by itself.

## Pre-Release Checklist

Use this checklist before cutting any release:

- [ ] Review `git diff` for unrelated changes.
- [ ] Run `git diff --check`.
- [ ] Run `ruby scripts/test-examples.rb`.
- [ ] Review [COMPATIBILITY.md](COMPATIBILITY.md) against [conformance/expectations.yaml](conformance/expectations.yaml).
- [ ] Review [README.md](README.md) links and status language.
- [ ] Review [ROADMAP.md](ROADMAP.md) for completed and remaining milestone criteria.
- [ ] Confirm that examples and contexts contain no real secrets, credentials, tokens, private keys, or production-only endpoint details.
- [ ] Confirm that new diagnostics do not expose secret values or decrypted secret payloads.

## Version And Change Log

Every release should make version intent explicit:

- Update status language in [README.md](README.md) and [SPEC.md](SPEC.md) when the project moves between draft, release-candidate, and stable states.
- Update the change log in [SPEC.md](SPEC.md#change-log) with release-impacting behavior changes.
- Increment the ADS API version when the authoring format changes incompatibly during draft development.
- For v1.0 and later, preserve backward compatibility within the same major version.
- Record deprecations before removing fields in a later major version.

## Breaking Change Review

Treat a change as breaking when it would cause a previously conforming ADS
document to fail without an intentional major-version or draft API-version
change.

Breaking changes include:

- Removing or renaming a normative field.
- Changing the meaning of a field in a way existing processors cannot preserve.
- Making an optional field required.
- Removing a standard capability, profile, diagnostic category, or audit event.
- Changing fixture expectations in a way that invalidates existing supported target behavior.

Before accepting a breaking change:

- [ ] Document the rationale in the change log or roadmap.
- [ ] Update schema, examples, conformance expectations, and compatibility docs together.
- [ ] Decide whether the change requires a new draft API version or a new stable major version.

## Release Candidate Flow

For a release candidate:

- [ ] Create a release branch or release-candidate tag.
- [ ] Verify the Conformance workflow passes.
- [ ] Freeze normative field additions except for release-blocking fixes.
- [ ] Review [SPEC.md](SPEC.md), [README.md](README.md), [COMPATIBILITY.md](COMPATIBILITY.md), [CONTRIBUTING.md](CONTRIBUTING.md), and this file together.
- [ ] Collect release-blocking issues in [ROADMAP.md](ROADMAP.md) or the project tracker.

## Final Release Flow

For a final release:

- [ ] Confirm all release gates are satisfied.
- [ ] Confirm no release-candidate-only language remains unless intentionally retained.
- [ ] Tag the release with the project version.
- [ ] Publish release notes from the spec change log and compatibility summary.
- [ ] Keep the release tag immutable.
