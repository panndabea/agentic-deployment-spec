# Release Readiness

This document is the operational release checklist for ADS. It is informative:
the normative specification remains [SPEC.md](SPEC.md), and the contribution
and governance process lives in [CONTRIBUTING.md](CONTRIBUTING.md).

## Release Gates

These recurring gates apply to the active release checklist. Historical checked
evidence for `v1.0.0` remains in the sections below.

A release is ready only when all of these gates are satisfied:

- [x] [SPEC.md](SPEC.md) reflects the intended normative behavior for the release.
- [x] [schemas/ads.schema.json](schemas/ads.schema.json) matches the structural requirements in the spec.
- [x] Reference examples in [examples/](examples/) match the current authoring guidance.
- [x] Target contexts in [contexts/](contexts/) match the supported compatibility profiles.
- [x] [conformance/expectations.yaml](conformance/expectations.yaml) captures all expected schema, conformance, warning, and target-context outcomes.
- [x] [COMPATIBILITY.md](COMPATIBILITY.md) matches the public example-to-target-context expectations.
- [x] [IMPLEMENTERS.md](IMPLEMENTERS.md) matches the current conformance model for independent processors.
- [x] [REFERENCE_PROCESSOR.md](REFERENCE_PROCESSOR.md) matches the behavior and limitations of the Ruby reference processor.
- [x] [CONTRIBUTING.md](CONTRIBUTING.md) describes the current contribution and governance process.
- [x] The change log in [SPEC.md](SPEC.md#change-log) summarizes release-impacting changes.
- [x] `ruby scripts/test-examples.rb` passes locally.
- [x] The Conformance GitHub Actions workflow passes for the release branch or tag.

## v1.1 Release Readiness

The `v1.1.0` release checklist is complete. `ads.dev/v1` remains the stable API
version.

- [x] Spec, status text, and change log updated for `v1.1.0`.
- [x] README, roadmap, and compatibility matrix updated for `v1.1.0`.
- [x] Compatibility audit against `v1.0.0` completed.
- [x] [COMPATIBILITY.md](COMPATIBILITY.md) checked against [conformance/expectations.yaml](conformance/expectations.yaml).
- [x] Plan snapshot coverage checked.
- [x] Artifact snapshot coverage checked.
- [x] CLI envelope coverage checked, including `explain`.
- [x] Unsupported emit-profile behavior documented.
- [x] Secret redaction evidence checked.
- [x] Local release commands passed.
- [x] GitHub Actions Conformance passed on the exact release branch or tag commit.

### v1.1 Compatibility Review

`ads.dev/v1` remains the stable ADS API version for the `v1.1.0` release.
The release adds compatible processor, fixture, CLI, artifact, and
target-context surface area: `bin/ads`, deterministic `ADSDeploymentPlan`
output, local Compose and Kubernetes artifact emission, plan and artifact
snapshots, SARIF output file support, `serverless-auxiliary` and `air-gapped`
fixtures, and secret payload redaction checks.

Compatibility audit notes:

- Compatibility audit performed on 2026-07-18 for release commit
  `998098b797d7a7f59cb6518f4ea83eb222b5fd0a`.
- Reviewed `git diff --name-status v1.0.0..HEAD`, the scoped
  `v1.0.0..HEAD` diff for the spec, schema, expectations, examples, contexts,
  processor, CLI, and Go validator, and the current uncommitted scoped diff.
- `v1.0.0..HEAD` adds implementation and fixture surface without changing the
  ADS source document API version.
- No required root field was added to `AgenticDeployment`.
- No optional ADS field was made required by the schema or processor.
- Existing standard capability, audit event, profile, diagnostic category, and
  required-field vocabulary is retained.
- `ADSDeploymentPlan` remains a processor artifact, not a required ADS source
  document kind.
- The current schema still requires only `apiVersion`, `kind`, `metadata`,
  `runtime`, `capabilities`, `secrets`, `security`, `approvals`, and
  `observability`; `apiVersion` remains `ads.dev/v1` and `kind` remains
  `AgenticDeployment`.
- [conformance/expectations.yaml](conformance/expectations.yaml) now records 21
  schema-positive fixtures, 5 schema-negative fixtures, 36 target-context
  expectations, 4 plan snapshots, 3 artifact snapshots, and 2 artifact rejects.
- Local emit support is intentionally limited to the `compose` adapter for
  `compose-single-host` and the `kubernetes` adapter for
  `kubernetes-production`; other profiles may still validate or plan.

### v1.1 Verification Evidence

- Release commit SHA: `998098b797d7a7f59cb6518f4ea83eb222b5fd0a`.
- Verification date: 2026-07-18.
- Local command results on 2026-07-18:
  - `git diff --check`: passed.
  - `ruby scripts/test-examples.rb`: passed, including `bin/ads explain`
    envelope coverage, artifact snapshots, artifact rejects, and redaction
    checks.
  - `go test ./...`: passed.
  - `go run ./cmd/ads-fixture-validator`: passed.
  - `bin/ads validate --file examples/minimal.yaml --format json`: passed with
    `ok: true`, `phase: validate`, no errors, and `plan: null`.
  - `bin/ads explain --file examples/minimal.yaml --context contexts/kubernetes-production.yaml --format json`:
    passed with `ok: true`, `target: kubernetes`,
    `targetProfile: kubernetes-production`, non-empty `summary`, `plan: null`,
    and empty `artifacts`.
  - `bin/ads plan --file examples/minimal.yaml --context contexts/kubernetes-production.yaml --format json`:
    passed with `ok: true` and an `ADSDeploymentPlan`.
  - `bin/ads emit --file examples/minimal.yaml --context contexts/compose-single-host.yaml --target compose --output-dir /private/tmp/ads-v1.1-compose-smoke.jDIXZQ --format json`:
    passed with `ok: true` and wrote only local files.
  - Compose smoke output directory:
    `/private/tmp/ads-v1.1-compose-smoke.jDIXZQ`.
  - Compose smoke output files: `compose.yaml`, `ads-plan.json`, and
    `README.md`.
  - Secret payload scan over `conformance/artifacts` and the Compose smoke
    output found no matches for `secretValue:`, `privateKey:`, `password:`,
    `token:`, `super-secret`, private-key headers, or `credential`.
- GitHub Actions workflow name: `Conformance`.
- GitHub Actions release tag run: `29657378848`, completed successfully for
  `v1.1.0` on commit `998098b797d7a7f59cb6518f4ea83eb222b5fd0a` at
  <https://github.com/panndabea/agentic-deployment-spec/actions/runs/29657378848>.
- GitHub Actions main baseline for the same commit: run `29657339788`,
  completed successfully at
  <https://github.com/panndabea/agentic-deployment-spec/actions/runs/29657339788>.
- Release tag: `v1.1.0`.
- GitHub release: <https://github.com/panndabea/agentic-deployment-spec/releases/tag/v1.1.0>.
- Historical baseline main evidence: Conformance run `29646050898` passed for
  `33a83b9a062181e324d317e4f5d356688d1cb278` on `main` at
  <https://github.com/panndabea/agentic-deployment-spec/actions/runs/29646050898>.

## v1.1 Release Publication

The final `v1.1.0` tag was pushed on July 18, 2026 for commit
`998098b797d7a7f59cb6518f4ea83eb222b5fd0a`.

The Conformance GitHub Actions workflow passed for the tag in run
`29657378848`, covering the Ruby fixture suite, SARIF diagnostics, Go tests, and
the independent Go fixture validator.

The GitHub release was published at
<https://github.com/panndabea/agentic-deployment-spec/releases/tag/v1.1.0>.

## v1.0 Readiness Checklist

The v1.0 stabilization pass is complete:

- [x] Decide and document the stable ADS API version for v1.0 according to [SPEC.md](SPEC.md#versioning-policy).
- [x] Remove or resolve stale draft-only language that conflicts with v1.0 stability.
- [x] Confirm that recognized profile names without current target context fixtures are intentionally retained.
- [x] Confirm that all required fields and conformance requirements are intentional.
- [x] Confirm that every diagnostic category in [SPEC.md](SPEC.md#diagnostic-categories) is stable enough for processors to depend on.
- [x] Confirm that every standard audit event in [SPEC.md](SPEC.md#audit-event-taxonomy) is stable enough for processors and operators.
- [x] Confirm that at least two deployment targets are covered by reference examples and target-context fixtures.
- [x] Confirm that [IMPLEMENTERS.md](IMPLEMENTERS.md) explains how independent processors should validate those fixtures.
- [x] Confirm that the in-repository reference processor is documented but not counted as the independent ADS processor.
- [x] Confirm that at least one independent ADS processor can validate the reference examples.
- [x] Confirm that breaking changes after v1.0 require a new major version unless a field has been explicitly deprecated first.

## v1.0 Spec/Schema/Fixtures Alignment Review

[SPEC.md](SPEC.md), [schemas/ads.schema.json](schemas/ads.schema.json), the
reference examples, target contexts, conformance expectations, and public
compatibility matrix are aligned for the v1.0 release surface.

The review checked the normative document model, YAML structure, validation
rules, processor conformance rules, diagnostic categories, audit event taxonomy,
deployment profile matrix, and canonical minimal example against the schema and
fixtures. The JSON Schema covers the structural requirements that are expressible
locally, including required root fields, required nested minima, standard enum
values, audit event names, namespaced extension keys, and the schema-detectable
egress default conflict. Cross-reference, warning, and target-context rules
remain processor conformance responsibilities as described in the spec.

The canonical minimal example in [SPEC.md](SPEC.md#minimal-example) matches
[examples/minimal.yaml](examples/minimal.yaml). All 21 example fixtures are
listed in [conformance/expectations.yaml](conformance/expectations.yaml) under
schema accept or reject expectations. The target-context expectations cover all
15 combinations of the five top-level reference examples and the three current
target contexts, plus the intentionally incomplete negative target context.
[COMPATIBILITY.md](COMPATIBILITY.md) matches those public example-to-target
expectations.

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

## v1.0 Independent Processor Review

The Go fixture validator in [cmd/ads-fixture-validator](cmd/ads-fixture-validator)
is a second implementation path for v1.0 fixture validation. It reads
[conformance/expectations.yaml](conformance/expectations.yaml), parses the ADS
and target-context fixture YAML, applies v1.0 structural and semantic checks,
evaluates strict-warning behavior and target-context compatibility, and compares
diagnostics against expected fixture substrings without invoking the Ruby
reference processor or `check-jsonschema`.

`go run ./cmd/ads-fixture-validator` passed locally against the current
reference examples, schema-negative fixtures, conformance-negative fixtures,
strict-warning fixtures, and target-context matrix. This satisfies the v1.0
release criterion for at least one independent ADS processor validating the
reference fixtures. External processors remain valuable follow-up evidence after
the v1.0 release.

## v1.0 Processor And Contributor Documentation Review

[IMPLEMENTERS.md](IMPLEMENTERS.md) matches the current independent processor
conformance model. It describes safe parsing, schema validation, normalization,
document-level checks, target-context checks, diagnostics, planning boundaries,
fixture comparison against [conformance/expectations.yaml](conformance/expectations.yaml),
and the second Go validation path.

[REFERENCE_PROCESSOR.md](REFERENCE_PROCESSOR.md) matches the Ruby reference
processor's current behavior and limitations: command-line options, exit codes,
text and JSON diagnostic formats, strict-warning behavior, target-context
evidence, fixture expectations, and the fact that it does not emit deployment
plans or call external platform, policy, observability, registry, or signature
verification APIs.

[CONTRIBUTING.md](CONTRIBUTING.md) now describes the current contribution and
governance process for v1.0 maintenance, including synchronized updates across
the spec, schema, examples, contexts, expectations, compatibility matrix, Ruby
fixture suite, and independent Go fixture validator when conformance behavior or
release-readiness evidence changes. The [SPEC.md change log](SPEC.md#change-log)
summarizes the release-impacting v1.0 changes, including stable API selection,
reference example and schema updates, diagnostic and audit taxonomy
stabilization, profile fixture coverage, processor conformance terminology,
extension expectations, and independent fixture validation guidance.

## v1.0 Breaking Change Review

[SPEC.md](SPEC.md#versioning-policy), [CONTRIBUTING.md](CONTRIBUTING.md#governance),
and this release checklist agree on the v1 compatibility rule: after v1.0,
breaking changes to `ads.dev/v1` documents require a new stable major API
version unless the affected field or behavior was explicitly deprecated first
and removed in a later major version.

Breaking changes include removing or renaming normative fields, changing field
semantics in a non-compatible way, making optional fields required, removing
standard capabilities, profiles, diagnostic categories, or audit events, or
changing fixture expectations in a way that invalidates supported target
behavior. Release-blocking changes before final v1.0 must update the change log,
schema, examples, conformance expectations, and compatibility documentation
together.

## Pre-Release Checklist

Use this checklist before cutting any release:

- [x] Review `git diff` for unrelated changes.
- [x] Run `git diff --check`.
- [x] Run `ruby scripts/test-examples.rb`.
- [x] Review [COMPATIBILITY.md](COMPATIBILITY.md) against [conformance/expectations.yaml](conformance/expectations.yaml).
- [x] Review [README.md](README.md) links and status language.
- [x] Review [ROADMAP.md](ROADMAP.md) for completed and remaining milestone criteria.
- [x] Confirm that examples and contexts contain no real secrets, credentials, tokens, private keys, or production-only endpoint details.
- [x] Confirm that new diagnostics do not expose secret values or decrypted secret payloads.

## v1.0 Pre-Release Local Review

The local pre-release checklist is complete for the current v1.0 release state.
The working diff was reviewed for unrelated changes,
and whitespace checks passed with `git diff --check`.

[README.md](README.md) status language matches the v1.0 release state,
its local documentation links and checked anchors resolve, and its validation
commands match the current Ruby fixture suite and independent Go fixture
validator. [ROADMAP.md](ROADMAP.md) matches the completed v1.0 criteria and
keeps the maintenance focus on compatibility, documentation alignment, and a
green conformance workflow.

[COMPATIBILITY.md](COMPATIBILITY.md) was checked against
[conformance/expectations.yaml](conformance/expectations.yaml): the public target
matrix covers all current top-level example and target-context combinations,
plus the intentionally incomplete negative target context. A focused scan of
[examples/](examples/) and [contexts/](contexts/) found placeholder secret
references only, not real credentials, tokens, private keys, or
production-only endpoint details. The Ruby reference processor and Go fixture
validator diagnostics were checked for secret-payload exposure paths.

## v1.0 Release Branch CI Review

The `release/v1.0-rc1` branch was created for the v1.0 release candidate. After
the final v1.0 status-language updates landed, the Conformance GitHub Actions
workflow passed for commit `95e69ac` on July 12, 2026 in run `29208435207`,
covering the Ruby fixture suite, Go tests, and the independent Go fixture
validator.

The final `v1.0.0` tag passed the same Conformance workflow on July 12, 2026 in
run `29208566123`.

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

- [x] Create a release branch or release-candidate tag.
- [x] Verify the Conformance workflow passes.
- [x] Freeze normative field additions except for release-blocking fixes.
- [x] Review [SPEC.md](SPEC.md), [README.md](README.md), [COMPATIBILITY.md](COMPATIBILITY.md), [CONTRIBUTING.md](CONTRIBUTING.md), and this file together.
- [x] Collect release-blocking issues in [ROADMAP.md](ROADMAP.md) or the project tracker.

## Final Release Flow

For a final release:

- [x] Confirm all release gates are satisfied.
- [x] Confirm no release-candidate-only language remains unless intentionally retained.
- [x] Tag the release with the project version.
- [x] Publish release notes from the spec change log and compatibility summary.
- [x] Keep the release tag immutable.
