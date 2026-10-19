#!/usr/bin/env node
// Records what a role call cost, measured from the subagent's own transcript.
//
// A SubagentStop hook for Claude Code. Copy it into the product repository (e.g.
// scripts/cost-capture.mjs, versioned) and register it in the shared .claude/settings.json:
//
//   "hooks": {
//     "SubagentStop": [
//       { "hooks": [ { "type": "command",
//                      "command": "node \"$CLAUDE_PROJECT_DIR/scripts/cost-capture.mjs\"" } ] }
//     ]
//   }
//
// Why not the Agent tool's result: its `totalTokens` and `usage` cover the subagent's final API
// request only, and a background call (the default) returns at launch with no usage at all. The
// subagent's transcript has every request, so this hook sums them, once per message id: one
// request is written as several entries that repeat the same usage.
//
// When a subagent stops while a task is running in the repository (a worktree of it has a .task/
// directory; see task-command.md, "Task journal and hand-offs"), the hook writes
// <git common dir>/cost-capture/<agent id>.json: agent id and type, model, start and end, seconds,
// tool calls, requests, and tokens with their split. The common dir is the one every worktree
// shares, so the record is found whether the session runs in the task's worktree or in the main
// checkout, and git never tracks it. The transcript format is not documented, so every record
// says where its tokens came from (`tokensSource`). A transcript it can't read gives
// `"tokens": "no data"` and the reason, never a guess. With no task running it writes nothing.
//
// It always exits 0 as a hook: a broken cost record must never stop a role. The task command
// notices a missing record instead.
//
//   cost-capture.mjs                                  # as the hook: reads the event from stdin
//   cost-capture.mjs --transcript <path> [--type <t>] # prints the record for one transcript
//   cost-capture.mjs --self-test                      # built-in cases

import { readFileSync, writeFileSync, mkdirSync, existsSync, statSync, mkdtempSync, rmSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { tmpdir } from "node:os";
import { join, dirname, basename } from "node:path";

const TOOL = "cost-capture";

function measure(transcriptPath, agentId, agentType) {
  const record = { agentId, agentType: agentType || null };
  let text;
  try {
    text = readFileSync(transcriptPath, "utf8");
  } catch (error) {
    return { ...record, tokens: "no data", tokensSource: `no data: transcript not readable (${error.code ?? error.message})` };
  }

  const usageById = new Map();
  const toolUses = new Set();
  const models = new Set();
  let first = null, last = null, skipped = 0, version = null;
  for (const line of text.split("\n")) {
    if (!line.trim()) continue;
    let entry;
    try {
      entry = JSON.parse(line);
    } catch {
      skipped++;
      continue;
    }
    if (entry.timestamp) {
      first ??= entry.timestamp;
      last = entry.timestamp;
    }
    version ??= entry.version ?? null;
    if (entry.type !== "assistant" || !entry.message) continue;
    const { id, usage, model, content } = entry.message;
    if (id && usage) usageById.set(id, usage);
    if (model) models.add(model);
    for (const block of Array.isArray(content) ? content : []) if (block?.type === "tool_use") toolUses.add(block.id);
  }

  const split = { input: 0, output: 0, cacheWrite: 0, cacheRead: 0 };
  for (const u of usageById.values()) {
    split.input += u.input_tokens ?? 0;
    split.output += u.output_tokens ?? 0;
    split.cacheWrite += u.cache_creation_input_tokens ?? 0;
    split.cacheRead += u.cache_read_input_tokens ?? 0;
  }
  const seconds = first && last ? Math.round((Date.parse(last) - Date.parse(first)) / 1000) : "no data";
  const model = models.size === 0 ? "no data" : models.size === 1 ? [...models][0] : `mixed: ${[...models].join(", ")}`;

  return {
    ...record,
    model,
    startedAt: first,
    endedAt: last,
    seconds,
    toolCalls: toolUses.size,
    requests: usageById.size,
    tokens: usageById.size === 0 ? "no data" : split.input + split.output + split.cacheWrite + split.cacheRead,
    tokenSplit: split,
    tokensSource: usageById.size === 0 ? "no data: no assistant request with usage in the transcript" : "transcript",
    skippedLines: skipped,
    claudeCodeVersion: version,
  };
}

// The documented field first; the path it points to otherwise sits next to the main transcript.
function transcriptFor(event) {
  if (event.agent_transcript_path) return event.agent_transcript_path;
  if (!event.transcript_path || !event.agent_id) return null;
  const session = basename(event.transcript_path).replace(/\.jsonl$/, "");
  return join(dirname(event.transcript_path), session, "subagents", `agent-${event.agent_id}.jsonl`);
}

function git(cwd, args) {
  return execFileSync("git", ["-C", cwd, ...args], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] });
}

function costDir(cwd) {
  let common, worktrees;
  try {
    common = git(cwd, ["rev-parse", "--path-format=absolute", "--git-common-dir"]).trim();
    worktrees = git(cwd, ["worktree", "list", "--porcelain"]).split("\n")
      .filter((l) => l.startsWith("worktree ")).map((l) => l.slice("worktree ".length).trim());
  } catch {
    return null;
  }
  const running = worktrees.some((w) => {
    const dir = join(w, ".task");
    return existsSync(dir) && statSync(dir).isDirectory();
  });
  return running ? join(common, "cost-capture") : null;
}

function hook(input) {
  let event;
  try {
    event = JSON.parse(input);
  } catch {
    return;
  }
  if (!event?.agent_id || !/^[A-Za-z0-9_-]+$/.test(event.agent_id)) return;
  const dir = costDir(event.cwd || process.cwd());
  if (!dir) return;
  const path = transcriptFor(event);
  const record = path
    ? measure(path, event.agent_id, event.agent_type)
    : { agentId: event.agent_id, agentType: event.agent_type || null, tokens: "no data", tokensSource: "no data: the event names no transcript" };
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, `${event.agent_id}.json`), JSON.stringify(record, null, 2) + "\n");
}

// ---------------------------------------------------------------------------- self-test

function assistant(id, usage, { model = "model-a", ts, tools = [] } = {}) {
  return JSON.stringify({
    type: "assistant", timestamp: ts, version: "9.9.9",
    message: { id, model, usage, content: tools.map((t) => ({ type: "tool_use", id: t })) },
  });
}
const U = (i, o, cw, cr) => ({ input_tokens: i, output_tokens: o, cache_creation_input_tokens: cw, cache_read_input_tokens: cr });

// task: "main" puts .task/ in the main checkout, "worktree" in a linked worktree at <root>/wt.
function withRepo(run, { task = "main" } = {}) {
  const root = mkdtempSync(join(tmpdir(), "cost-capture-self-test-"));
  try {
    const repo = join(root, "repo");
    mkdirSync(repo);
    execFileSync("git", ["init", "-q", repo], { stdio: "ignore" });
    if (task === "main") mkdirSync(join(repo, ".task"));
    if (task === "worktree") {
      for (const args of [["config", "user.email", "t@t"], ["config", "user.name", "t"], ["commit", "-q", "--allow-empty", "-m", "base"], ["worktree", "add", "-q", join(root, "wt"), "-b", "task"]])
        execFileSync("git", ["-C", repo, ...args], { stdio: "ignore" });
      mkdirSync(join(root, "wt", ".task"));
    }
    mkdirSync(join(root, "proj", "sess", "subagents"), { recursive: true });
    return run(root);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

function runHook(event) {
  execFileSync(process.execPath, [process.argv[1]], { input: typeof event === "string" ? event : JSON.stringify(event), stdio: ["pipe", "ignore", "ignore"] });
}

const RUN = [
  JSON.stringify({ type: "user", timestamp: "2026-10-19T10:00:00.000Z", version: "9.9.9" }),
  assistant("m1", U(10, 100, 1000, 0), { ts: "2026-10-19T10:00:05.000Z", tools: ["t1"] }),
  assistant("m1", U(10, 100, 1000, 0), { ts: "2026-10-19T10:00:05.100Z", tools: ["t1"] }),
  assistant("m2", U(2, 50, 200, 1000), { ts: "2026-10-19T10:01:00.000Z", tools: ["t2", "t3"] }),
  JSON.stringify({ type: "user", timestamp: "2026-10-19T10:01:30.000Z" }),
].join("\n") + "\n";

const SELF_TEST_CASES = [
  {
    name: "a finished call: tokens summed over every request, split kept",
    run: () => {
      const r = withRepo((root) => {
        const t = join(root, "t.jsonl");
        writeFileSync(t, RUN);
        return measure(t, "a1", "qa");
      });
      return r.tokens === 2362 && r.tokenSplit.cacheRead === 1000 && r.tokenSplit.output === 150 && r.requests === 2 &&
        r.toolCalls === 3 && r.seconds === 90 && r.model === "model-a" && r.tokensSource === "transcript" && r.claudeCodeVersion === "9.9.9"
        ? null : `got ${JSON.stringify(r)}`;
    },
  },
  {
    name: "entries repeating one message id count once",
    run: () => withRepo((root) => {
      const t = join(root, "t.jsonl");
      writeFileSync(t, [1, 2, 3].map((n) => assistant("same", U(1, 1, 1, 1), { ts: `2026-10-19T10:00:0${n}.000Z` })).join("\n"));
      const r = measure(t, "a1");
      return r.tokens === 4 && r.requests === 1 ? null : `got ${JSON.stringify(r)}`;
    }),
  },
  {
    name: "a missing transcript gives no data and the reason, not a number",
    run: () => withRepo((root) => {
      const r = measure(join(root, "nope.jsonl"), "a1");
      return r.tokens === "no data" && r.tokensSource.startsWith("no data: transcript not readable") ? null : `got ${JSON.stringify(r)}`;
    }),
  },
  {
    name: "a broken line is skipped and counted, the rest still summed",
    run: () => withRepo((root) => {
      const t = join(root, "t.jsonl");
      writeFileSync(t, RUN + "{not json\n");
      const r = measure(t, "a1");
      return r.tokens === 2362 && r.skippedLines === 1 ? null : `got ${JSON.stringify(r)}`;
    }),
  },
  {
    name: "a transcript with no usage gives no data",
    run: () => withRepo((root) => {
      const t = join(root, "t.jsonl");
      writeFileSync(t, JSON.stringify({ type: "user", timestamp: "2026-10-19T10:00:00.000Z" }) + "\n");
      const r = measure(t, "a1");
      return r.tokens === "no data" && r.tokensSource.startsWith("no data") ? null : `got ${JSON.stringify(r)}`;
    }),
  },
  {
    name: "two models in one run are both named",
    run: () => withRepo((root) => {
      const t = join(root, "t.jsonl");
      writeFileSync(t, [assistant("m1", U(1, 1, 1, 1), { model: "model-a" }), assistant("m2", U(1, 1, 1, 1), { model: "model-b" })].join("\n"));
      const r = measure(t, "a1");
      return r.model === "mixed: model-a, model-b" ? null : `got ${r.model}`;
    }),
  },
  {
    name: "the hook writes <common dir>/cost-capture/<agent id>.json while a task runs",
    run: () => withRepo((root) => {
      const t = join(root, "proj", "sess", "subagents", "agent-a1.jsonl");
      writeFileSync(t, RUN);
      runHook({ hook_event_name: "SubagentStop", agent_id: "a1", agent_type: "qa", agent_transcript_path: t, cwd: join(root, "repo") });
      const f = join(root, "repo", ".git", "cost-capture", "a1.json");
      if (!existsSync(f)) return "no record written";
      const r = JSON.parse(readFileSync(f, "utf8"));
      return r.tokens === 2362 && r.agentType === "qa" ? null : `got ${JSON.stringify(r)}`;
    }),
  },
  {
    name: "a session in the main checkout finds a task running in a linked worktree",
    run: () => withRepo((root) => {
      const t = join(root, "t.jsonl");
      writeFileSync(t, RUN);
      runHook({ agent_id: "a4", agent_transcript_path: t, cwd: join(root, "repo") });
      return existsSync(join(root, "repo", ".git", "cost-capture", "a4.json")) ? null : "no record written";
    }, { task: "worktree" }),
  },
  {
    name: "without agent_transcript_path, the path next to the main transcript is used",
    run: () => withRepo((root) => {
      writeFileSync(join(root, "proj", "sess", "subagents", "agent-a2.jsonl"), RUN);
      runHook({ agent_id: "a2", transcript_path: join(root, "proj", "sess.jsonl"), cwd: join(root, "repo") });
      const f = join(root, "repo", ".git", "cost-capture", "a2.json");
      return existsSync(f) && JSON.parse(readFileSync(f, "utf8")).tokens === 2362 ? null : "no record, or the wrong tokens";
    }),
  },
  {
    name: "no task running: nothing is written",
    run: () => withRepo((root) => {
      const t = join(root, "t.jsonl");
      writeFileSync(t, RUN);
      runHook({ agent_id: "a1", agent_transcript_path: t, cwd: join(root, "repo") });
      return existsSync(join(root, "repo", ".git", "cost-capture")) ? "a record was written" : null;
    }, { task: "none" }),
  },
  {
    name: "input that isn't an event, or an unsafe agent id, still exits 0 and writes nothing",
    run: () => withRepo((root) => {
      runHook("not json");
      runHook({ agent_id: "../escape", agent_transcript_path: join(root, "t.jsonl"), cwd: join(root, "repo") });
      runHook({ agent_id: "a3", cwd: join(root, "outside-any-repo") });
      return existsSync(join(root, "repo", ".git", "cost-capture")) ? "a record was written" : null;
    }),
  },
  {
    name: "the last line states the result (exit contract)",
    run: () => {
      const out = execFileSync(process.execPath, [process.argv[1], "--self-test", "--only-summary"], { encoding: "utf8" });
      return /^Self-test: \d+ cases ran, \d+ passed, 0 failed\.$/.test(out.trim().split("\n").at(-1)) ? null : `last line '${out.trim().split("\n").at(-1)}'`;
    },
  },
];

function selfTest(onlySummary) {
  const cases = onlySummary ? SELF_TEST_CASES.slice(0, -1) : SELF_TEST_CASES;
  let failed = 0;
  for (const testCase of cases) {
    let reason;
    try {
      reason = testCase.run();
    } catch (error) {
      reason = `threw: ${error?.stack ?? error}`;
    }
    if (reason) failed++;
    if (!onlySummary) console.log(reason ? `FAIL ${testCase.name} — ${reason}` : `ok   ${testCase.name}`);
  }
  console.log(`Self-test: ${cases.length} cases ran, ${cases.length - failed} passed, ${failed} failed.`);
  return failed === 0 ? 0 : 1;
}

// ---------------------------------------------------------------------------- entry point

const args = process.argv.slice(2);
if (args[0] === "--self-test") {
  process.exit(selfTest(args.includes("--only-summary")));
} else if (args[0] === "--transcript") {
  if (!args[1]) {
    console.error(`${TOOL}: --transcript needs a path`);
    process.exit(2);
  }
  const typeAt = args.indexOf("--type");
  const id = basename(args[1]).replace(/^agent-/, "").replace(/\.jsonl$/, "");
  const record = measure(args[1], id, typeAt > 0 ? args[typeAt + 1] : null);
  if (record.tokens === "no data" && record.tokensSource.includes("not readable")) {
    console.error(`${TOOL}: ${record.tokensSource}`);
    process.exit(2);
  }
  console.log(JSON.stringify(record, null, 2));
  process.exit(0);
} else {
  try {
    hook(readFileSync(0, "utf8"));
  } catch {
    // A cost record is bookkeeping; a failure here must never stop the role or the session.
  }
  process.exit(0);
}
