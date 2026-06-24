# anthill

Autonomous software engineering orchestrator. Turns tickets into pull requests.

Anthill watches for Jira tickets or GitHub Issues that enter a configured state, spins up a specialized agent container per ticket, and moves the ticket forward or back based on the result — no human intervention required unless the agent fails.

---

## How it works

```
Jira ticket enters "Ready for Dev"
        |
        v
anthill poller detects it (every 30s)
        |
        v
ticket moved to "In Progress"
        |
        v
agent container launched (ghcr.io/yoennisrg/anthill-action:latest)
        |
        +-- clones target repo
        +-- injects agent workspace (AGENTS.md, agents/, skills/)
        +-- detects stack and installs deps (Node / Go / Python)
        +-- runs: opencode run "<ticket context>"
        |
        v
container exits
        |
        +-- exit 0  -->  ticket moved to "In Review"
        +-- exit 1  -->  ticket stays in listener state
                         label "needs-human-review" added
                         container logs commented on the ticket
                         poller skips the ticket until label is removed
```

Inside the container, OpenCode runs with a team of 10 specialized agents. Uma acts as the default dispatcher and delegates to the right specialist based on the ticket. The agent creates a branch, opens a draft PR to reserve territory, implements the full solution, and auto-merges.

---

## Usage mode 1 — GitHub Action

The fastest way to use anthill. No infra required, runs in your CI.

```yaml
# .github/workflows/anthill.yml
name: Anthill

on:
  workflow_dispatch:
    inputs:
      ticket_id:
        description: Jira ticket ID (e.g. PROJ-123)
        required: true

jobs:
  run:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: yoennisrg/anthill-action@v1
        with:
          ticket_id: ${{ github.event.inputs.ticket_id }}
          repository: ${{ github.repository }}
          branch: main
          github_token: ${{ secrets.GITHUB_TOKEN }}
          opencode_api_key: ${{ secrets.OPENCODE_API_KEY }}
          # Optional — omit if you don't use Jira
          jira_url: ${{ secrets.JIRA_URL }}
          jira_email: ${{ secrets.JIRA_EMAIL }}
          jira_token: ${{ secrets.JIRA_TOKEN }}
          jira_project: PROJ
```

You can trigger this from a Jira webhook, a GitHub Actions schedule, or any event that provides a ticket ID.

### Action inputs

| Input | Required | Description |
|---|---|---|
| `ticket_id` | yes | Ticket ID to work on (e.g. `PROJ-123`) |
| `repository` | no | Target repo (`owner/repo`). Defaults to current repo. |
| `branch` | no | Target branch. Defaults to `main`. |
| `github_token` | yes | GitHub token for git operations and PR creation |
| `merge_token` | no | Separate token with merge permissions (falls back to `github_token`) |
| `opencode_api_key` | yes | API key for OpenCode |
| `brave_api_key` | no | Brave Search API key (enables web search in agents) |
| `jira_url` | no | Jira base URL (e.g. `https://myco.atlassian.net`) |
| `jira_email` | no | Jira account email |
| `jira_token` | no | Jira API token |
| `jira_project` | no | Jira project key (e.g. `MP`) |
| `cgc_url` | no | CGC Neo4j bolt URL (e.g. `bolt://host:7687`) |
| `cgc_user` | no | CGC Neo4j username (defaults to `neo4j`) |
| `cgc_password` | no | CGC Neo4j password |
| `graphiti_url` | no | Graphiti MCP server URL (e.g. `http://host:8001/mcp/`) |
| `graphiti_group_id` | no | Graphiti group ID for this repo (e.g. `owner/repo`) |

---

## Usage mode 2 — Self-hosted daemon

Run anthill on your own machine or server. The daemon polls Jira every 30 seconds and dispatches containers automatically.

### Install

**Linux / macOS:**
```bash
curl -sSL https://raw.githubusercontent.com/yoennisrg/anthill-action/main/install.sh | bash
```

Detects your OS and architecture automatically. Installs to `/usr/local/bin/anthill`.

### Configure and start

```bash
# Interactive setup wizard — walks through GitHub, Jira, model, repo config
anthill init

# Start the orchestrator in the background
anthill daemon start

# Verify everything is running
anthill status
```

`anthill init` will:
1. Check and configure `gh` CLI authentication
2. Prompt for your GitHub token, OpenCode API key, and optional Brave Search key
3. Validate the target repo and let you pick the branch
4. Configure ticket provider — Jira or GitHub Issues (optional)
5. Configure Knowledge Layer — CGC and Graphiti (optional)
6. Write `~/.anthill/anthill.yaml` and `~/.anthill/secrets.yaml`

---

## CLI reference

```
anthill init                          Interactive setup wizard
anthill daemon start                  Start the orchestrator in background
anthill daemon stop                   Stop the running orchestrator
anthill daemon logs                   Stream orchestrator logs (tail -F)
anthill daemon containers             List running ant containers
anthill daemon exec <container>       Open a shell inside a container
anthill status                        Show daemon status, integrations, running containers, open PRs
anthill run <ticket-id>               Manually trigger a single ticket
anthill issues get <id>               Fetch and print full ticket details (uses configured provider)
anthill issues update <id>            Update a ticket (--transition, --comment, --label)
anthill jira get <ticket-id>          Fetch and print full Jira ticket details
anthill jira update <ticket-id>       Update a Jira ticket (--transition, --comment, --label, --attach)
anthill version                       Show version
```

`anthill issues` works with whichever provider is configured — Jira or GitHub Issues. `anthill jira` is Jira-specific and supports file attachments.

Examples:
```bash
# Jira
anthill run PROJ-42
anthill issues get PROJ-42
anthill issues update PROJ-42 --transition "In Review" --comment "Done in PR #88"

# GitHub Issues
anthill run 42
anthill issues get 42
anthill issues update 42 --label "in-review" --comment "Done in PR #88"
```

---

## Configuration

Config lives in `~/.anthill/`. The wizard creates both files on `anthill init`.

### `~/.anthill/anthill.yaml`

```yaml
version: 1

repos:
  - repo: owner/my-project              # GitHub repo in owner/repo format
    branch: main                        # Branch to clone and target for PRs
    merge: auto                         # auto | manual
    model: opencode-go/kimi-k2.7-code   # Model passed to OpenCode
    image: ghcr.io/yoennisrg/anthill:latest  # Agent container image

daemon:
  port: "8080"
  docker_host: ""                       # Optional: ssh://user@host for remote Docker

integrations:
  jira:
    url: https://your-org.atlassian.net
    email: bot@company.com
    token: <jira-api-token>
    project: PROJ
    # status defines which ticket states trigger anthill.
    # Omit status entirely to disable the poller — anthill run still works.
    status:
      - listener: Ready for Dev         # anthill reacts when a ticket enters this state
        on_start: In Progress           # ticket moves here when the container starts
        on_complete: In Review          # ticket moves here on exit 0
      - listener: Ready for QA
        on_start: In QA
        on_complete: Done

  # Linear support coming soon.
  # linear:
  #   api_key: <token>
  #   team: ENG
  #   status:
  #     - listener: Ready for Dev
  #       on_start: In Progress
  #       on_complete: In Review

# Knowledge Layer — CGC structural graph + Graphiti semantic graph (optional)
# When configured, agent containers automatically index the repo and query
# the knowledge graph before implementing.
knowledge:
  cgc_url: bolt://192.168.1.100:7687      # Neo4j for CGC
  cgc_user: neo4j
  cgc_password: <password>
  graphiti_url: http://192.168.1.100:8001/mcp/  # Graphiti MCP server
  graphiti_group_id: owner/repo           # group_id for this repo in Graphiti
```

### `~/.anthill/secrets.yaml`

```yaml
github_token: ghp_...        # Used for git clone, branch creation, PR management
merge_token: ghp_...         # Token with merge permissions (optional, falls back to github_token)
registry_token: ghp_...      # Token for pulling the image from ghcr.io (read:packages scope)
opencode_api_key: sk-...     # OpenCode API key
brave_api_key: BSA...        # Brave Search API key (optional)
```

The file is written with mode `0600`. Do not commit it.

---

## Agents

The container runs 10 specialized agents built on OpenCode. Uma is the default entry point — it reads the ticket, defines the plan, and either implements directly or delegates to the right specialist.

| Agent | Role |
|---|---|
| uma | Product manager. Reads the ticket, defines the plan, delegates to the right agent. Default dispatcher. |
| carol | UI/UX. Visual components, design systems, user experience. |
| piper | Frontend logic. State management, API integration, client-side business logic. |
| kael | Backend. APIs, database schemas, server-side business logic. |
| atlas | Architecture. File structure, design patterns, module organization. |
| fiona | Refactoring. Code cleanup, dead code removal, technical debt. |
| nova | Performance. Optimization, caching, bundle size, load times. |
| vesper | QA and security. Tests, security audits, vulnerability fixes. |
| echo | DevOps. CI/CD pipelines, Docker, infrastructure, automation. |
| lyra | Documentation and research. Specs, technical docs, analysis. |

Every agent follows the same protocol: check for an existing PR (kill-switch to avoid duplicates), read the ticket and recent PR history, reserve territory with an empty commit and draft PR before writing any code, implement, run lint and tests, then mark the PR ready and auto-merge.

---

## Requirements

| Requirement | Notes |
|---|---|
| GitHub token | Needs repo write access for cloning, branch creation, and PR management |
| OpenCode API key | Get one at [opencode.ai](https://opencode.ai) |
| Docker | Required for the self-hosted daemon. Not needed for the GitHub Action (runs inside the action). |
| Jira API token | Optional. Needed for automatic ticket polling. Without it, use `anthill run <id>` manually. |
| Brave Search API key | Optional. Enables web search inside agent containers. |

The runtime image (`ghcr.io/yoennisrg/anthill:latest`) is hosted on GHCR. A GitHub token with `read:packages` scope is required to pull it — pass it as `registry_token` in `secrets.yaml`.

---

## Release

Releases are triggered by pushing a `v*` tag:

```bash
git tag v1.2.0 && git push --tags
```

This triggers three workflows in parallel:

- **build-image** — builds `ghcr.io/yoennisrg/anthill:latest` and the versioned tag for `linux/amd64` and `linux/arm64`
- **build-cli** — compiles and uploads binaries for `linux/amd64`, `linux/arm64`, `darwin/amd64`, `darwin/arm64` to GitHub Releases
- **publish-action** — mirrors `action.yml` and `README.md` to the public `yoennisrg/anthill-action` repo and tags the release there
