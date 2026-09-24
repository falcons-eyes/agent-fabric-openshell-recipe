# Skill card: fabric-access

| Field | Value |
| --- | --- |
| Name | fabric-access |
| Version | 0.1.0 |
| Owner | Falcon Eyes Inc. (Agent Fabric team) |
| License | Apache-2.0 |
| Format | Agent Skills specification (`SKILL.md`) |
| Works with | Agents running inside NVIDIA OpenShell (OpenClaw via NemoClaw, or any agent that can make HTTP calls) |

## What it does

Teaches an agent how to call private MCP / A2A / LLM services on other machines through
the Agent Fabric gateway, how to read the gateway's refusals, and how to handle
approval-gated actions.

## Dependencies

- An Agent Fabric gateway reachable from the sandbox (`fabric gateway proxy`).
- An OpenShell provider that injects `FABRIC_CAPABILITY` for the gateway endpoint.
- Environment: `FABRIC_GATEWAY_URL`, `FABRIC_NETWORK`.

## Limitations and risks

- The skill is guidance. It does not enforce anything; enforcement is done by the
  OpenShell proxy and the Agent Fabric gateway, which hold even if the model ignores
  this skill.
- It contains no scripts, executes nothing, and reads no files.
- Not yet scanned or signed through NVIDIA's verified-skill pipeline.
