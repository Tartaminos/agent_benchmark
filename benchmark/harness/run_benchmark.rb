#!/usr/bin/env ruby
# frozen_string_literal: true

require "base64"
require "digest"
require "fileutils"
require "json"
require "net/http"
require "open3"
require "optparse"
require "pathname"
require "securerandom"
require "time"
require "uri"

MODEL = "gpt-5.6-sol"
REASONING_EFFORT = "medium"
PRICING_REFERENCE_DATE = "2026-08-14"
CODEX_CREDITS_PER_MTOK = {
  "input" => 125.0,
  "cached_input" => 12.5,
  "output" => 750.0
}.freeze
API_USD_PER_MTOK = {
  "input" => 5.0,
  "cached_input" => 0.5,
  "output" => 30.0
}.freeze
PROTECTED_BRANCHES = %w[main].freeze
USAGE_FIELDS = %w[
  input_tokens
  cached_input_tokens
  cache_write_input_tokens
  output_tokens
  reasoning_output_tokens
].freeze

class BenchmarkError < StandardError; end

class BenchmarkRunner
  def initialize(options)
    @options = options
    @repo_root = Pathname.new(__dir__).join("../..").expand_path
    @harness_dir = Pathname.new(__dir__).expand_path
    load_env_file(@harness_dir.join(".env"))
  end

  def run
    if @options[:check_langfuse]
      check_langfuse!
      return 0
    end

    validate_inputs!
    validate_langfuse_env! unless @options[:no_langfuse]
    validate_repository_state!

    task_path = absolute_repo_path(@options.fetch(:task))
    image_path = @options[:image] && absolute_repo_path(@options[:image])
    task_id = infer_task_id(task_path)
    workflow = @options.fetch(:workflow)
    run_number = @options.fetch(:run)

    output_dir = build_output_dir(workflow, task_id, run_number)
    FileUtils.mkdir_p(output_dir)

    branch = git("branch", "--show-current").strip
    initial_commit = git("rev-parse", "HEAD").strip
    initial_status = git("status", "--porcelain")
    raise BenchmarkError, "Working tree must be clean before a measured run." unless initial_status.empty?

    events_path = output_dir.join("events.jsonl")
    stderr_path = output_dir.join("stderr.log")
    final_message_path = output_dir.join("final_message.txt")

    prompt = build_prompt(task_path)
    command = codex_command(prompt, final_message_path, image_path)

    started_wall = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    started_at = Time.now.utc
    exit_code = execute_codex(command, events_path, stderr_path)
    ended_at = Time.now.utc
    wall_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_wall

    exec_metrics = parse_exec_events(events_path)
    root_thread_id = exec_metrics["root_thread_id"]
    raise BenchmarkError, "Codex JSONL did not contain a thread.started event." unless root_thread_id

    threads = collect_thread_metrics(root_thread_id)
    usage = aggregate_usage(threads)
    cost = usage_breakdown(usage)

    final_commit = git("rev-parse", "HEAD").strip
    diff_stats = git_diff_stats(initial_commit)
    git_diff = git("diff", initial_commit)
    git_status = git("status", "--short")

    output_dir.join("git.diff").write(git_diff)
    output_dir.join("git_status.txt").write(git_status)

    compliance = threads.all? do |thread|
      thread["model"] == MODEL && thread["reasoning_effort"] == REASONING_EFFORT
    end

    result = {
      "workflow" => workflow,
      "task_id" => task_id,
      "run" => run_number,
      "task_path" => relative_to_repo(task_path),
      "image_path" => image_path && relative_to_repo(image_path),
      "branch" => branch,
      "initial_commit" => initial_commit,
      "final_commit" => final_commit,
      "codex_version" => codex_version,
      "codex_config_sha256" => codex_config_sha256,
      "model" => MODEL,
      "reasoning_effort" => REASONING_EFFORT,
      "model_policy_compliant" => compliance,
      "root_thread_id" => root_thread_id,
      "thread_count" => threads.length,
      "threads" => threads,
      "usage" => usage,
      "cost" => cost.merge("pricing_reference_date" => PRICING_REFERENCE_DATE),
      "wall_time_seconds" => wall_time.round(3),
      "started_at" => started_at.iso8601(6),
      "ended_at" => ended_at.iso8601(6),
      "exit_code" => exit_code,
      "human_interventions" => @options.fetch(:human_interventions),
      "git" => diff_stats,
      "exec_events" => exec_metrics
    }

    result_path = output_dir.join("result.json")
    result_path.write(JSON.pretty_generate(result))

    unless @options[:no_langfuse]
      begin
        trace_id = send_to_langfuse(result, task_path.read, started_at, ended_at)
        result["langfuse"] = { "status" => "sent", "trace_id" => trace_id }
      rescue StandardError => e
        result["langfuse"] = { "status" => "error", "error" => "#{e.class}: #{e.message}" }
        warn "Langfuse ingestion failed: #{e.class}: #{e.message}"
      ensure
        result_path.write(JSON.pretty_generate(result))
      end
    end

    print_summary(result, output_dir)
    exit_code
  end

  private

  def validate_inputs!
    raise BenchmarkError, "--task is required." unless @options[:task]
    raise BenchmarkError, "--workflow is required." if @options[:workflow].to_s.empty?
    raise BenchmarkError, "--run must be >= 1." unless @options[:run].to_i >= 1
  end

  def validate_repository_state!
    branch = git("branch", "--show-current").strip
    raise BenchmarkError, "Detached HEAD is not allowed for measured runs." if branch.empty?
    if PROTECTED_BRANCHES.include?(branch)
      raise BenchmarkError, "Do not run measured tasks on protected branch #{branch.inspect}. Create or switch to the benchmark configuration branch first."
    end
  end

  def absolute_repo_path(value)
    path = Pathname.new(value)
    path = @repo_root.join(path) unless path.absolute?
    path = path.expand_path
    unless path.to_s == @repo_root.to_s || path.to_s.start_with?(@repo_root.to_s + File::SEPARATOR)
      raise BenchmarkError, "Path must stay inside the benchmark repository: #{value}"
    end
    raise BenchmarkError, "File not found: #{path}" unless path.file?
    path
  end

  def relative_to_repo(path)
    path.relative_path_from(@repo_root).to_s
  end

  def infer_task_id(task_path)
    match = task_path.basename.to_s.match(/\A(\d{2})-/)
    raise BenchmarkError, "Task filename must begin with a two-digit id, e.g. 01-..." unless match
    match[1]
  end

  def build_output_dir(workflow, task_id, run_number)
    configured = ENV.fetch("BENCHMARK_RUNS_ROOT", "../agent_benchmark_runs")
    root = Pathname.new(configured)
    root = @repo_root.join(root) unless root.absolute?
    root.expand_path.join(workflow, "task_#{task_id}", format("run_%02d", run_number))
  end

  def build_prompt(task_path)
    relative_task = relative_to_repo(task_path)
    "$software-development-workflow Execute the benchmark task defined in #{relative_task}. Complete the entire workflow autonomously."
  end

  def codex_command(prompt, final_message_path, image_path)
    command = [
      "codex", "exec",
      "--json",
      "--model", MODEL,
      "--config", "model_reasoning_effort=\"#{REASONING_EFFORT}\"",
      "--dangerously-bypass-approvals-and-sandbox",
      "--output-last-message", final_message_path.to_s
    ]
    command.concat(["--image", image_path.to_s]) if image_path
    command << prompt
    command
  end

  def execute_codex(command, events_path, stderr_path)
    File.open(events_path, "w") do |events|
      File.open(stderr_path, "w") do |stderr_file|
        Open3.popen3(*command, chdir: @repo_root.to_s) do |stdin, stdout, stderr, wait_thread|
          stdin.close
          stderr_reader = Thread.new do
            stderr.each_line do |line|
              stderr_file.write(line)
              stderr_file.flush
              warn line.rstrip
            end
          end

          stdout.each_line do |line|
            events.write(line)
            events.flush
          end

          stderr_reader.join
          return wait_thread.value.exitstatus
        end
      end
    end
  rescue Errno::ENOENT => e
    raise BenchmarkError, "Unable to start Codex CLI: #{e.message}"
  end

  def parse_exec_events(path)
    root_thread_id = nil
    root_turn_usage = nil
    event_count = 0
    invalid_json_lines = 0

    path.each_line do |line|
      next if line.strip.empty?

      begin
        event = JSON.parse(line)
      rescue JSON::ParserError
        invalid_json_lines += 1
        next
      end

      event_count += 1
      case event["type"]
      when "thread.started"
        root_thread_id = event["thread_id"] if event["thread_id"].is_a?(String)
      when "turn.completed"
        root_turn_usage = normalize_usage(event["usage"]) if event["usage"].is_a?(Hash)
      end
    end

    {
      "root_thread_id" => root_thread_id,
      "root_turn_usage" => root_turn_usage,
      "event_count" => event_count,
      "invalid_json_lines" => invalid_json_lines
    }
  end

  def collect_thread_metrics(root_thread_id)
    index = index_rollouts
    thread_ids = rollout_tree(index, root_thread_id)
    raise BenchmarkError, "Root Codex rollout #{root_thread_id} was not found under CODEX_HOME." if thread_ids.empty?

    thread_ids.map do |thread_id|
      record = index.fetch(thread_id)
      extract_thread_metrics(record.fetch("path"), record.fetch("meta"))
    end
  end

  def index_rollouts
    sessions_root = codex_home.join("sessions")
    return {} unless sessions_root.directory?

    Dir.glob(sessions_root.join("**", "rollout-*.jsonl").to_s).each_with_object({}) do |raw_path, indexed|
      path = Pathname.new(raw_path)
      meta = first_session_meta(path)
      next unless meta

      thread_id = meta["id"]
      next unless thread_id.is_a?(String) && !thread_id.empty?

      indexed[thread_id] = {
        "path" => path,
        "meta" => meta,
        "parent_thread_id" => nested_parent_thread_id(meta)
      }
    end
  end

  def first_session_meta(path)
    File.foreach(path).first(30).each do |line|
      event = JSON.parse(line) rescue nil
      next unless event.is_a?(Hash) && event["type"] == "session_meta"

      payload = event["payload"]
      payload = payload["meta"] if payload.is_a?(Hash) && payload["meta"].is_a?(Hash)
      return payload if payload.is_a?(Hash)
    end
    nil
  rescue Errno::ENOENT, Errno::EACCES
    nil
  end

  def nested_parent_thread_id(meta)
    direct = meta["parent_thread_id"]
    return direct if direct.is_a?(String) && !direct.empty?

    source = meta["source"]
    return nil unless source.is_a?(Hash)
    subagent = source["subagent"]
    return nil unless subagent.is_a?(Hash)
    thread_spawn = subagent["thread_spawn"]
    return nil unless thread_spawn.is_a?(Hash)
    parent = thread_spawn["parent_thread_id"]
    parent if parent.is_a?(String) && !parent.empty?
  end

  def rollout_tree(indexed, root_thread_id)
    return [] unless indexed.key?(root_thread_id)

    selected = { root_thread_id => true }
    loop do
      changed = false
      indexed.each do |thread_id, record|
        next if selected.key?(thread_id)
        next unless selected.key?(record["parent_thread_id"])

        selected[thread_id] = true
        changed = true
      end
      break unless changed
    end
    selected.keys.sort_by { |id| [id == root_thread_id ? 0 : 1, id] }
  end

  def extract_thread_metrics(path, meta)
    started_at = parse_time(meta["timestamp"])
    latest_event_at = started_at
    latest_context_at = nil
    latest_context = {}
    latest_usage_at = nil
    latest_usage = normalize_usage({})
    token_count_events = 0

    File.foreach(path) do |line|
      event = JSON.parse(line) rescue nil
      next unless event.is_a?(Hash)

      event_time = parse_time(event["timestamp"])
      next if started_at && event_time && event_time < started_at
      latest_event_at = event_time if event_time && (!latest_event_at || event_time > latest_event_at)

      payload = event["payload"]
      if event["type"] == "turn_context" && payload.is_a?(Hash)
        if latest_context_at.nil? || event_time.nil? || event_time >= latest_context_at
          latest_context = payload
          latest_context_at = event_time || latest_context_at
        end
      end

      next unless event["type"] == "event_msg" && payload.is_a?(Hash)
      next unless payload["type"] == "token_count"

      info = payload["info"]
      usage = info.is_a?(Hash) ? info["total_token_usage"] : nil
      next unless usage.is_a?(Hash)

      token_count_events += 1
      next if latest_usage_at && event_time && event_time < latest_usage_at

      latest_usage = normalize_usage(usage)
      latest_usage_at = event_time || latest_usage_at
    end

    {
      "thread_id" => meta["id"],
      "parent_thread_id" => nested_parent_thread_id(meta),
      "agent_path" => meta["agent_path"],
      "agent_role" => meta["agent_role"],
      "agent_nickname" => meta["agent_nickname"],
      "thread_source" => meta["thread_source"],
      "source" => meta["source"],
      "rollout_path" => path.to_s,
      "started_at" => started_at&.iso8601(6) || meta["timestamp"],
      "ended_at" => latest_event_at&.iso8601(6),
      "model" => latest_context["model"],
      "reasoning_effort" => latest_context["effort"] || latest_context["model_reasoning_effort"],
      "approval_policy" => latest_context["approval_policy"],
      "sandbox_policy" => latest_context["sandbox_policy"],
      "token_count_events" => token_count_events,
      "usage" => latest_usage
    }
  rescue Errno::ENOENT, Errno::EACCES => e
    raise BenchmarkError, "Unable to read Codex rollout #{path}: #{e.message}"
  end

  def normalize_usage(usage)
    USAGE_FIELDS.to_h { |field| [field, Integer(usage[field] || 0)] }
  rescue ArgumentError, TypeError
    USAGE_FIELDS.to_h { |field| [field, 0] }
  end

  def aggregate_usage(threads)
    total = normalize_usage({})
    threads.each do |thread|
      USAGE_FIELDS.each { |field| total[field] += thread.fetch("usage").fetch(field, 0).to_i }
    end
    total
  end

  def usage_breakdown(usage)
    input_tokens = usage.fetch("input_tokens", 0).to_i
    cached_input_tokens = [[usage.fetch("cached_input_tokens", 0).to_i, 0].max, input_tokens].min
    uncached_input_tokens = [input_tokens - cached_input_tokens, 0].max
    output_tokens = [usage.fetch("output_tokens", 0).to_i, 0].max

    credits = (
      uncached_input_tokens * CODEX_CREDITS_PER_MTOK.fetch("input") +
      cached_input_tokens * CODEX_CREDITS_PER_MTOK.fetch("cached_input") +
      output_tokens * CODEX_CREDITS_PER_MTOK.fetch("output")
    ) / 1_000_000.0

    api_usd = (
      uncached_input_tokens * API_USD_PER_MTOK.fetch("input") +
      cached_input_tokens * API_USD_PER_MTOK.fetch("cached_input") +
      output_tokens * API_USD_PER_MTOK.fetch("output")
    ) / 1_000_000.0

    {
      "uncached_input_tokens" => uncached_input_tokens,
      "cached_input_tokens" => cached_input_tokens,
      "output_tokens" => output_tokens,
      "estimated_codex_credits" => credits.round(6),
      "api_equivalent_cost_usd_base_rate" => api_usd.round(6)
    }
  end

  def git_diff_stats(initial_commit)
    files_changed = 0
    lines_added = 0
    lines_deleted = 0

    git("diff", "--numstat", initial_commit).each_line do |line|
      added, deleted, path = line.chomp.split("\t", 3)
      next unless path

      files_changed += 1
      lines_added += added.to_i if added.match?(/\A\d+\z/)
      lines_deleted += deleted.to_i if deleted.match?(/\A\d+\z/)
    end

    untracked = git("ls-files", "--others", "--exclude-standard").lines.count { |line| !line.strip.empty? }

    {
      "tracked_files_changed" => files_changed,
      "untracked_files" => untracked,
      "lines_added" => lines_added,
      "lines_deleted" => lines_deleted
    }
  end

  def codex_version
    stdout, stderr, status = Open3.capture3("codex", "--version")
    status.success? ? stdout.strip : "unknown (#{stderr.strip})"
  rescue Errno::ENOENT
    "unavailable"
  end

  def codex_home
    Pathname.new(ENV.fetch("CODEX_HOME", File.expand_path("~/.codex"))).expand_path
  end

  def codex_config_sha256
    path = codex_home.join("config.toml")
    path.file? ? Digest::SHA256.file(path).hexdigest : nil
  end

  def git(*args)
    stdout, stderr, status = Open3.capture3("git", *args, chdir: @repo_root.to_s)
    raise BenchmarkError, "git #{args.join(' ')} failed: #{stderr.strip}" unless status.success?
    stdout
  end

  def parse_time(value)
    return nil unless value.is_a?(String) && !value.empty?
    Time.iso8601(value).utc
  rescue ArgumentError
    nil
  end

  def load_env_file(path)
    return unless path.file?

    path.each_line do |raw_line|
      line = raw_line.strip
      next if line.empty? || line.start_with?("#") || !line.include?("=")

      key, value = line.split("=", 2).map(&:strip)
      if value.length >= 2 && ((value.start_with?("\"") && value.end_with?("\"")) || (value.start_with?("'") && value.end_with?("'")))
        value = value[1...-1]
      end
      ENV[key] ||= value
    end
  end

  def validate_langfuse_env!
    required = %w[LANGFUSE_PUBLIC_KEY LANGFUSE_SECRET_KEY LANGFUSE_BASE_URL]
    missing = required.reject { |key| ENV[key] && !ENV[key].empty? }
    return if missing.empty?

    raise BenchmarkError, "Missing Langfuse configuration: #{missing.join(', ')}. Copy benchmark/harness/.env.example to benchmark/harness/.env and fill it locally."
  end

  def check_langfuse!
    validate_langfuse_env!
    now = Time.now.utc
    trace_id = SecureRandom.hex(16)
    span = otlp_span(
      trace_id: trace_id,
      span_id: SecureRandom.hex(8),
      parent_span_id: nil,
      name: "benchmark-harness-canary",
      started_at: now,
      ended_at: now + 0.001,
      attributes: {
        "langfuse.trace.name" => "benchmark-harness-canary",
        "langfuse.observation.type" => "span",
        "langfuse.observation.input" => JSON.generate({ "check" => "Ruby harness connectivity" }),
        "langfuse.observation.output" => JSON.generate({ "status" => "ok" }),
        "langfuse.trace.tags" => ["benchmark", "canary", "ruby"],
        "langfuse.trace.metadata.runtime" => "ruby",
        "langfuse.environment" => "local"
      },
      success: true
    )
    post_otlp([span])
    puts "Langfuse connection OK. Canary trace id: #{trace_id}"
  end

  def send_to_langfuse(result, task_text, started_at, ended_at)
    trace_id = SecureRandom.hex(16)
    root_span_id = SecureRandom.hex(8)
    span_ids = result.fetch("threads").to_h { |thread| [thread.fetch("thread_id"), SecureRandom.hex(8)] }

    common_trace_attributes = {
      "langfuse.trace.name" => "#{result['workflow']}/task_#{result['task_id']}/run_#{format('%02d', result['run'])}",
      "langfuse.trace.tags" => ["benchmark", result["workflow"], "task-#{result['task_id']}", "ruby-harness"],
      "langfuse.trace.metadata.workflow" => result["workflow"],
      "langfuse.trace.metadata.task_id" => result["task_id"],
      "langfuse.trace.metadata.run" => result["run"].to_s,
      "langfuse.trace.metadata.model" => result["model"],
      "langfuse.trace.metadata.reasoning_effort" => result["reasoning_effort"],
      "langfuse.trace.metadata.branch" => result["branch"],
      "langfuse.trace.metadata.initial_commit" => result["initial_commit"],
      "langfuse.environment" => "local",
      "langfuse.version" => result["initial_commit"]
    }

    root_span = otlp_span(
      trace_id: trace_id,
      span_id: root_span_id,
      parent_span_id: nil,
      name: common_trace_attributes.fetch("langfuse.trace.name"),
      started_at: started_at,
      ended_at: ended_at,
      attributes: common_trace_attributes.merge(
        "langfuse.observation.type" => "span",
        "langfuse.observation.input" => JSON.generate({ "task" => task_text }),
        "langfuse.observation.output" => JSON.generate({
          "exit_code" => result["exit_code"],
          "wall_time_seconds" => result["wall_time_seconds"],
          "thread_count" => result["thread_count"],
          "model_policy_compliant" => result["model_policy_compliant"],
          "estimated_codex_credits" => result.dig("cost", "estimated_codex_credits"),
          "api_equivalent_cost_usd_base_rate" => result.dig("cost", "api_equivalent_cost_usd_base_rate")
        }),
        "langfuse.observation.metadata.human_interventions" => result["human_interventions"].to_s,
        "langfuse.observation.metadata.codex_version" => result["codex_version"].to_s
      ),
      success: result["exit_code"].zero?
    )

    child_spans = result.fetch("threads").map.with_index(1) do |thread, index|
      parent_thread_id = thread["parent_thread_id"]
      parent_span_id = parent_thread_id && span_ids[parent_thread_id] ? span_ids.fetch(parent_thread_id) : root_span_id
      breakdown = usage_breakdown(thread.fetch("usage"))
      role = thread["agent_role"] || thread["agent_path"] || (thread["thread_id"] == result["root_thread_id"] ? "orchestrator" : "subagent")
      thread_started = parse_time(thread["started_at"]) || started_at
      thread_ended = parse_time(thread["ended_at"]) || ended_at
      thread_ended = thread_started if thread_ended < thread_started

      otlp_span(
        trace_id: trace_id,
        span_id: span_ids.fetch(thread.fetch("thread_id")),
        parent_span_id: parent_span_id,
        name: format("%02d-%s", index, role),
        started_at: thread_started,
        ended_at: thread_ended,
        attributes: common_trace_attributes.merge(
          "langfuse.observation.type" => "generation",
          "langfuse.observation.model.name" => thread["model"] || result["model"],
          "langfuse.observation.model.parameters" => JSON.generate({ "reasoning_effort" => thread["reasoning_effort"] }),
          "langfuse.observation.usage_details" => JSON.generate({
            "input" => breakdown["uncached_input_tokens"],
            "input_cached_tokens" => breakdown["cached_input_tokens"],
            "output" => breakdown["output_tokens"]
          }),
          "langfuse.observation.cost_details" => JSON.generate({
            "input" => breakdown["uncached_input_tokens"] * API_USD_PER_MTOK.fetch("input") / 1_000_000.0,
            "input_cached_tokens" => breakdown["cached_input_tokens"] * API_USD_PER_MTOK.fetch("cached_input") / 1_000_000.0,
            "output" => breakdown["output_tokens"] * API_USD_PER_MTOK.fetch("output") / 1_000_000.0
          }),
          "langfuse.observation.metadata.thread_id" => thread["thread_id"].to_s,
          "langfuse.observation.metadata.parent_thread_id" => thread["parent_thread_id"].to_s,
          "langfuse.observation.metadata.agent_role" => role.to_s,
          "langfuse.observation.metadata.reasoning_output_tokens" => thread.dig("usage", "reasoning_output_tokens").to_s,
          "langfuse.observation.metadata.cache_write_input_tokens" => thread.dig("usage", "cache_write_input_tokens").to_s,
          "langfuse.observation.metadata.estimated_codex_credits" => breakdown["estimated_codex_credits"].to_s
        ),
        success: true
      )
    end

    post_otlp([root_span] + child_spans)
    trace_id
  end

  def otlp_span(trace_id:, span_id:, parent_span_id:, name:, started_at:, ended_at:, attributes:, success:)
    span = {
      "traceId" => trace_id,
      "spanId" => span_id,
      "flags" => 1,
      "name" => name,
      "kind" => 1,
      "startTimeUnixNano" => unix_nanos(started_at),
      "endTimeUnixNano" => unix_nanos(ended_at),
      "attributes" => attributes.map { |key, value| otlp_attribute(key, value) },
      "status" => { "code" => success ? 1 : 2 }
    }
    span["parentSpanId"] = parent_span_id if parent_span_id
    span
  end

  def otlp_attribute(key, value)
    encoded = case value
              when Array
                { "arrayValue" => { "values" => value.map { |item| { "stringValue" => item.to_s } } }
              when TrueClass, FalseClass
                { "boolValue" => value }
              when Integer
                { "intValue" => value.to_s }
              when Float
                { "doubleValue" => value }
              else
                { "stringValue" => value.to_s }
              end
    { "key" => key, "value" => encoded }
  end

  def unix_nanos(time)
    (time.to_r * 1_000_000_000).to_i.to_s
  end

  def post_otlp(spans)
    base_url = ENV.fetch("LANGFUSE_BASE_URL").sub(%r{/+\z}, "")
    uri = URI("#{base_url}/api/public/otel/v1/traces")
    auth = Base64.strict_encode64("#{ENV.fetch('LANGFUSE_PUBLIC_KEY')}:#{ENV.fetch('LANGFUSE_SECRET_KEY')}")

    payload = {
      "resourceSpans" => [
        {
          "resource" => {
            "attributes" => [
              otlp_attribute("service.name", "agent-benchmark-harness"),
              otlp_attribute("service.version", "ruby")
            ]
          },
          "scopeSpans" => [
            {
              "scope" => { "name" => "agent-benchmark-harness", "version" => "1" },
              "spans" => spans
            }
          ]
        }
      ]
    }

    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Basic #{auth}"
    request["Content-Type"] = "application/json"
    request["x-langfuse-ingestion-version"] = "4"
    request.body = JSON.generate(payload)

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 15) do |http|
      http.request(request)
    end

    return response if response.is_a?(Net::HTTPSuccess)

    raise BenchmarkError, "Langfuse OTLP ingestion returned HTTP #{response.code}: #{response.body.to_s[0, 500]}"
  end

  def print_summary(result, output_dir)
    puts
    puts "Benchmark run complete"
    puts "  workflow: #{result['workflow']}"
    puts "  task: #{result['task_id']}"
    puts "  run: #{result['run']}"
    puts "  exit_code: #{result['exit_code']}"
    puts "  wall_time_seconds: #{result['wall_time_seconds']}"
    puts "  threads: #{result['thread_count']}"
    puts "  input_tokens: #{result.dig('usage', 'input_tokens')}"
    puts "  cached_input_tokens: #{result.dig('usage', 'cached_input_tokens')}"
    puts "  output_tokens: #{result.dig('usage', 'output_tokens')}"
    puts "  estimated_codex_credits: #{result.dig('cost', 'estimated_codex_credits')}"
    puts "  api_equivalent_usd: #{result.dig('cost', 'api_equivalent_cost_usd_base_rate')}"
    puts "  model_policy_compliant: #{result['model_policy_compliant']}"
    puts "  artifacts: #{output_dir}"
    puts "  langfuse: #{result.dig('langfuse', 'status')}" if result["langfuse"]
  end
end

options = {
  workflow: "baseline",
  run: 1,
  human_interventions: 0,
  no_langfuse: false,
  check_langfuse: false
}

parser = OptionParser.new do |opts|
  opts.banner = "Usage: ruby benchmark/harness/run_benchmark.rb --task TASK [options]"
  opts.on("--task PATH", "Benchmark task markdown file") { |value| options[:task] = value }
  opts.on("--image PATH", "Optional image attached to the initial Codex prompt") { |value| options[:image] = value }
  opts.on("--workflow NAME", "Workflow/experiment name (default: baseline)") { |value| options[:workflow] = value }
  opts.on("--run N", Integer, "Run number (default: 1)") { |value| options[:run] = value }
  opts.on("--human-interventions N", Integer, "Manual interventions during measured run (default: 0)") { |value| options[:human_interventions] = value }
  opts.on("--no-langfuse", "Keep artifacts locally without sending OTLP traces") { options[:no_langfuse] = true }
  opts.on("--check-langfuse", "Send a canary trace to Langfuse without running Codex") { options[:check_langfuse] = true }
  opts.on("-h", "--help", "Show this help") do
    puts opts
    exit 0
  end
end

begin
  parser.parse!
  exit BenchmarkRunner.new(options).run
rescue BenchmarkError, OptionParser::ParseError => e
  warn "ERROR: #{e.message}"
  exit 1
rescue Interrupt
  warn "Interrupted."
  exit 130
end
