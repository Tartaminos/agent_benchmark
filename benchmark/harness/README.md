# Codex Benchmark Harness

This harness executes one benchmark task with Codex, captures reproducible run artifacts, aggregates token usage across the root thread and persisted descendant subagent rollouts, and sends the resulting metrics to the local Langfuse instance.

The harness is implemented in Ruby and uses only the Ruby standard library. It does not require Python, a virtual environment, pip, or a Langfuse SDK.

Langfuse ingestion is sent after the measured Codex run through the Langfuse v4 OpenTelemetry HTTP/JSON endpoint.

## Fixed execution policy

The runner pins:

- model: `gpt-5.6-sol`
- reasoning effort: `medium`
- human approvals during the measured run: none

It also checks the effective model and reasoning effort recorded in every persisted Codex rollout. A run is marked non-compliant if any thread differs from the fixed policy.

## Setup

From the repository root:

```bash
cp benchmark/harness/.env.example benchmark/harness/.env
```

Edit `benchmark/harness/.env` and add the API keys created by the local Langfuse project. The local Langfuse URL is expected to be:

```text
http://localhost:3001
```

Real credentials must never be committed.

No additional Ruby gems are required by the harness.

## Test Langfuse before the first benchmark

With Langfuse running locally, send a canary trace without invoking Codex:

```bash
ruby benchmark/harness/run_benchmark.rb --check-langfuse
```

The command should print a Langfuse trace ID. Confirm that `benchmark-harness-canary` appears in the local Langfuse UI before starting measured runs.

## Run isolation

Do not execute measured tasks directly on `main` or `baseline`. Create a fresh run branch from the frozen baseline first:

```bash
git checkout baseline
git checkout -b runs/baseline-task-01-run-01
```

The runner requires a clean working tree and resets the benchmark database before starting the timer.

## Task 01 example

```bash
ruby benchmark/harness/run_benchmark.rb \
  --task tasks/01-order-details-api.md \
  --workflow baseline \
  --run 1
```

For Task 04, attach the visual reference explicitly:

```bash
ruby benchmark/harness/run_benchmark.rb \
  --task tasks/04-admin-orders-dashboard.md \
  --image tasks/task_4_image_reference.png \
  --workflow baseline \
  --run 1
```

The prompt explicitly invokes the project orchestration skill with `$software-development-workflow`.

## Measured outputs

By default, run artifacts are written to the sibling directory `../agent_benchmark_runs`, outside the benchmark repository:

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
- root and descendant subagent thread count;
- input, cached-input, output, reasoning-output, and cache-write token telemetry when available;
- estimated Codex credits;
- base-rate API-equivalent USD cost for comparison;
- effective model/reasoning policy compliance per thread;
- Codex version and a SHA-256 fingerprint of the external Codex config;
- initial/final Git state and change statistics;
- human intervention count;
- Langfuse ingestion status and trace ID.

Database reset, metric parsing, Git inspection, and Langfuse ingestion occur outside the measured `codex exec` wall time.

## Why persisted Codex rollouts are required

`codex exec --json` provides the root thread event stream, but a multi-agent workflow can create separate Codex threads for subagents. The harness therefore does not use `--ephemeral`: after the run, it follows each rollout's `parent_thread_id` from the root thread and sums the final cumulative usage of every thread in that execution tree.

This prevents the benchmark from reporting only the orchestrator's tokens while omitting Architecture, Implementation, Tests, Review, QA, or other spawned agents.

## Langfuse representation

Each measured benchmark run becomes one Langfuse trace.

The trace root stores run-level metadata such as workflow, task, run number, Git commit, wall time and exit status. Each persisted Codex thread is exported as a child `generation` observation containing its model, reasoning effort, token usage and equivalent API cost.

The exporter uses the self-hosted Langfuse v4 endpoint:

```text
POST /api/public/otel/v1/traces
```

with OpenTelemetry HTTP/JSON, project-key Basic Authentication, and `x-langfuse-ingestion-version: 4`.

## Cost fields

`estimated_codex_credits` uses the GPT-5.6 Sol Codex token rate card frozen by the harness on `2026-08-14`:

- uncached input: 125 credits / 1M tokens
- cached input: 12.5 credits / 1M tokens
- output: 750 credits / 1M tokens

`api_equivalent_cost_usd_base_rate` uses the GPT-5.6 Sol base API rates frozen on the same date:

- uncached input: USD 5 / 1M tokens
- cached input: USD 0.50 / 1M tokens
- output: USD 30 / 1M tokens

The API-equivalent value is a comparison metric, not a statement of cash charged to the ChatGPT subscription. It intentionally uses the base token rates and does not attempt to reconstruct request-level large-context multipliers from cumulative Codex thread telemetry.
