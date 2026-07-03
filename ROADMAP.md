# Roadmap

This roadmap tracks the path from the current draft to a stable Agentic Deployment Specification. The normative draft lives in [SPEC.md](SPEC.md), and the technical research reference lives in [deployment-research.md](deployment-research.md).

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

## v0.3 - JSON Schema and Conformance (Current)

Goal: make ADS machine-validatable.

Deliverables:

- initial `schemas/ads.schema.json`
- conformance requirements for ADS processors
- compatibility error categories
- schema tests for valid and invalid documents
- secret-reference and observability validation rules

Exit criteria:

- the canonical examples validate against the schema
- unsupported required capabilities produce clear errors
- extension fields have a documented namespace rule

## v0.4 - Profiles and Examples

Goal: make ADS practical across deployment targets.

Deliverables:

- production Kubernetes profile
- single-host Compose profile
- managed container runtime profile
- multi-agent example
- stateful agent example
- approval-and-policy example

Exit criteria:

- each profile states which ADS capabilities it can satisfy
- examples reuse the same naming and structure where possible
- architecture diagrams use the same component names as `SPEC.md`

## v0.5 - Security, Policy, and Operations

Goal: harden the production model.

Deliverables:

- threat model for agentic deployments
- supply-chain requirements for signed artifacts and SBOMs
- policy decision points for approvals
- production-readiness checklist
- audit event taxonomy

Exit criteria:

- production deployments have explicit security, secret, approval, and telemetry requirements
- high-risk tool actions are deny-by-default unless approved
- audit events map to deployment, policy, secret, and tool activity

## v1.0 - Stable Specification

Goal: publish a stable, implementable standard.

Deliverables:

- stable specification text
- stable schema
- reference examples
- compatibility matrix
- conformance test suite
- contribution and governance process

Exit criteria:

- breaking changes require a new major version
- at least two different deployment targets are covered by examples
- at least one independent ADS processor can validate the examples
