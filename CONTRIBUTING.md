# Contributing

ADS is a draft specification, so useful contributions should make the standard
clearer, more implementable, or easier to validate. Prefer improving the
existing specification, examples, schema, conformance fixtures, and target
contexts before adding parallel documents.

## Development Setup

The fixture suite needs Ruby and either `check-jsonschema` or `uvx`.

Run all schema, conformance, warning, and target-context checks with:

```sh
ruby scripts/test-examples.rb
```

The [Conformance GitHub Actions workflow](.github/workflows/conformance.yml)
runs the same suite on pull requests and pushes to `main`.

Run the document-level conformance checker directly with:

```sh
ruby scripts/ads-conformance-check.rb examples/minimal.yaml
```

Validate an example against a target context with:

```sh
ruby scripts/ads-conformance-check.rb --context contexts/kubernetes-production.yaml examples/minimal.yaml
```

## Contribution Workflow

For every change, keep the specification, examples, schema, conformance
expectations, and documentation synchronized.

Use this checklist when changing ADS behavior:

- Update [SPEC.md](SPEC.md) when semantics, field meanings, conformance rules, or diagnostic expectations change.
- Update [schemas/ads.schema.json](schemas/ads.schema.json) when structural YAML requirements change.
- Update [examples/](examples/) when the change affects authoring guidance or expected usage.
- Update [contexts/](contexts/) when target-profile support or target fixtures change.
- Update [conformance/expectations.yaml](conformance/expectations.yaml) when schema, conformance, warning, or target-context outcomes change.
- Update [COMPATIBILITY.md](COMPATIBILITY.md) when example-to-target-context compatibility changes in a user-visible way.
- Run `ruby scripts/test-examples.rb`.

## Examples And Fixtures

Top-level files in `examples/*.yaml` are positive reference examples. They should
pass schema validation and document-level conformance checks.

Files in `examples/invalid/` are negative schema fixtures. They should fail JSON
Schema validation.

Files in `examples/conformance/invalid/` are schema-valid negative conformance
fixtures. They should pass schema validation but fail ADS processor conformance
checks.

Files in `examples/conformance/warnings/` exercise warning behavior. The fixture
suite runs them with `--strict-warnings` so warning expectations remain visible.

When adding an example:

- Reuse the names and structure of [examples/minimal.yaml](examples/minimal.yaml) unless the scenario requires different components.
- Add target-context expectations to [conformance/expectations.yaml](conformance/expectations.yaml).
- Update [COMPATIBILITY.md](COMPATIBILITY.md) when the example is part of the public compatibility matrix.
- Add at least one negative fixture when the new behavior creates a meaningful new failure mode.

## Target Contexts

Target contexts are non-normative fixtures for processor compatibility checks.
They describe available profile capabilities, secret bindings, approval
handlers, policy decision points, observability sinks, network controls,
security policy enforcement, and supply-chain controls.

When adding or changing a target context:

- Declare the intended `targetProfile`.
- Keep capability names aligned with [SPEC.md](SPEC.md).
- Avoid embedding real secret values, credentials, tokens, private keys, or production endpoint details.
- Add positive and negative expectations to [conformance/expectations.yaml](conformance/expectations.yaml).
- Update [COMPATIBILITY.md](COMPATIBILITY.md) when the target context is part of the public matrix.

## Schema And Conformance

Use JSON Schema for structural requirements that can be validated locally within
the document shape. Use the Ruby reference conformance processor documented in
[REFERENCE_PROCESSOR.md](REFERENCE_PROCESSOR.md) for cross-reference,
compatibility, target-context, and policy checks that require document-wide or
context-aware validation.

Add or update diagnostics when processor behavior changes. Diagnostics should
use stable machine-readable categories from [SPEC.md](SPEC.md#diagnostic-categories)
and should include enough context for a processor or authoring tool to explain
the failure.

Diagnostics must never include secret values, credentials, tokens, private keys,
or decrypted secret payloads.

## Governance

ADS uses the versioning policy in [SPEC.md](SPEC.md#versioning-policy).

Draft versions may introduce breaking changes, but incompatible authoring-format
changes should increment the draft API version. Breaking changes must update the
change log, schema expectations, reference examples, compatibility matrix, and
conformance fixtures together.

Stable versions must preserve backward compatibility within the same major
version. After v1.0, breaking changes require a new major version unless a field
was explicitly deprecated and removed in a later major version.

Independent processor implementation guidance is tracked in
[IMPLEMENTERS.md](IMPLEMENTERS.md).

Release readiness gates and release-candidate checklists are tracked in
[RELEASE.md](RELEASE.md).

New normative fields should be accepted only when they meet all of these
criteria:

- The behavior cannot be represented clearly with existing ADS fields.
- At least one reference example or target context demonstrates the behavior.
- Schema and conformance expectations can validate the behavior.
- The change preserves ADS' separation between deployment intent and platform-specific manifests.

New capabilities should be vendor-neutral, named consistently with the existing
capability vocabulary, and supported by at least one target context fixture or
explicitly documented as optional.

New profiles should state which ADS capabilities they can satisfy, include at
least one target context fixture, and define expected compatibility for the
current reference examples.

Extensions must use namespaced keys and must not redefine normative ADS fields.
Required extensions should be treated as unsupported unless a processor or
target context explicitly supports them.

## Review Checklist

Before merging a contribution, reviewers should check:

- The change updates every affected source of truth.
- The normative and informative sections remain clearly separated.
- Examples do not contain real credentials or sensitive deployment details.
- New diagnostics are stable, actionable, and mapped to documented categories.
- Independent processor guidance remains accurate when conformance requirements change.
- Reference processor behavior remains documented when command-line behavior, output format, scope, or limitations change.
- Compatibility expectations are explicit and tested.
- Release-impacting changes update [RELEASE.md](RELEASE.md) expectations when needed.
- `ruby scripts/test-examples.rb` passes.
