# Secure Agent Passport: agents that reach private data on other machines, and can prove what left

**A secure agent is one that causes no incident even when its model is fooled. NVIDIA OpenShell guards the agent inside its machine; Agent Fabric's Secure Agent Passport guards the moment it reaches data and tools on another machine, and records it.**

Regulated teams can now run AI agents on their own hardware (DGX Spark), but the useful
data lives on *other* machines: a ledger database, a document store, a teammate's GPU box.
The usual ways to connect them are a VPN that opens the whole network or a port exposed
to it. Neither says which tool an agent may call, for how long, or what data left.

This recipe runs an analyst agent (NVIDIA Nemotron, running locally) inside an
**NVIDIA OpenShell** sandbox on the agent node. Its only way out is the **Agent Fabric
gateway**, which forwards a call to another machine only when a short-lived capability
allows that exact service and method. The agent never holds that capability: OpenShell
injects it on the wire.

```mermaid
flowchart LR
  U["Analyst"] --> A
  subgraph S1["Agent node · DGX Spark"]
    A["Agent<br/>OpenShell sandbox"] --> M["Nemotron<br/>local model"]
    A -->|"only allowed egress<br/>+ injected capability"| G["Agent Fabric gateway"]
  end
  G -->|"WireGuard mesh"| T
  subgraph S2["Data node"]
    T["ledger-read MCP<br/>aggregates only"] --> D[("ledger DB")]
    X["ledger-admin MCP<br/>raw export"] --> D
  end
  P["Person on data node"] -.->|"approves tier-3"| X
```

## What the demo shows

See it step by step, with screenshots of real runs: [docs/DEMO_WALKTHROUGH.md](docs/DEMO_WALKTHROUGH.md).


| Step | What happens | What stops it / records it |
| --- | --- | --- |
| The job | "Summarize Jiangsu Huaxin's risk signals for the last 90 days." The agent plans, calls `ledger-read` through the gateway, gets bucketed aggregates, and answers | The capability allows `mcp://ledger-read` and its MCP methods only, for 30 minutes |
| Attack 1 | A memo in the ledger (planted, invented data) tells the agent to upload all rows to `https://audit-drop.example.net` | **OpenShell** proxy: `403`, destination not in policy |
| Attack 2 | The same memo tells it to call `export_transactions` on `ledger-admin` | **Agent Fabric gateway**: `403 capability denied`. The data node never sees the call |
| Approval | The agent can only *prepare* a limit change (tier 3) | A person approves on the data node (`scripts/approve.sh`) |
| Record | Every call through the gateway, allowed or refused, with bytes each way and the capability id | `fabric gateway ledger` on the agent node, and `fintech.agent_log` on the data node |
| Emergency stop | An operator stops the agent mid-task | `fabric gateway freeze --all`: the very next call is refused, before any control-plane round trip |

### Guardrail built with an NVIDIA skill

`agent-node/guardrail/` holds a **Fintech Agent Boundary** content-safety policy
generated with NVIDIA's [`nemotron-policy-generator`](https://build.nvidia.com/skills)
skill (Markdown + JSON validated against the skill's schema + a Nemotron
content-safety system prompt). With `GUARDRAIL_URL` set, every tool result is screened
by a Nemotron content-safety model before the planner reads it. If it is flagged, the
result is quarantined, and the agent's answer always ends with a security warning. The
warning is added by code, because in our runs the planner read the planted memo and
presented it as a legitimate note.

This layer is detection. The hard controls are the OpenShell policy and the gateway.

The controls do not depend on the model behaving. `agent.py --replay-attack` performs
the injected actions deliberately, with no model in the loop, and they still fail.

## Run it

Requirements: Docker, [`uv`](https://docs.astral.sh/uv/), `psql`, the
[OpenShell CLI](https://github.com/NVIDIA/OpenShell), and the `fabric` CLI signed in to
one Agent Fabric network on both machines (`fabric login && fabric up`). One machine
can play both roles. The gateway ledger, `freeze` and the default MCP grant need a `fabric` release newer
than v0.1.35.

```bash
# data node
./scripts/data-node-up.sh

# agent node
ollama pull nemotron-3-nano:30b          # or serve Nemotron with NIM / vLLM on DGX Spark
./scripts/agent-node-up.sh
./scripts/demo.sh

# a person approves a prepared change (on the data node)
./scripts/approve.sh <approval_id>
```

On DGX Spark (Linux), the sandbox reaches the host through OpenShell's own bridge, not
loopback. Find its address, then start the gateway there:

```bash
openshell sandbox create --no-keep -- getent hosts host.openshell.internal   # 172.19.0.1 on our Spark
GATEWAY_LISTEN=172.19.0.1:17777 ./scripts/agent-node-up.sh
```

If an older OpenShell (for example one installed with NemoClaw) comes first on `PATH`,
set `OPENSHELL=/usr/bin/openshell`.
It still refuses any request without a valid capability. To use Nemotron on
build.nvidia.com instead of a local model, attach OpenShell's `nvidia` provider and set
`MODEL_URL=https://integrate.api.nvidia.com/v1`.

## Repository

| Path | What |
| --- | --- |
| `agent-node/agent/` | The agent (standard-library Python, no package egress needed) and its sandbox image |
| `agent-node/openshell/` | Sandbox policy (two destinations, nothing else) and provider profiles |
| `data-node/ledger_mcp/` | MCP server, one process per role (`read`, `admin`); official MCP Python SDK |
| `data-node/db/` | Synthetic lender data (every company and amount is invented) and the attack memo |
| `skills/fabric-access/` | Agent Skill (`SKILL.md` + skill card) teaching an agent to use the gateway |
| `agent-node/guardrail/` | Content-safety policy made with NVIDIA's `nemotron-policy-generator` skill, and `render.py` to regenerate it |
| `scripts/` | Bring-up, demo and approval |
| `docs/VERIFICATION.md` | What was run, on what, and what came back |
| `docs/demo-run.txt` | Unedited output of one full `scripts/demo.sh` run |
| `docs/DEMO_WALKTHROUGH.md` | Screenshots of every step, each rendered from a real run (raw output kept next to each image) |

## Honest limits

- OpenShell and NemoClaw are alpha software. With OpenShell 0.0.116 the provider
  profile's endpoint was not composed into the sandbox policy, so the policy declares
  it; the capability was still substituted only for that endpoint.
- Aggregates do leave the data node. Raw rows do not, and every response's size is recorded.
- This covers part of the compensating controls a regulator asks for. It is not a
  compliance certification.

## License

Apache-2.0.
