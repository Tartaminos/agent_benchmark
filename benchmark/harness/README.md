# Codex Benchmark Harness

This harness executes one benchmark task with Codex, captures reproducible run artifacts, aggregates token usage across the root thread and persisted descendant subagent rollouts, and sends the resulting metrics to the local Langfuse instance.

## Fixed execution policy

The runner pins:

- model: `gpt-5.6-sol`
- reasoning effort: `medium`
- human approvals during the measured run: `never`

It also checks the effective model and reasoning effort recorded in every Codex rollout. A run is marked non-compliant if any thread differs from the fixed policy.

## Setup

From the repository root:

```bash
python3 -m venv benchmark/harness/.venv
source benchmark/harness/.venv/bin/activate
pip install -r benchmark/harness/requirements.txt
cp benchmark/harness/.env.example benchmark/harness/.env
```

Edit `benchmark/harness/.env` and add the API keys created by the local Langfuse project. The local Langfuse URL is expected to be `http://localhost:3001`.

Real credentials must never be committed.

## Run isolation

Do not execute measured tasks directly on `main` or `baseline`. Create a fresh run branch from the frozen baseline first:

```bash
git checkout baseline
git checkout -b runs/baseline-task-01-run-01
```

The runner requires a clean working tree and resets the benchmark database before starting the timer.

## Task 01 example

```bash
source benchmark/harness/.venv/bin/activate

python benchmark/harness/run_benchmark.py \
  --task tasks/01-order-details-api.md \
  --workflow baseline \
  --run 1
```

For Task 04, attach the visual reference explicitly:

```bash
python benchmark/harness/run_benchmark.py \
  --task tasks/04-admin-orders-dashboard.md \
  --image tasks/task_4_image_reference.png \
  --workflow baseline \
  --run 1
```

## Measured outputs

By default, run artifacts are written to the sibling directory `../agent_benchmark_runs`, outside the repository seen by Codex:

```text
agent_benchmark_runs/
└── baseline/
    └── task_01/
        └── run_01/
            ├── events.jsonl
            ├── stderr.log
            ├── final_message.txt
            ├── git.diff
            ├── git_status.txt
            └── result.json
```

`result.json` records, among other fields:

- wall-clock time for `codex exec` only;
- root and subagent thread count;
- input, cached-input, output, reasoning-output, and cache-write token telemetry when available;
- estimated Codex credits;
- base-rate API-equivalent USD cost for comparison;
- effective model/reasoning policy compliance per thread;
- Codex version and a SHA-256 fingerprint of the external Codex config;
- initial/final Git state and change statistics;
- human intervention count.

Database reset, metric parsing, Git inspection, and Langfuse ingestion occur outside the measured `codex exec` wall time.

## Why persisted Codex rollouts are required

`codex exec --json` provides the root thread event stream, but a multi-agent workflow can create separate Codex threads for subagents. The harness therefore does not use `--ephemeral`: after the run, it follows each rollout's `parent_thread_id` from the root thread and sums the final cumulative usage of every thread in that execution tree.

This prevents the benchmark from reporting only the orchestrator's tokens while omitting Architecture, Implementation, Tests, Review, QA, or other spawned agents.

## Cost fields

`estimated_codex_credits` uses the token-based GPT-5.6 Sol Codex rate card frozen by the harness on `2026-08-14`.

`api_equivalent_cost_usd_base_rate` is a comparison metric based on the model's base API token prices. It is not a statement of cash charged to the ChatGPT subscription and intentionally does not attempt to reconstruct per-request large-context pricing from cumulative Codex thread telemetry.
