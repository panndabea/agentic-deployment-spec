# ADS Agent Usability Implementation Plan

This is the reviewed execution plan for turning ADS from a stable validation
specification into an agent-usable planning and artifact-emission workflow.
It is intentionally strict: a coding agent should be able to implement it
without guessing about command shape, file locations, blocking behavior, or test
coverage.

## Objective

Implement three product-critical layers for agent adoption:

1. A deterministic, machine-readable ADS deployment plan emitted only after
   validation and target-context compatibility pass.
2. Concrete target adapters that consume that plan and emit deployable artifact
   bundles without applying anything to a live runtime.
3. A stable agent-facing CLI surface for `validate`, `explain`, `plan`, and
   `emit` workflows.

The implementation must preserve the ADS v1 contract. Required ADS behavior
must never be silently dropped, weakened, inferred away, or replaced with a
non-equivalent platform behavior.

## Repository Baseline

Current anchors that must remain compatible:

- `SPEC.md` defines the normative ADS v1 processor and planning boundary.
- `IMPLEMENTERS.md` describes processor layers, diagnostics, and the planning
  boundary.
- `REFERENCE_PROCESSOR.md` documents `scripts/ads-conformance-check.rb`.
- `schemas/ads.schema.json` validates ADS document shape.
- `conformance/expectations.yaml` defines fixture expectations.
- `contexts/*.yaml` model target context capabilities.
- `examples/*.yaml` provide positive production-oriented ADS documents.
- `scripts/test-examples.rb` runs schema, conformance, SARIF, and
  target-context fixture checks.
- `scripts/ads-conformance-check.rb` is currently a monolithic Ruby reference
  checker with `--format text|json|sarif`, `--context`, `--output`, and
  `--strict-warnings`.
- `cmd/ads-fixture-validator` is the independent Go fixture validator.
- `.github/workflows/conformance.yml` runs `ruby scripts/test-examples.rb`,
  `go test ./...`, and `go run ./cmd/ads-fixture-validator`.

Do not break existing conformance behavior or output formats. Extend in small,
tested layers.

## Review Corrections Incorporated

The previous draft had several implementation risks. This version fixes them:

- Do not overload the existing checker's `--format json` output. It currently
  emits a legacy list of file results and should remain backward-compatible.
- Do not reuse the existing checker's `--output` flag as an artifact directory.
  It currently means "write formatted diagnostics to this file".
- Do not add ambiguous `--plan` or `--format plan-json` flags to the legacy
  checker. Add `bin/ads` for agent-facing subcommands.
- Do not plan from the current Ruby conformance checks alone. Planning must be
  gated by structural schema validation plus document-level and target-context
  checks.
- Do not include timestamps in plan or artifact fixtures by default.
- Do not generate Kubernetes custom resources that may not exist in a cluster.
  Use built-in Kubernetes resources for stubs unless a target context explicitly
  declares support for a CRD.
- Do not generate native secret payloads. Emit references and redacted binding
  metadata only.
- Do not allow adapters to reread the ADS YAML. The plan must contain all
  target-preserving information the adapters need.

## Non-Negotiable Constraints

- Validation, planning, and artifact emission are separate phases.
- Planning requires exactly one ADS document and exactly one target context.
- A target context must include a concrete `targetProfile`.
- If the ADS document declares `profiles`, the selected `targetProfile` must be
  listed there before planning or emitting.
- A profile mismatch is a blocking `processor-limitation` diagnostic at
  `$.profiles`.
- CLI invocation problems that are not ADS document diagnostics use
  `invocation-invalid` and exit `2`.
- Errors block planning and emitting. Warnings do not block by default, but they
  block when `--strict-warnings` is supplied.
- Schema-invalid documents must never produce a plan.
- Incompatible document/context pairs must never produce a plan or artifacts.
- Every plan item that represents ADS behavior must retain enough source-path
  information to explain where it came from.
- Secret values, tokens, credentials, private keys, and decrypted payloads must
  never appear in diagnostics, plans, generated artifacts, logs, snapshots, or
  README output.
- Generated output must be deterministic: stable ordering, stable key order
  where practical, stable filenames, and no timestamps unless an explicit
  non-default flag is added later.
- No command in this plan applies changes to Kubernetes, Docker, cloud
  runtimes, policy engines, registries, or secret stores.

## Phase 0: Shared Processor Core

### Goal

Extract the existing Ruby checker into reusable code without changing its
current CLI behavior. Add a planning-safe validation result that includes schema
status, conformance diagnostics, target-context diagnostics, warning handling,
and target profile information.

### Required File Layout

Create these files:

```text
scripts/lib/ads/
  diagnostic.rb
  io.rb
  processor.rb
  validation_result.rb
```

Keep `scripts/ads-conformance-check.rb` as the legacy CLI entry point. It should
load the shared code and continue to accept:

```sh
ruby scripts/ads-conformance-check.rb [--format text|json|sarif] [--context FILE] [--output FILE] [--strict-warnings] FILE...
```

### Implementation Requirements

1. Move constants and pure helper methods from `scripts/ads-conformance-check.rb`
   into shared modules under `scripts/lib/ads/`.
2. Keep safe YAML loading: use `YAML.safe_load` with no permitted classes,
   no permitted symbols, and `aliases: false`.
3. Introduce `Ads::ValidationResult` with:
   - `file`
   - `context_file`
   - `document`
   - `context`
   - `target_profile`
   - `diagnostics`
   - `errors`
   - `warnings`
   - `ok?`
   - `blocking?`
   - `strict_warnings`
4. Add a planning gate method, for example:

   ```ruby
   Ads::Processor.validate_for_planning(file:, context_file:, strict_warnings: false)
   ```

   This method must return an `Ads::ValidationResult`.

5. Planning validation must run these checks in order:
   - safe YAML parse for the ADS document
   - structural schema checks equivalent to `schemas/ads.schema.json` for the
     fields used by this repository's fixtures
   - existing document-level conformance checks
   - target-context loading and target-context compatibility checks
   - selected target profile check
6. If adding a full Ruby JSON Schema dependency is not desired, implement the
   same dependency-free structural schema gate already covered independently by
   `cmd/ads-fixture-validator`. It must at minimum reject the current
   `conformance/expectations.yaml` `schema.rejects` fixtures with
   `schema-invalid` diagnostics before planning.
7. Add dependency-cycle detection for `runtime.components[].dependsOn`.
   Cycles are `reference-invalid` errors and block planning.
8. Add deterministic Kubernetes/Compose resource-name normalization helpers:
   - preserve original ADS names in the plan
   - produce DNS-safe names for generated artifacts
   - fail with `processor-limitation` if two ADS names normalize to the same
     generated resource name
9. Add a secret-redaction helper used by diagnostics, plan generation, adapter
   generation, JSON envelopes, and tests. Include an allowlist for secret binding
   fields that may be emitted: `name`, `source`, `ref`, `injection`, `reload`,
   `for`, and `purpose`.
10. Preserve legacy JSON/SARIF/text output from `scripts/ads-conformance-check.rb`.

### Tests

Update `scripts/test-examples.rb` so it still runs all existing checks and also
tests the shared processor core:

- each `schema.rejects` fixture blocks planning
- warnings block planning only with `--strict-warnings`
- an incompatible target context blocks planning
- a selected `targetProfile` missing from ADS `profiles` blocks planning with
  `processor-limitation`
- dependency cycles produce `reference-invalid`
- name-normalization collisions produce `processor-limitation`
- redaction removes inline secret-like values from output

Add any new negative fixtures under these directories:

```text
examples/conformance/invalid/
contexts/invalid/
```

Register new fixture expectations in `conformance/expectations.yaml`.

### Acceptance Criteria

- `scripts/ads-conformance-check.rb` behaves the same for existing documented
  commands.
- `ruby scripts/test-examples.rb` still passes.
- `go test ./...` still passes.
- `go run ./cmd/ads-fixture-validator` still passes.
- `Ads::Processor.validate_for_planning` exists and blocks all schema,
  conformance, strict-warning, and target-context failures required above.

## Phase 1: Machine-Readable ADS Deployment Plan

### Goal

Add a deterministic planner that converts a validated ADS document plus target
context into a stable intermediate plan.

The plan is a processor artifact, not an ADS source document. It must not be
validated with `schemas/ads.schema.json`. Its `apiVersion` identifies the ADS
contract that was planned.

### Required File Layout

Create:

```text
scripts/lib/ads/
  plan.rb
  planner.rb
```

Add plan snapshots under:

```text
conformance/plans/
```

### Plan Shape

Emit JSON with these top-level fields:

```json
{
  "apiVersion": "ads.dev/v1",
  "kind": "ADSDeploymentPlan",
  "planVersion": 1,
  "metadata": {},
  "source": {},
  "target": {},
  "components": [],
  "capabilities": {},
  "secrets": [],
  "networking": {},
  "security": {},
  "approvals": {},
  "observability": {},
  "supplyChain": {},
  "reliability": {},
  "actions": [],
  "diagnostics": []
}
```

Required field details:

- `metadata.name`: copied from `metadata.name`
- `metadata.owner`: copied from `metadata.owner`
- `metadata.labels`: copied from `metadata.labels` or `{}`
- `metadata.annotations`: copied from `metadata.annotations` or `{}`
- `source.file`: ADS input path as passed to the CLI
- `source.contextFile`: target context path as passed to the CLI
- `source.documentKind`: copied from `kind`
- `source.documentApiVersion`: copied from `apiVersion`
- `target.profile`: copied from `targetProfile` in the context
- `target.capabilities`: normalized target capabilities used by the plan
- `components`: normalized runtime components in dependency-safe order
- `capabilities.required`: normalized required capabilities as objects with
  `name`, optional `for`, optional `level`, optional `reason`, and `sourcePath`
- `capabilities.optional`: normalized optional capabilities with the same shape
- `secrets`: required secret declarations merged with redacted target binding
  metadata
- `networking`: ingress, internal traffic, egress, and default-deny intent
- `security`: sandbox, outbound policy, tool policy, identity, trust
  boundaries, threat model, and hardening intent
- `approvals`: required approvals, policy decision points, handlers available
  in the target context, and fail-closed behavior
- `observability`: traces, metrics, logs, audit events, and target sinks
- `supplyChain`: digest, signature, SBOM, provenance requirements, and target
  controls
- `reliability`: rollout, rollback, retries, timeouts, rate limits, and
  dead-letter requirements
- `actions`: deterministic planning actions grouped by concern
- `diagnostics`: non-blocking warning diagnostics carried forward

Do not include `generatedAt` by default. If a future flag adds timestamps, tests
must normalize or disable them.

### Components

Each component entry must include:

- `name`: original ADS component name
- `resourceName`: normalized artifact-safe name
- `type`
- `image` when present, preserved exactly
- `externalRef` when present
- `execution`
- `ports`
- `dependsOn`
- `state`
- `resources`
- `health`
- `scaling`
- `config`
- `sourcePath`

Components with `externalRef` and no `image` are external components. Adapters
must not create workload resources for them; they may emit references, comments,
or built-in-resource stubs that preserve the dependency and requirement.

### Secret Handling

For each `secrets.required[]` entry:

- include declaration fields from the ADS document
- include target binding metadata from the selected context
- include `bindingAvailable: true`
- include `sourcePath`
- include `bindingSourcePath` when practical

Never include binding fields named or shaped like secret payloads, including
`value`, `secretValue`, `token`, `password`, `privateKey`, `credential`, or
`data`.

### Actions

Actions must be stable and sorted by this concern order, then by affected
component or requirement name:

1. `validate-schema`
2. `resolve-target-context`
3. `normalize-component`
4. `resolve-secret-binding`
5. `prepare-runtime-component`
6. `configure-service`
7. `configure-ingress`
8. `configure-internal-traffic`
9. `configure-egress-policy`
10. `configure-security-policy`
11. `configure-observability-sink`
12. `configure-approval-gate`
13. `verify-supply-chain`
14. `apply-reliability-policy`

Each action must include:

- `type`
- `status`: `planned`
- `requirement`
- `sourcePath`
- `targetProfile`
- `component` when component-scoped
- `notes` only when useful and deterministic

### CLI Contract

Create the `bin/ads` executable in this phase if it does not already exist. It
must be executable and support at least `validate` and `plan` with JSON output:

```sh
bin/ads validate --file examples/minimal.yaml --format json
bin/ads plan --file examples/minimal.yaml --context contexts/kubernetes-production.yaml --format json
```

The legacy checker must not gain `--format plan-json`; that would conflict with
its documented diagnostics-only output contract.

### Tests And Fixtures

Add plan fixtures and register them in `conformance/expectations.yaml`:

```yaml
plans:
  accepts:
    - example: examples/minimal.yaml
      context: contexts/compose-single-host.yaml
      fixture: conformance/plans/minimal.compose-single-host.json
    - example: examples/minimal.yaml
      context: contexts/kubernetes-production.yaml
      fixture: conformance/plans/minimal.kubernetes-production.json
    - example: examples/approval-policy.yaml
      context: contexts/kubernetes-production.yaml
      fixture: conformance/plans/approval-policy.kubernetes-production.json
    - example: examples/multi-agent.yaml
      context: contexts/kubernetes-production.yaml
      fixture: conformance/plans/multi-agent.kubernetes-production.json
  rejects:
    - example: examples/minimal.yaml
      context: contexts/air-gapped.yaml
      expectedDiagnostics:
        - network-unresolved
        - api.openai.com
```

Plan snapshot tests must compare exact JSON after deterministic pretty-printing.
Do not compare only partial fragments unless a field is explicitly documented as
volatile.

### Acceptance Criteria

- Compatible document/context pairs emit an `ADSDeploymentPlan` JSON object.
- Incompatible pairs emit a JSON error envelope and no plan.
- Plan fixtures are exact, deterministic, and checked by
  `ruby scripts/test-examples.rb`.
- Plans contain enough information for adapters to generate artifacts without
  rereading ADS YAML or target context YAML.
- Existing Ruby and Go suites still pass.

## Phase 2: Target Adapters

### Goal

Implement deterministic adapters that consume `ADSDeploymentPlan` and emit
artifact bundles. Adapters must preserve ADS requirements as native resources,
external-control bindings, or explicit stubs.

Adapters must not apply artifacts to live systems.

### Required File Layout

Create:

```text
scripts/lib/ads/adapters/
  compose.rb
  kubernetes.rb
```

Add artifact fixtures under:

```text
conformance/artifacts/
  compose-single-host/minimal/
  kubernetes-production/minimal/
```

Use temporary directories for generated test output. Do not commit `dist/` or
other ad hoc generated output.

### Shared Adapter Rules

1. Adapters consume only an `Ads::Plan` object or parsed plan JSON.
2. Adapters must verify `plan.kind == "ADSDeploymentPlan"`.
3. Adapters must verify `plan.apiVersion == "ads.dev/v1"`.
4. Adapters must verify that `plan.target.profile` matches the requested
   adapter's supported profile mapping:
   - `compose` -> `compose-single-host`
   - `kubernetes` -> `kubernetes-production`
5. Adapters must fail before writing artifacts when the plan has error
   diagnostics.
6. Adapters must write atomically into an empty or newly created output
   directory. Refuse to overwrite unrelated existing files unless a future
   explicit `--force` flag is added.
7. Artifact manifests must not include secret values.
8. Artifact manifests must include labels or annotations that link generated
   resources back to ADS metadata and source paths where practical.
9. Resource ordering and filenames must be deterministic.

### Adapter 1: Compose Single Host

Command:

```sh
bin/ads emit --file examples/minimal.yaml --context contexts/compose-single-host.yaml --target compose --output-dir /tmp/ads-compose --format json
```

The `compose` adapter requires `plan.target.profile == "compose-single-host"`.

Output:

```text
/tmp/ads-compose/
  compose.yaml
  ads-plan.json
  README.md
```

Generate `compose.yaml` with:

- `services` for image-backed runtime components
- `image` values preserved exactly from the plan
- `depends_on` from `components[].dependsOn` for services that exist in Compose
- `ports` for externally exposed component ports
- environment variable references for required secrets, never values
- named volumes for persistent state when `state.mode` requires durability
- restart policy from `reliability` when it can be represented by Compose
- `x-ads-requirements` extension data for requirements Compose cannot natively
  enforce but the compatible target context claims are externally satisfied

Do not claim native enforcement for default-deny egress, approval gates, policy
decisions, audit export, or supply-chain verification unless the plan contains
explicit target evidence for native enforcement.

### Adapter 2: Kubernetes Production

Command:

```sh
bin/ads emit --file examples/minimal.yaml --context contexts/kubernetes-production.yaml --target kubernetes --output-dir /tmp/ads-k8s --format json
```

The `kubernetes` adapter requires
`plan.target.profile == "kubernetes-production"`.

Output:

```text
/tmp/ads-k8s/
  namespace.yaml
  deployments.yaml
  services.yaml
  network-policies.yaml
  secret-bindings.yaml
  observability.yaml
  approvals.yaml
  supply-chain-policy.yaml
  ads-plan.json
  README.md
```

Generate built-in Kubernetes resources only unless the target context explicitly
declares support for a CRD. For v1 implementation, represent non-native ADS
concepts as `ConfigMap` stubs with clear labels and annotations rather than
inventing custom kinds.

Generate:

- `Namespace` for the deployment
- `Deployment` resources for image-backed runtime components
- no workload resources for `externalRef`-only components
- `Service` resources for declared ports
- `NetworkPolicy` resources for declared internal traffic and egress intent
- `ConfigMap` stubs in `secret-bindings.yaml` that point to external secret
  references without values
- service account references from `security.identity` when declared
- readiness and liveness probes from component `health` declarations
- resource requests, limits, and replica intent from component `resources` and
  `scaling` when present
- observability `ConfigMap` stubs for traces, metrics, logs, audit events, and
  sinks
- approval and policy `ConfigMap` stubs for required approval gates and policy
  decision points
- supply-chain policy `ConfigMap` stubs for digest, signature, SBOM, and
  provenance requirements

If a Kubernetes-native representation cannot preserve a required behavior,
represent the requirement as an explicit external-control stub. Do not omit it.

### Artifact Fixture Expectations

Register artifact checks in `conformance/expectations.yaml`:

```yaml
artifacts:
  accepts:
    - target: compose
      example: examples/minimal.yaml
      context: contexts/compose-single-host.yaml
      fixtureDir: conformance/artifacts/compose-single-host/minimal
    - target: kubernetes
      example: examples/minimal.yaml
      context: contexts/kubernetes-production.yaml
      fixtureDir: conformance/artifacts/kubernetes-production/minimal
  rejects:
    - target: compose
      example: examples/multi-agent.yaml
      context: contexts/compose-single-host.yaml
      expectedDiagnostics:
        - capability-unsupported
        - secret-unbound
        - network-unresolved
```

Tests must compare generated directories file-by-file after deterministic
pretty-printing. They must also assert that generated artifacts do not contain
secret-like payload keys or known forbidden fixture values.

### Optional Local Verification

These checks are useful when tools are installed, but they must not be required
unless CI installs them:

```sh
docker compose -f /tmp/ads-compose/compose.yaml config
kubectl apply --dry-run=client -f /tmp/ads-k8s
```

### Acceptance Criteria

- Compose emits a deterministic bundle for compatible minimal ADS plans.
- Kubernetes emits a deterministic bundle for compatible minimal ADS plans.
- Adapters refuse incompatible targets before writing artifacts.
- Generated artifacts preserve security, networking, approval, observability,
  reliability, and supply-chain requirements as native resources or explicit
  stubs.
- Generated artifacts and READMEs contain no secret values.
- `ruby scripts/test-examples.rb`, `go test ./...`, and
  `go run ./cmd/ads-fixture-validator` still pass.

## Phase 3: Agent-Facing CLI

### Goal

Complete the compact CLI that coding agents can call and parse without scraping
prose. `bin/ads` is introduced earlier for `validate` and `plan`; this phase
hardens the common envelope, adds `explain`, and ensures `emit` is wired through
the adapters.

### Required File

Use this file created in Phase 1:

```text
bin/ads
```

The file must remain executable.

### Commands

By the end of this phase, support these commands:

```sh
bin/ads validate --file examples/minimal.yaml --format json
bin/ads explain --file examples/minimal.yaml --context contexts/kubernetes-production.yaml --format json
bin/ads plan --file examples/minimal.yaml --context contexts/kubernetes-production.yaml --format json
bin/ads emit --file examples/minimal.yaml --context contexts/kubernetes-production.yaml --target kubernetes --output-dir /tmp/ads-k8s --format json
```

Initial implementation may support only `--format json` for `bin/ads`. If text
output is added, JSON remains the default for automation.

### JSON Envelope

Every `bin/ads` command must emit one JSON object:

```json
{
  "ok": true,
  "phase": "plan",
  "file": "examples/minimal.yaml",
  "context": "contexts/kubernetes-production.yaml",
  "target": "kubernetes",
  "targetProfile": "kubernetes-production",
  "diagnostics": [],
  "errors": [],
  "warnings": [],
  "plan": {},
  "artifacts": [],
  "nextActions": []
}
```

Field rules:

- `ok`: `true` only when the command completed without blocking diagnostics
- `phase`: `validate`, `explain`, `plan`, or `emit`
- `file`: ADS source file
- `context`: target context file, or `null` for validate without context
- `target`: requested emit target, or `null` outside emit
- `targetProfile`: selected context profile, or `null` without context
- `diagnostics`: all diagnostics in stable order
- `errors`: only error diagnostics
- `warnings`: only warning diagnostics
- `plan`: present only for successful `plan` and `emit`; otherwise `null`
- `artifacts`: present only for successful `emit`; otherwise `[]`
- `nextActions`: actionable remediation hints for failures

Diagnostic objects must include:

- `category`
- `severity`
- `path`
- `message`
- `remediation` when practical

Additional diagnostic fields may include `targetProfile`, `capability`,
`component`, `secret`, `approval`, `policyDecisionPoint`, `destination`,
`signal`, `verifier`, `formats`, and `predicateTypes`.

`invocation-invalid` is allowed only for CLI-level errors such as missing
required flags, unreadable inputs, unsupported targets, unsupported formats, and
output-directory conflicts. ADS document and compatibility diagnostics should
use the categories from `SPEC.md`.

### Exit Codes

- `0`: success
- `1`: validation, compatibility, strict-warning, planning, or emit failure
- `2`: invalid invocation, unreadable inputs, malformed YAML, unsupported
  format, unsupported target, or output-directory conflict

### Remediation Hints

Add deterministic `nextActions` for common blockers:

- `invocation-invalid`: correct the command flags, target name, input path, or
  output directory
- `schema-invalid`: fix the ADS field at `path`
- `reference-invalid`: declare or rename the referenced component/action
- `capability-unsupported`: choose a target with the capability or remove the
  requirement
- `secret-unbound`: add a target-context binding for the named secret
- `approval-handler-missing`: configure a human or policy approval handler
- `policy-decision-point-missing`: declare the decision point and make it
  available in the target context
- `network-unresolved`: add an allowed destination or choose a target that can
  enforce the network rule
- `security-policy-unenforceable`: add the missing platform control or choose a
  stronger target
- `supply-chain-unverified`: add the required verifier/SBOM/provenance control
  or use a compatible target
- `observability-sink-missing`: bind the required signal to an available sink
- `processor-limitation`: adjust names, target, or unsupported runtime shape

### Explain Mode

`bin/ads explain` must return both machine-readable fields and a concise
human-readable summary string. It must explain:

- whether the document is deployable to the selected target
- which target capabilities are used
- which requirements block planning
- which warnings should be reviewed
- which approval gates must be satisfied
- which artifact files `emit` would generate

Do not include prose that an agent must parse to determine success. The JSON
fields are the contract; prose is supplemental.

### Tests

Add CLI tests to `scripts/test-examples.rb` for:

- successful `validate`
- successful `plan`
- successful `emit`
- failed `plan` without `--context` exits `2`
- failed `plan` for incompatible target exits `1`
- failed `emit` for unsupported target exits `2`
- output-directory conflict exits `2`
- JSON envelopes contain `ok`, `phase`, `errors`, `warnings`, and
  `nextActions`

### Acceptance Criteria

- A coding agent can call one command to validate an ADS file.
- A coding agent can call one command to get a plan JSON object.
- A coding agent can call one command to emit target artifacts.
- Failures include machine-readable diagnostics and deterministic remediation.
- No command requires parsing human prose to decide whether to continue.
- The legacy checker remains documented and compatible.

## Documentation Updates

Update these files in the same implementation branch:

- `README.md`: add a short agent-facing quickstart with `bin/ads validate`,
  `plan`, and `emit`.
- `REFERENCE_PROCESSOR.md`: document that the legacy checker remains
  diagnostics-only; document shared core behavior if relevant.
- `IMPLEMENTERS.md`: document the plan artifact contract, planning gate, JSON
  envelope, and adapter expectations.
- `COMPATIBILITY.md`: update only if target-context compatibility behavior or
  public matrix expectations change.
- `CONTRIBUTING.md`: mention new plan and artifact fixture update rules if
  fixture sections are added to `conformance/expectations.yaml`.

Do not change `SPEC.md` unless the implementation introduces a normative ADS v1
behavior change. Plan and artifact formats are processor artifacts for this
repository unless separately standardized.

## Recommended Delivery Order

1. Extract shared Ruby processor core while preserving legacy CLI behavior.
2. Add the planning-safe validation gate and tests.
3. Add `bin/ads validate` with JSON envelopes.
4. Add the internal plan model and `bin/ads plan`.
5. Add plan fixtures and exact snapshot tests.
6. Implement the Compose adapter.
7. Add Compose artifact fixtures and tests.
8. Implement the Kubernetes adapter.
9. Add Kubernetes artifact fixtures and tests.
10. Add `bin/ads explain`.
11. Update docs.
12. Run the full verification suite.

## Full Verification

Run:

```sh
ruby scripts/test-examples.rb
go test ./...
go run ./cmd/ads-fixture-validator
bin/ads validate --file examples/minimal.yaml --format json
bin/ads plan --file examples/minimal.yaml --context contexts/kubernetes-production.yaml --format json
bin/ads emit --file examples/minimal.yaml --context contexts/compose-single-host.yaml --target compose --output-dir /tmp/ads-compose --format json
bin/ads emit --file examples/minimal.yaml --context contexts/kubernetes-production.yaml --target kubernetes --output-dir /tmp/ads-k8s --format json
```

If Docker Compose or kubectl are installed, optionally run:

```sh
docker compose -f /tmp/ads-compose/compose.yaml config
kubectl apply --dry-run=client -f /tmp/ads-k8s
```

## Definition Of Done

This implementation is complete when:

- `examples/minimal.yaml` can be validated, planned, and emitted for
  `compose-single-host`.
- `examples/minimal.yaml` can be validated, planned, and emitted for
  `kubernetes-production`.
- `examples/approval-policy.yaml` and `examples/multi-agent.yaml` can emit
  deterministic plans for `kubernetes-production`.
- Incompatible example/context pairs fail before planning or emitting artifacts.
- The emitted plan and artifacts preserve ADS security, secret, approval,
  observability, networking, reliability, and supply-chain requirements.
- The CLI output is structured enough for a coding agent to choose the next
  action without guessing.
- No existing legacy command or fixture expectation regresses.

## Non-Goals

- Do not apply changes to live Kubernetes clusters, Docker runtimes, cloud
  runtimes, policy engines, registries, observability systems, or secret stores.
- Do not implement a policy engine.
- Do not implement a secrets manager.
- Do not verify real signatures, SBOMs, or provenance against live registries.
- Do not introduce breaking ADS v1 schema changes unless a separate versioning
  decision is made first.
- Do not require Docker Compose or kubectl in CI unless the workflow is updated
  to install them.

## Risks And Watchpoints

- Planning can accidentally become an implicit weakening layer. Every generated
  action must map back to ADS requirements and target evidence.
- The current Ruby checker is diagnostics-oriented and not a full schema
  validator. Planning must use the stricter Phase 0 gate.
- Kubernetes has no native object for several ADS concepts, especially approval
  gates, policy decision points, observability sinks, and supply-chain evidence.
  Use explicit built-in-resource stubs unless the target context declares CRD
  support.
- Compose cannot natively enforce many production controls. The adapter must
  distinguish native Compose behavior from externally satisfied target-context
  claims.
- Snapshot tests become brittle if output includes timestamps or unstable
  ordering. Keep generated output deterministic.
- Agent-facing JSON should stay compact, stable, and versioned. Avoid dumping
  unstructured internal implementation details.
