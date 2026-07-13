# Compatibility Matrix

This matrix summarizes the expected behavior of the reference ADS examples against
the current target context fixtures. The machine-readable source of truth for
these checks is [conformance/expectations.yaml](conformance/expectations.yaml),
and the fixture suite enforces it with [scripts/test-examples.rb](scripts/test-examples.rb).

Target contexts are non-normative fixtures. They model the platform capabilities,
secret bindings, approval handlers, observability sinks, network controls,
security policy controls, and supply-chain controls available to an ADS
processor before deployment planning.

## Current Target Contexts

| Target context | Profile | Intended coverage |
|---|---|---|
| [contexts/compose-single-host.yaml](contexts/compose-single-host.yaml) | `compose-single-host` | Single-host container deployment with basic approvals, secrets, telemetry, and outbound controls. |
| [contexts/managed-container-runtime.yaml](contexts/managed-container-runtime.yaml) | `managed-container-runtime` | Managed runtime deployment with stateful session support, approvals, secrets, telemetry, and outbound controls. |
| [contexts/kubernetes-production.yaml](contexts/kubernetes-production.yaml) | `kubernetes-production` | Production-oriented Kubernetes deployment with multi-agent, policy, stateful, observability, and supply-chain support. |
| [contexts/serverless-auxiliary.yaml](contexts/serverless-auxiliary.yaml) | `serverless-auxiliary` | Event-driven worker deployment with secrets, telemetry, audit export, default-deny egress, and event-driven scaling. |

## Recognized Profiles Without Fixtures

ADS v1.0 intentionally recognizes `air-gapped` and `gpu-serving` as profile
names without publishing reference target context fixtures for them. These names
reserve stable vocabulary for common deployment targets, but they do not imply
compatibility by themselves. A processor must still validate against a concrete
target context before planning for one of these profiles.

## Example Compatibility

| Example | compose-single-host | managed-container-runtime | kubernetes-production | serverless-auxiliary |
|---|---|---|---|---|
| [examples/minimal.yaml](examples/minimal.yaml) | pass | pass | pass | fail: `capability-unsupported`, `secret-unbound`, `approval-handler-missing`, `policy-decision-point-missing`, `network-unresolved` |
| [examples/approval-policy.yaml](examples/approval-policy.yaml) | pass | pass | pass | fail: `capability-unsupported`, `approval-handler-missing`, `policy-decision-point-missing`, `network-unresolved` |
| [examples/serverless-auxiliary.yaml](examples/serverless-auxiliary.yaml) | fail: `capability-unsupported` | fail: `capability-unsupported` | pass | pass |
| [examples/stateful-agent.yaml](examples/stateful-agent.yaml) | fail: `capability-unsupported` | pass | pass | fail: `capability-unsupported`, `secret-unbound`, `approval-handler-missing`, `policy-decision-point-missing`, `network-unresolved` |
| [examples/multi-agent.yaml](examples/multi-agent.yaml) | fail: `capability-unsupported`, `secret-unbound`, `network-unresolved` | fail: `capability-unsupported`, `secret-unbound`, `network-unresolved` | pass | fail: `capability-unsupported`, `secret-unbound`, `approval-handler-missing`, `policy-decision-point-missing`, `network-unresolved` |
| [examples/supply-chain.yaml](examples/supply-chain.yaml) | fail: `capability-unsupported`, `supply-chain-unverified` | fail: `capability-unsupported`, `supply-chain-unverified` | pass | fail: `capability-unsupported`, `secret-unbound`, `approval-handler-missing`, `policy-decision-point-missing`, `network-unresolved`, `supply-chain-unverified` |

## Negative Target Context Fixture

[contexts/invalid/incomplete-target.yaml](contexts/invalid/incomplete-target.yaml)
intentionally omits required platform support. It is expected to reject
[examples/minimal.yaml](examples/minimal.yaml) with:

- `capability-unsupported`
- `secret-unbound`
- `approval-handler-missing`
- `policy-decision-point-missing`
- `observability-sink-missing`
- `network-unresolved`
- `security-policy-unenforceable`

## Updating Expectations

When adding a new example or target context:

- Add the fixture file under `examples/` or `contexts/`.
- Add the expected result to [conformance/expectations.yaml](conformance/expectations.yaml).
- Update this matrix when the new fixture changes user-visible compatibility.
- Run `ruby scripts/test-examples.rb`.
