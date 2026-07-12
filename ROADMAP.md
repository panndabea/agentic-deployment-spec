# Roadmap

This roadmap tracks released ADS milestones and future maintenance for the stable Agentic Deployment Specification. The normative v1.0 specification lives in [SPEC.md](SPEC.md), and the technical research reference lives in [deployment-research.md](deployment-research.md).

## Release Principles

- Each release should improve the specification instead of adding parallel documents with overlapping content.
- Examples should reuse the canonical minimal example from [SPEC.md](SPEC.md#minimal-example).
- New chapters should be added only when the existing `SPEC.md`, `README.md`, or roadmap cannot reasonably hold the material.
- Security, approvals, secrets, and observability should stay first-class in every milestone.

## v0.1 - Baseline Draft

Goal: establish the specification shape and shared vocabulary.

Deliverables:

- project positioning in [README.md](README.md)
- normative draft structure in [SPEC.md](SPEC.md)
- problem statement, goals, non-goals, scope, and terminology
- conceptual document model
- draft runtime, capability, security, secrets, observability, approval, and profile models

Exit criteria:

- README links to the spec, roadmap, and research reference
- SPEC contains a reusable minimal example
- profile names are stable enough for v0.2 schema work

## v0.2 - YAML Document Model

Goal: turn the conceptual model into a concrete authoring format.

Deliverables:

- complete YAML field structure
- required and optional fields for `AgenticDeployment`
- validation rules for required capabilities
- first standalone examples derived from the canonical minimal example
- initial compatibility notes for `compose-single-host` and `kubernetes-production`

Exit criteria:

- an ADS document can be authored without reading the research report
- processors can detect missing required sections
- examples do not duplicate unrelated sample applications

## v0.3 - JSON Schema and Conformance

Goal: make ADS machine-validatable.

Deliverables:

- initial `schemas/ads.schema.json`
- initial conformance requirements for ADS processors
- initial compatibility diagnostic categories
- schema tests for valid and invalid documents
- secret-reference and observability validation rules
- target context fixtures for capability, secret, approval, observability, network, and security checks

Exit criteria:

- the canonical examples validate against the schema
- unsupported required capabilities produce clear errors
- extension fields have a documented namespace rule

## v0.4 - Profiles and Examples

Goal: make ADS practical across deployment targets.

Deliverables:

- [x] production Kubernetes profile
- [x] single-host Compose profile
- [x] managed container runtime profile
- [x] profile capability matrix with positive and negative fixture expectations
- [x] multi-agent example
- [x] stateful agent example
- [x] approval-and-policy example

Exit criteria:

- [x] each profile states which ADS capabilities it can satisfy
- [x] examples state which target contexts they are expected to pass or fail
- [x] examples reuse the same naming and structure where possible
- [x] architecture diagrams use the same component names as `SPEC.md`

v0.4 maintenance note:

- keep profile fixtures, examples, and diagrams synchronized during maintenance

## v0.5 - Security, Policy, and Operations

Goal: harden the production model.

Deliverables:

- [x] threat model for agentic deployments
- [x] supply-chain requirements for signed artifacts and SBOMs
- [x] policy decision points for approvals
- [x] production-readiness checklist
- [x] audit event taxonomy

Exit criteria:

- production deployments have explicit security, secret, approval, and telemetry requirements
- high-risk tool actions are deny-by-default unless approved
- [x] audit events map to deployment, policy, secret, and tool activity

v0.5 stabilization note:

- threat model, supply-chain, and policy decision point additions were carried into the v1.0 stabilization pass

## v1.0 - Stable Specification

Goal: publish a stable, implementable standard.

Deliverables:

- stable specification text
- stable schema
- reference examples
- implementer guidance in [IMPLEMENTERS.md](IMPLEMENTERS.md)
- reference processor documentation in [REFERENCE_PROCESSOR.md](REFERENCE_PROCESSOR.md)
- compatibility matrix
- conformance test suite with CI coverage
- contribution and governance process in [CONTRIBUTING.md](CONTRIBUTING.md)
- release readiness gates in [RELEASE.md](RELEASE.md)

Exit criteria:

- breaking changes require a new major version
- at least two different deployment targets are covered by examples
- at least one independent ADS processor can validate the examples

v1.0 maintenance focus:

- apply the contribution and governance process in [CONTRIBUTING.md](CONTRIBUTING.md) during review
- use [RELEASE.md](RELEASE.md) to track release readiness and release evidence
- keep `ads.dev/v1` as the stable ADS v1 API version; use compatible additions for v1.x and a new major version for breaking changes
- keep [SPEC.md](SPEC.md) free of stale draft-only language that conflicts with stable v1 behavior
- keep [IMPLEMENTERS.md](IMPLEMENTERS.md) aligned with processor conformance requirements
- keep [REFERENCE_PROCESSOR.md](REFERENCE_PROCESSOR.md) aligned with the Ruby checker and fixture expectations
- keep the conformance workflow green for changes to examples, schema, contexts, and processor rules
- keep [COMPATIBILITY.md](COMPATIBILITY.md) and [conformance/expectations.yaml](conformance/expectations.yaml) synchronized as examples and target contexts evolve
- grow the conformance expectation manifest before adding new profile-specific examples
