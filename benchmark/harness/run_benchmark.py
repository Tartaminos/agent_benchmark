#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone
from typing import Any

MODEL = "gpt-5.6-sol"
REASONING_EFFORT = "medium"
PRICING_REFERENCE_DATE = "2026-08-14"
CODEX_CREDITS_PER_MTOK = {
    "input": 125.0,
    "cached_input": 12.5,
    "output": 750.0,
}
API_BASE_USD_PER_MTOK = {
    "input": 5.0,
    "cached_input": 0.5,
    "output": 30.0,
}
PROTECTED_BRANCHES = {"main", "baseline"}
USAGE_FIELDS = (
    "input_tokens",
    "cached_input_tokens",
    "cache_write_input_tokens",
    "output_tokens",
    "reasoning_output_tokens",
)


def run_cmd(args: list[str], cwd: Path, *, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        cwd=cwd,
        check=check,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def load_env_file(path: Path) -> None:
    if not path.exists():
        return
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if value and value[0] == value[-1] and value[0] in {'"', "'"}:
            value = value[1:-1]
        os.environ.setdefault(key, value)


def sha256_file(path: Path) -> str | None:
    if not path.exists() or not path.is_file():
        return None
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_iso8601(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        normalized = value[:-1] + "+00:00" if value.endswith("Z") else value
        parsed = datetime.fromisoformat(normalized)
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=timezone.utc)
        return parsed.astimezone(timezone.utc)
    except ValueError:
        return None


def first_session_meta(path: Path) -> dict[str, Any] | None:
    try:
        with path.open("r", encoding="utf-8") as handle:
            for _ in range(20):
                line = handle.readline()
                if not line:
                    return None
                try:
                    event = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if event.get("type") != "session_meta":
                    continue
                payload = event.get("payload") or {}
                if isinstance(payload.get("meta"), dict):
                    payload = payload["meta"]
                if isinstance(payload, dict):
                    return payload
    except OSError:
        return None
    return None


def nested_parent_thread_id(meta: dict[str, Any]) -> str | None:
    direct = meta.get("parent_thread_id")
    if isinstance(direct, str) and direct:
        return direct

    source = meta.get("source")
    if not isinstance(source, dict):
        return None
    subagent = source.get("subagent")
    if not isinstance(subagent, dict):
        return None
    thread_spawn = subagent.get("thread_spawn")
    if not isinstance(thread_spawn, dict):
        return None
    parent = thread_spawn.get("parent_thread_id")
    return parent if isinstance(parent, str) and parent else None


def index_rollouts(codex_home: Path) -> dict[str, dict[str, Any]]:
    sessions_root = codex_home / "sessions"
    indexed: dict[str, dict[str, Any]] = {}
    if not sessions_root.exists():
        return indexed

    for path in sessions_root.rglob("rollout-*.jsonl"):
        meta = first_session_meta(path)
        if not meta:
            continue
        thread_id = meta.get("id")
        if not isinstance(thread_id, str) or not thread_id:
            continue
        indexed[thread_id] = {
            "path": path,
            "meta": meta,
            "parent_thread_id": nested_parent_thread_id(meta),
        }
    return indexed


def rollout_tree(indexed: dict[str, dict[str, Any]], root_thread_id: str) -> list[str]:
    selected = {root_thread_id}
    changed = True
    while changed:
        changed = False
        for thread_id, record in indexed.items():
            if thread_id in selected:
                continue
            if record.get("parent_thread_id") in selected:
                selected.add(thread_id)
                changed = True
    return sorted(selected, key=lambda value: (value != root_thread_id, value))


def extract_thread_metrics(path: Path, meta: dict[str, Any]) -> dict[str, Any]:
    started_at = parse_iso8601(meta.get("timestamp"))
    latest_context_at: datetime | None = None
    latest_context: dict[str, Any] = {}
    latest_usage_at: datetime | None = None
    latest_usage: dict[str, int] = {field: 0 for field in USAGE_FIELDS}
    token_count_events = 0

    try:
        with path.open("r", encoding="utf-8") as handle:
            for line in handle:
                try:
                    event = json.loads(line)
                except json.JSONDecodeError:
                    continue

                event_time = parse_iso8601(event.get("timestamp"))
                if started_at and event_time and event_time < started_at:
                    # Child rollout histories can contain copied parent events.
                    continue

                event_type = event.get("type")
                payload = event.get("payload") or {}

                if event_type == "turn_context" and isinstance(payload, dict):
                    if latest_context_at is None or event_time is None or event_time >= latest_context_at:
                        latest_context = payload
                        latest_context_at = event_time or latest_context_at

                if event_type != "event_msg" or not isinstance(payload, dict):
                    continue
                if payload.get("type") != "token_count":
                    continue

                info = payload.get("info") or {}
                usage = info.get("total_token_usage") or {}
                if not isinstance(usage, dict):
                    continue

                token_count_events += 1
                if latest_usage_at is not None and event_time is not None and event_time < latest_usage_at:
                    continue
                latest_usage = {
                    field: int(usage.get(field, 0) or 0)
                    for field in USAGE_FIELDS
                }
                latest_usage_at = event_time or latest_usage_at
    except OSError as exc:
        raise RuntimeError(f"Unable to read rollout {path}: {exc}") from exc

    return {
        "thread_id": meta.get("id"),
        "parent_thread_id": nested_parent_thread_id(meta),
        "agent_path": meta.get("agent_path"),
        "agent_role": meta.get("agent_role"),
        "agent_nickname": meta.get("agent_nickname"),
        "thread_source": meta.get("thread_source"),
        "source": meta.get("source"),
        "rollout_path": str(path),
        "started_at": meta.get("timestamp"),
        "model": latest_context.get("model"),
        "reasoning_effort": latest_context.get("effort"),
        "approval_policy": latest_context.get("approval_policy"),
        "sandbox_policy": latest_context.get("sandbox_policy"),
        "token_count_events": token_count_events,
        "usage": latest_usage,
    }


def aggregate_usage(threads: list[dict[str, Any]]) -> dict[str, int]:
    total = {field: 0 for field in USAGE_FIELDS}
    for thread in threads:
        usage = thread.get("usage") or {}
        for field in USAGE_FIELDS:
            total[field] += int(usage.get(field, 0) or 0)
    return total


def usage_breakdown(usage: dict[str, int]) -> dict[str, float | int]:
    input_tokens = int(usage.get("input_tokens", 0) or 0)
    cached_input_tokens = min(
        input_tokens,
        max(0, int(usage.get("cached_input_tokens", 0) or 0)),
    )
    uncached_input_tokens = max(0, input_tokens - cached_input_tokens)
    output_tokens = max(0, int(usage.get("output_tokens", 0) or 0))

    credits = (
        uncached_input_tokens * CODEX_CREDITS_PER_MTOK["input"]
        + cached_input_tokens * CODEX_CREDITS_PER_MTOK["cached_input"]
        + output_tokens * CODEX_CREDITS_PER_MTOK["output"]
    ) / 1_000_000

    api_base_usd = (
        uncached_input_tokens * API_BASE_USD_PER_MTOK["input"]
        + cached_input_tokens * API_BASE_USD_PER_MTOK["cached_input"]
        + output_tokens * API_BASE_USD_PER_MTOK["output"]
    ) / 1_000_000

    return {
        "uncached_input_tokens": uncached_input_tokens,
        "cached_input_tokens": cached_input_tokens,
        "output_tokens": output_tokens,
        "estimated_codex_credits": credits,
        "api_equivalent_cost_usd_base_rate": api_base_usd,
    }


def parse_exec_events(path: Path) -> dict[str, Any]:
    root_thread_id: str | None = None
    turn_usage: dict[str, int] | None = None
    event_count = 0
    invalid_lines = 0

    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            if not line.strip():
                continue
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                invalid_lines += 1
                continue
            event_count += 1
            if event.get("type") == "thread.started":
                value = event.get("thread_id")
                if isinstance(value, str):
                    root_thread_id = value
            elif event.get("type") == "turn.completed":
                usage = event.get("usage")
                if isinstance(usage, dict):
                    turn_usage = {
                        field: int(usage.get(field, 0) or 0)
                        for field in USAGE_FIELDS
                    }

    return {
        "root_thread_id": root_thread_id,
        "root_turn_usage": turn_usage,
        "event_count": event_count,
        "invalid_json_lines": invalid_lines,
    }


def git_diff_stats(repo_root: Path, initial_commit: str) -> dict[str, int]:
    result = run_cmd(["git", "diff", "--numstat", initial_commit], repo_root)
    files_changed = 0
    lines_added = 0
    lines_deleted = 0
    for line in result.stdout.splitlines():
        parts = line.split("\t", 2)
        if len(parts) != 3:
            continue
        added, deleted, _ = parts
        files_changed += 1
        if added.isdigit():
            lines_added += int(added)
        if deleted.isdigit():
            lines_deleted += int(deleted)

    untracked = run_cmd(
        ["git", "ls-files", "--others", "--exclude-standard"],
        repo_root,
    ).stdout.splitlines()

    return {
        "tracked_files_changed": files_changed,
        "lines_added": lines_added,
        "lines_deleted": lines_deleted,
        "untracked_files": len([line for line in untracked if line.strip()]),
    }


def validate_langfuse_env() -> None:
    required = ("LANGFUSE_PUBLIC_KEY", "LANGFUSE_SECRET_KEY", "LANGFUSE_BASE_URL")
    missing = [key for key in required if not os.environ.get(key)]
    if missing:
        raise RuntimeError(
            "Missing Langfuse configuration: " + ", ".join(missing)
            + ". Copy benchmark/harness/.env.example to benchmark/harness/.env and fill it locally."
        )


def send_to_langfuse(result: dict[str, Any], task_text: str) -> str | None:
    from langfuse import get_client

    langfuse = get_client()
    trace_name = (
        f"{result['workflow']}/task_{result['task_id']}/run_{result['run']:02d}"
    )

    with langfuse.start_as_current_observation(
        as_type="span",
        name=trace_name,
        input={"task": task_text},
        metadata={
            "workflow": result["workflow"],
            "task_id": result["task_id"],
            "run": result["run"],
            "branch": result["branch"],
            "initial_commit": result["initial_commit"],
            "final_commit": result["final_commit"],
            "codex_version": result["codex_version"],
            "model": result["model"],
            "reasoning_effort": result["reasoning_effort"],
            "root_thread_id": result["root_thread_id"],
            "human_interventions": result["human_interventions"],
        },
        level="DEFAULT" if result["exit_code"] == 0 else "ERROR",
    ) as root_span:
        root_span.update(
            output={
                "exit_code": result["exit_code"],
                "wall_time_seconds": result["wall_time_seconds"],
                "estimated_codex_credits": result["cost"]["estimated_codex_credits"],
                "api_equivalent_cost_usd_base_rate": result["cost"]["api_equivalent_cost_usd_base_rate"],
                "model_policy_compliant": result["model_policy_compliant"],
            }
        )

        for index, thread in enumerate(result["threads"], start=1):
            usage = thread["usage"]
            breakdown = usage_breakdown(usage)
            input_uncached = int(breakdown["uncached_input_tokens"])
            input_cached = int(breakdown["cached_input_tokens"])
            output_tokens = int(breakdown["output_tokens"])
            role = thread.get("agent_role") or thread.get("agent_path") or (
                "root" if thread["thread_id"] == result["root_thread_id"] else "subagent"
            )

            with langfuse.start_as_current_observation(
                as_type="generation",
                name=f"{index:02d}-{role}",
                model=thread.get("model") or result["model"],
                model_parameters={
                    "reasoning_effort": thread.get("reasoning_effort") or "unknown"
                },
                metadata={
                    "thread_id": thread["thread_id"],
                    "parent_thread_id": thread.get("parent_thread_id"),
                    "agent_path": thread.get("agent_path"),
                    "agent_role": thread.get("agent_role"),
                    "agent_nickname": thread.get("agent_nickname"),
                    "token_count_events": thread.get("token_count_events", 0),
                    "reasoning_output_tokens": usage.get("reasoning_output_tokens", 0),
                    "cache_write_input_tokens": usage.get("cache_write_input_tokens", 0),
                    "estimated_codex_credits": breakdown["estimated_codex_credits"],
                    "api_equivalent_cost_usd_base_rate": breakdown["api_equivalent_cost_usd_base_rate"],
                },
                usage_details={
                    "input": input_uncached,
                    "input_cached_tokens": input_cached,
                    "output": output_tokens,
                },
                cost_details={
                    "input": input_uncached * API_BASE_USD_PER_MTOK["input"] / 1_000_000,
                    "input_cached_tokens": input_cached * API_BASE_USD_PER_MTOK["cached_input"] / 1_000_000,
                    "output": output_tokens * API_BASE_USD_PER_MTOK["output"] / 1_000_000,
                },
            ):
                pass

        root_span.score_trace(
            name="wall_time_seconds",
            value=float(result["wall_time_seconds"]),
            data_type="NUMERIC",
        )
        root_span.score_trace(
            name="codex_credits",
            value=float(result["cost"]["estimated_codex_credits"]),
            data_type="NUMERIC",
        )
        root_span.score_trace(
            name="api_equivalent_usd_base_rate",
            value=float(result["cost"]["api_equivalent_cost_usd_base_rate"]),
            data_type="NUMERIC",
        )
        root_span.score_trace(
            name="execution_success",
            value=1.0 if result["exit_code"] == 0 else 0.0,
            data_type="BOOLEAN",
        )
        root_span.score_trace(
            name="model_policy_compliant",
            value=1.0 if result["model_policy_compliant"] else 0.0,
            data_type="BOOLEAN",
        )
        trace_id = getattr(root_span, "trace_id", None)

    langfuse.flush()
    return str(trace_id) if trace_id else None


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Run one Codex benchmark task and record reproducible metrics."
    )
    parser.add_argument("--task", required=True, help="Task markdown path inside the repository.")
    parser.add_argument("--workflow", required=True, help="Workflow/configuration label, e.g. baseline.")
    parser.add_argument("--run", type=int, default=1, help="1-based repetition number.")
    parser.add_argument("--image", action="append", default=[], help="Optional image path to attach. Repeatable.")
    parser.add_argument("--skip-db-reset", action="store_true", help="Skip restoring the benchmark database snapshot.")
    parser.add_argument("--allow-protected-branch", action="store_true", help="Allow execution directly on main/baseline (not recommended).")
    args = parser.parse_args()

    script_path = Path(__file__).resolve()
    repo_root = run_cmd(
        ["git", "rev-parse", "--show-toplevel"], script_path.parent
    ).stdout.strip()
    repo_root = Path(repo_root).resolve()

    env_path = script_path.parent / ".env"
    load_env_file(env_path)
    validate_langfuse_env()

    task_path = (repo_root / args.task).resolve()
    if repo_root not in task_path.parents or not task_path.is_file():
        raise RuntimeError(f"Task must be an existing file inside the repository: {task_path}")

    image_paths: list[Path] = []
    for raw_image in args.image:
        image_path = (repo_root / raw_image).resolve()
        if repo_root not in image_path.parents or not image_path.is_file():
            raise RuntimeError(f"Image must be an existing file inside the repository: {image_path}")
        image_paths.append(image_path)

    branch = run_cmd(["git", "branch", "--show-current"], repo_root).stdout.strip()
    if not branch:
        raise RuntimeError("Benchmark runs require a named Git branch, not detached HEAD.")
    if branch in PROTECTED_BRANCHES and not args.allow_protected_branch:
        raise RuntimeError(
            f"Refusing to mutate protected branch '{branch}'. Create a run branch from baseline first."
        )

    status_before = run_cmd(["git", "status", "--porcelain"], repo_root).stdout
    if status_before.strip():
        raise RuntimeError("Working tree must be clean before a measured run.")

    initial_commit = run_cmd(["git", "rev-parse", "HEAD"], repo_root).stdout.strip()
    codex_bin = shutil.which("codex")
    if not codex_bin:
        raise RuntimeError("codex executable not found in PATH.")
    codex_version_proc = subprocess.run(
        [codex_bin, "--version"], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT
    )
    codex_version = codex_version_proc.stdout.strip()

    codex_home = Path(os.environ.get("CODEX_HOME", Path.home() / ".codex")).expanduser().resolve()
    codex_config_sha256 = sha256_file(codex_home / "config.toml")

    if not args.skip_db_reset:
        reset_script = repo_root / "script" / "reset_benchmark_db.sh"
        if not reset_script.is_file():
            raise RuntimeError(f"Database reset script not found: {reset_script}")
        print("Resetting benchmark database...", flush=True)
        subprocess.run([str(reset_script)], cwd=repo_root, check=True)

    task_id = task_path.stem.split("-", 1)[0]
    runs_root_raw = os.environ.get("BENCHMARK_RUNS_ROOT", "../agent_benchmark_runs")
    runs_root = Path(runs_root_raw).expanduser()
    if not runs_root.is_absolute():
        runs_root = (repo_root / runs_root).resolve()
    run_dir = runs_root / args.workflow / f"task_{task_id}" / f"run_{args.run:02d}"
    if run_dir.exists() and any(run_dir.iterdir()):
        raise RuntimeError(f"Run directory is not empty: {run_dir}")
    run_dir.mkdir(parents=True, exist_ok=True)

    events_path = run_dir / "events.jsonl"
    stderr_path = run_dir / "stderr.log"
    final_message_path = run_dir / "final_message.txt"

    prompt = (
        f"$software-development-workflow Execute the benchmark task defined in "
        f"{task_path.relative_to(repo_root).as_posix()}. Complete the entire workflow "
        "autonomously and stop when the task is complete."
    )

    command = [
        codex_bin,
        "exec",
        "--json",
        "--ask-for-approval",
        "never",
        "--model",
        MODEL,
        "-c",
        f'model_reasoning_effort="{REASONING_EFFORT}"',
        "--output-last-message",
        str(final_message_path),
    ]
    for image_path in image_paths:
        command.extend(["--image", str(image_path)])
    command.append(prompt)

    print(
        f"Running {args.workflow} task {task_id} run {args.run:02d} "
        f"with {MODEL} / {REASONING_EFFORT}...",
        flush=True,
    )

    started_at = datetime.now(timezone.utc)
    wall_start = time.monotonic()
    with events_path.open("w", encoding="utf-8") as stdout_handle, stderr_path.open(
        "w", encoding="utf-8"
    ) as stderr_handle:
        process = subprocess.run(
            command,
            cwd=repo_root,
            text=True,
            stdout=stdout_handle,
            stderr=stderr_handle,
        )
    wall_time_seconds = time.monotonic() - wall_start
    ended_at = datetime.now(timezone.utc)

    exec_events = parse_exec_events(events_path)
    root_thread_id = exec_events["root_thread_id"]
    if not root_thread_id:
        raise RuntimeError(
            "Codex did not emit a thread.started event; cannot attribute multi-agent usage."
        )

    indexed = index_rollouts(codex_home)
    if root_thread_id not in indexed:
        raise RuntimeError(
            "Root rollout was not found. Benchmark instrumentation requires persisted Codex rollouts; do not use --ephemeral."
        )

    thread_ids = rollout_tree(indexed, root_thread_id)
    threads = [
        extract_thread_metrics(indexed[thread_id]["path"], indexed[thread_id]["meta"])
        for thread_id in thread_ids
    ]
    total_usage = aggregate_usage(threads)
    cost = usage_breakdown(total_usage)

    policy_violations = []
    for thread in threads:
        if thread.get("model") != MODEL or thread.get("reasoning_effort") != REASONING_EFFORT:
            policy_violations.append(
                {
                    "thread_id": thread["thread_id"],
                    "agent_role": thread.get("agent_role"),
                    "agent_path": thread.get("agent_path"),
                    "actual_model": thread.get("model"),
                    "actual_reasoning_effort": thread.get("reasoning_effort"),
                }
            )

    final_commit = run_cmd(["git", "rev-parse", "HEAD"], repo_root).stdout.strip()
    diff_text = run_cmd(["git", "diff", initial_commit], repo_root).stdout
    (run_dir / "git.diff").write_text(diff_text, encoding="utf-8")
    git_status = run_cmd(["git", "status", "--porcelain=v1"], repo_root).stdout
    (run_dir / "git_status.txt").write_text(git_status, encoding="utf-8")
    diff_stats = git_diff_stats(repo_root, initial_commit)

    try:
        langfuse_version = importlib.metadata.version("langfuse")
    except importlib.metadata.PackageNotFoundError:
        langfuse_version = "not-installed"

    result: dict[str, Any] = {
        "schema_version": 1,
        "workflow": args.workflow,
        "task_id": task_id,
        "task_path": task_path.relative_to(repo_root).as_posix(),
        "run": args.run,
        "branch": branch,
        "initial_commit": initial_commit,
        "final_commit": final_commit,
        "model": MODEL,
        "reasoning_effort": REASONING_EFFORT,
        "pricing_reference_date": PRICING_REFERENCE_DATE,
        "codex_credit_rates_per_million_tokens": CODEX_CREDITS_PER_MTOK,
        "api_base_usd_rates_per_million_tokens": API_BASE_USD_PER_MTOK,
        "model_policy_compliant": not policy_violations,
        "model_policy_violations": policy_violations,
        "codex_version": codex_version,
        "codex_config_sha256": codex_config_sha256,
        "langfuse_version": langfuse_version,
        "started_at": started_at.isoformat(),
        "ended_at": ended_at.isoformat(),
        "wall_time_seconds": wall_time_seconds,
        "exit_code": process.returncode,
        "human_interventions": 0,
        "root_thread_id": root_thread_id,
        "thread_count": len(threads),
        "exec_events": exec_events,
        "usage": total_usage,
        "cost": cost,
        "git": diff_stats,
        "threads": threads,
        "instrumentation_notes": [
            "Total token usage is the sum of the root Codex thread and all persisted descendant subagent rollouts linked by parent_thread_id.",
            "Codex credits are estimated from the published GPT-5.6 Sol token-based Codex rate card.",
            "api_equivalent_cost_usd_base_rate is a comparison metric using base API token prices; it is not a claim about cash charged to the ChatGPT subscription and does not model per-request large-context surcharges.",
            "wall_time_seconds measures only codex exec wall-clock time; database reset, parsing, Git inspection, and Langfuse ingestion are excluded.",
        ],
    }

    task_text = task_path.read_text(encoding="utf-8")
    result_path = run_dir / "result.json"
    result_path.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    try:
        result["langfuse_trace_id"] = send_to_langfuse(result, task_text)
        result_path.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    except Exception as exc:  # Preserve benchmark data even if observability ingestion fails.
        result["langfuse_error"] = f"{type(exc).__name__}: {exc}"
        result_path.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        print(f"Warning: Langfuse ingestion failed: {exc}", file=sys.stderr)

    print(f"Run artifacts: {run_dir}")
    print(f"Wall time: {wall_time_seconds:.2f}s")
    print(f"Threads measured: {len(threads)}")
    print(f"Input tokens: {total_usage['input_tokens']}")
    print(f"Cached input tokens: {total_usage['cached_input_tokens']}")
    print(f"Output tokens: {total_usage['output_tokens']}")
    print(f"Estimated Codex credits: {cost['estimated_codex_credits']:.4f}")
    print(f"API-equivalent base cost: ${cost['api_equivalent_cost_usd_base_rate']:.4f}")
    print(f"Model policy compliant: {not policy_violations}")
    print(f"Codex exit code: {process.returncode}")

    return process.returncode


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        print("Benchmark interrupted by user.", file=sys.stderr)
        raise SystemExit(130)
    except Exception as exc:
        print(f"Benchmark harness error: {exc}", file=sys.stderr)
        raise SystemExit(2)
