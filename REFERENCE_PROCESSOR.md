# Reference Processor

[scripts/ads-conformance-check.rb](scripts/ads-conformance-check.rb) is the ADS
reference conformance processor used by this repository's fixture suite. It is
intended to make ADS processor behavior concrete enough for authors, reviewers,
and independent implementers to compare results.

The normative processor requirements remain in [SPEC.md](SPEC.md#processor-conformance).
This reference processor is not an independent implementation for v1.0 release
purposes; it is the in-repository executable reference for conformance fixtures.
Guidance for independent implementations lives in [IMPLEMENTERS.md](IMPLEMENTERS.md).

## Scope

The reference processor checks ADS document behavior that requires document-wide
or target-context-aware validation, including:

- required root fields and minimal `AgenticDeployment` structure
- unknown root-field compatibility warnings
- component name uniqueness and `dependsOn` resolution
- component-scoped secret and capability references
- policy decision point references and approval-action coverage
- recommended capability coverage for secrets, state, telemetry, approvals, egress, and supply chain
- standard audit event names and recommended audit coverage
- production threat-model coverage warnings
- conflicting outbound and egress defaults
- digest pinning when `supplyChain.images.requireDigest` is required
- target-context capability, secret, approval, policy, observability, network, security, and supply-chain feasibility
- extension namespace handling and required-extension rejection

The reference processor does not replace JSON Schema validation. The fixture
suite pairs it with [schemas/ads.schema.json](schemas/ads.schema.json) through
[scripts/test-examples.rb](scripts/test-examples.rb).

## Command Line

Validate one or more ADS documents:

```sh
ruby scripts/ads-conformance-check.rb examples/minimal.yaml
```

Validate against a target context:

```sh
ruby scripts/ads-conformance-check.rb --context contexts/kubernetes-production.yaml examples/minimal.yaml
```

Emit JSON diagnostics:

```sh
ruby scripts/ads-conformance-check.rb --format json examples/minimal.yaml
```

Treat warnings as failures:

```sh
ruby scripts/ads-conformance-check.rb --strict-warnings examples/conformance/warnings/missing-audit-coverage.yaml
```

## Exit Codes

| Exit code | Meaning |
|---:|---|
| `0` | No error diagnostics were emitted, and no warning diagnostics were emitted when `--strict-warnings` is enabled. |
| `1` | At least one error diagnostic was emitted, or at least one warning diagnostic was emitted with `--strict-warnings`. |
| `2` | The invocation is invalid, required files cannot be loaded, the target context is malformed, or an unsupported output format was requested. |

## Diagnostic Format

Text output emits one line per diagnostic:

```text
FILE: SEVERITY: CATEGORY: PATH: MESSAGE
```

JSON output emits a list of file results:

```json
[
  {
    "file": "examples/minimal.yaml",
    "diagnostics": [
      {
        "category": "capability-unsupported",
        "severity": "error",
        "path": "$.capabilities.required[0]",
        "message": "Required capability is not supported by the target context."
      }
    ]
  }
]
```

Diagnostics use the categories documented in
[SPEC.md](SPEC.md#diagnostic-categories). They must not include secret values,
credentials, tokens, private keys, or decrypted secret payloads.

## Target Contexts

Target contexts are non-normative fixtures that describe what a processor can
prove about a selected deployment environment before planning. The current
fixtures live in [contexts/](contexts/).

The reference processor treats a target context as evidence for:

- supported capabilities
- secret bindings
- approval handlers
- policy decision points
- observability sinks
- egress and network controls
- sandbox and tool-policy controls
- signature, SBOM, and provenance controls

If no target context is supplied, the processor performs document-level checks
only.

## Fixture Expectations

The machine-readable expected behavior for the reference processor lives in
[conformance/expectations.yaml](conformance/expectations.yaml). The fixture
suite uses that manifest to verify:

- schema-positive and schema-negative fixtures
- document-level conformance-positive and conformance-negative fixtures
- warning fixtures under `--strict-warnings`
- target-context compatibility expectations

Independent ADS processors should be able to reproduce equivalent pass/fail
outcomes and compatible diagnostic categories for the same fixtures, even when
their messages or internal implementation differ.

## Limitations

The reference processor is intentionally small. It does not:

- emit deployment plans
- call Kubernetes, cloud, secrets, policy, observability, registry, or signature-verification APIs
- verify real image signatures, SBOM documents, or provenance attestations
- evaluate policy logic
- prove runtime security isolation
- replace a full production security review

Those behaviors belong to deployment agents, platform controllers, or
environment-specific processors. The reference processor checks whether an ADS
document and target context declare enough information for such systems to make
safe decisions.

## Updating The Reference Processor

When changing reference processor behavior:

- Update [SPEC.md](SPEC.md) when normative conformance behavior changes.
- Update [conformance/expectations.yaml](conformance/expectations.yaml) when fixture outcomes or expected diagnostics change.
- Update [COMPATIBILITY.md](COMPATIBILITY.md) when public target compatibility changes.
- Update this document when command-line behavior, output format, scope, or limitations change.
- Run `ruby scripts/test-examples.rb`.
