# AI Agent Benchmark

A controlled benchmark for measuring AI-assisted software-development workflows on a real Ruby on Rails codebase.

The project evaluates how different Codex workflow configurations affect software delivery across the same sequence of engineering tasks while collecting objective telemetry such as execution time, token consumption, cost, code changes, execution hierarchy, and model-policy compliance.

## What is being benchmarked?

Instead of evaluating an LLM with isolated coding questions, this benchmark executes a sequence of software-engineering tasks against the same application.

Each experiment starts from a common project baseline and runs the same tasks in the same order. The workflow configuration is the experimental variable.

~~~text
main
├── baseline
├── remove-agents-from-flow
├── experiment/functionality-first
├── experiment/no-qa
├── experiment/reduced-context
└── ...

Task 01 -> commit
Task 02 -> commit
Task 03 -> commit
...
~~~

This makes the benchmark closer to a real development workflow: changes persist between tasks and later tasks operate on the code produced by earlier ones.

### Functionality-first experiment

`experiment/functionality-first` is derived directly from `remove-agents-from-flow`,
the current reference workflow for this experiment.

It preserves the same agent pipeline, orchestration model, task flow, model policy, and
functional verification requirements. The experimental variable is the optimization
objective applied to implementation work.

The functionality-first branch still requires correct observable behavior, explicit
contracts, security, data integrity, runtime compatibility, automated verification, and
approved UI/UX behavior. However, internal code quality is deliberately non-gating:
descriptive naming, DRY, SOLID, idiomatic style, abstraction quality, method size,
maintainability, extensibility, and code elegance are not optimization targets unless a
task explicitly requires them.

The branch is intended to measure how much time, token usage, and cost are associated
with producing sustainable code versus producing code that primarily works.

## Goals

The benchmark is intended to investigate questions such as:

- How does workflow complexity affect engineering output?
- What is the token and execution-time overhead introduced by orchestration?
- How much does context or workflow structure affect implementation?
- Are additional reasoning or agent steps worth their computational cost?
- How do simple and multi-threaded workflows compare when their total resource usage is accounted for?
- Can AI coding workflows be compared reproducibly instead of only subjectively?

This is not intended to answer which model is "the smartest." The benchmark primarily evaluates software-development workflow configurations while keeping the model, reasoning policy, task sequence, and project baseline controlled.

## Repository structure

~~~text
.
├── app/                    # Rails application modified by benchmark tasks
├── benchmark/
│   ├── harness/            # Benchmark runner and operational documentation
│   └── snapshots/          # Baseline data integrity metadata
├── tasks/                  # Fixed engineering tasks used by experiments
├── AGENTS.md               # Project-scoped benchmark instructions
└── README.md
~~~

The current task suite includes API work, performance optimization, domain classification, an admin dashboard, reporting, bulk export, and data reconciliation.

## Benchmark architecture

The project has three main components:

1. **Rails application**  
   The real codebase modified during the benchmark.

2. **Benchmark tasks**  
   A fixed sequence of engineering tasks executed against the application.

3. **Benchmark harness**  
   A Ruby runner that executes Codex, captures telemetry, inspects Git state, aggregates persisted execution threads, and exports traces to Langfuse.

Detailed runner documentation lives in [benchmark/harness/README.md](benchmark/harness/README.md).

## Controlled execution

To keep runs comparable, the harness pins the measured execution policy:

- model: gpt-5.6-sol
- reasoning effort: medium
- human approvals during the measured run: none

After execution, the harness verifies the effective model and reasoning effort recorded in persisted Codex rollouts. A run is marked non-compliant if any thread differs from the fixed benchmark policy.

## What is measured?

Each benchmark run records metrics including:

- wall-clock time for the measured codex exec;
- root and descendant execution-thread count;
- input tokens;
- cached-input tokens;
- output tokens;
- reasoning-output telemetry when available;
- estimated Codex credits;
- API-equivalent base-rate cost;
- initial and final Git state;
- Git change statistics;
- human intervention count;
- Codex version;
- external configuration fingerprint;
- effective model/reasoning policy compliance;
- Langfuse trace and ingestion status.

Metric parsing, Git inspection, and telemetry export happen outside the measured codex exec wall time.

## Multi-thread accounting

Codex workflows may create additional execution threads.

Counting only the root codex exec --json event stream would under-report the actual resource consumption of an orchestrated workflow.

The harness therefore keeps persisted Codex rollouts and follows their parent_thread_id relationships from the root execution. It then aggregates the cumulative usage across the complete execution tree.

This allows a simple workflow and a multi-threaded workflow to be compared using the total resources actually consumed by each execution.

## Observability with Langfuse

Each measured benchmark run can be exported to a local Langfuse instance.

A benchmark execution becomes one Langfuse trace, while persisted Codex threads are represented as child generation observations.

This makes it possible to inspect:

- execution hierarchy;
- model and reasoning configuration;
- token usage;
- equivalent cost;
- timing;
- workflow metadata.

The harness uses Langfuse's OpenTelemetry HTTP/JSON ingestion endpoint.

## Reproducibility

The benchmark follows a few rules to keep experiments comparable:

- main is the common project base;
- experiments use separate branches;
- every experiment executes the same task sequence;
- tasks run in the same order;
- produced application changes are committed between tasks;
- each measured run begins with a clean Git working tree;
- the runner does not silently reset the project or database between tasks;
- credentials and generated benchmark artifacts stay outside the repository.

The intention is to change one workflow characteristic at a time while keeping the software-engineering problem constant.

## Running the benchmark

Copy the harness environment template:

~~~bash
cp benchmark/harness/.env.example benchmark/harness/.env
~~~

Configure the local Langfuse credentials, then verify connectivity before running Codex:

~~~bash
ruby benchmark/harness/run_benchmark.rb --check-langfuse
~~~

Run a benchmark task:

~~~bash
ruby benchmark/harness/run_benchmark.rb \
  --task tasks/01-order-details-api.md \
  --workflow baseline \
  --run 1
~~~

Tasks with visual references can explicitly attach the image:

~~~bash
ruby benchmark/harness/run_benchmark.rb \
  --task tasks/04-admin-orders-dashboard.md \
  --image tasks/task_4_image_reference.png \
  --workflow baseline \
  --run 1
~~~

See [benchmark/harness/README.md](benchmark/harness/README.md) for the complete execution policy, environment setup, cost model, and telemetry details.

## Benchmark outputs

Run artifacts are stored outside the benchmark repository by default:

~~~text
../agent_benchmark_runs/
└── <workflow>/
    └── task_01/
        └── run_01/
            ├── events.jsonl
            ├── stderr.log
            ├── final_message.txt
            ├── git.diff
            ├── git_status.txt
            └── result.json
~~~

Keeping telemetry outside the repository prevents benchmark output from modifying the codebase being measured.

## Tech stack

- Ruby on Rails 8.1
- Ruby
- PostgreSQL
- Codex CLI
- Langfuse
- OpenTelemetry HTTP/JSON
- Git

The benchmark harness itself uses only the Ruby standard library.

## Why this project exists

Most AI coding comparisons focus on isolated prompts or final answers.

This project treats AI-assisted development as a software-engineering workflow instead: the model receives a real repository, executes sequential tasks, changes persistent code, and is measured with reproducible telemetry.

The goal is not only to inspect whether a task was completed, but also to understand the engineering cost of the workflow that produced it.
