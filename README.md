# Agentic Deployment Specification

> A vendor-neutral deployment contract for self-hosted applications and agentic systems.

The Agentic Deployment Specification (ADS) lets an application describe how it should be deployed, secured, observed, and governed. Instead of forcing deployment agents or platform teams to reverse-engineer a repository, ADS makes operational intent explicit and machine-readable.

## Status

Draft v0.1. The current work is focused on the core terminology, document model, runtime model, security requirements, and approval semantics.

## What ADS is

ADS is a specification for describing deployment requirements that downstream tools can satisfy with Kubernetes, Docker Compose, managed container runtimes, GitOps systems, policy engines, or other infrastructure.

ADS is designed for:

- platform engineers operating self-hosted software
- AI deployment agents that need a safe contract to follow
- self-hosting vendors and open-source maintainers
- enterprise security and governance teams
- customers deploying software into their own environments

## What ADS is not

ADS is not a replacement for Kubernetes manifests, Helm charts, CI/CD pipelines, secrets managers, model-serving protocols, or agent frameworks. It describes the operational requirements those systems must satisfy.

## Core Principles

- Vendor neutral: ADS describes intent, not a single platform implementation.
- Human approval by default: risky deployment and tool actions must be explicit.
- Self-hosting first: customer-controlled environments are a primary target.
- AI-native: agents, tools, memory, policy, and observability are first-class concerns.
- Open standard: the specification should be readable by humans and enforceable by machines.

## Repository Navigation

- [SPEC.md](SPEC.md) is the normative draft specification.
- [ROADMAP.md](ROADMAP.md) tracks planned versions and exit criteria.
- [deployment-research.md](deployment-research.md) is the non-normative technical research reference used to shape the specification.

## Current Direction

ADS should become a deployment and governance standard for production agentic systems, not another wrapper around `docker-compose.yml`. A conforming ADS document should describe:

- the runtime components that must run
- the platform capabilities required by those components
- the security boundaries, secrets, and network policies that apply
- the approval and policy gates required before risky actions
- the observability signals needed for operations and auditability

See [SPEC.md](SPEC.md) for the current draft model.
