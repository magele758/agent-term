// Runs @ppeng/agent-loop at the max preset. One prompt in, the reply on stdout.
// ponytail: sub-agents read files and may run a Gate-checked shell. They cannot spawn.
const core = process.env.AGENT_CORE ?? new URL('../../ppeng-agent-core/packages/agent-loop/dist/', import.meta.url).pathname;
const { createAssembledLoop, OpenAiChatAdapter } = await import(core + 'index.js');
const { createDefaultMemoryStore, DEFAULT_EMBED_AGENT } = await import(core + 'mini.js');
import { readFileSync, readdirSync, statSync, existsSync, writeFileSync, renameSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { spawn, spawnSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { fileURLToPath } from 'node:url';

const [baseUrl, model, prompt, root] = process.argv.slice(2);

const repoRoot = fileURLToPath(new URL('..', import.meta.url));

// ponytail: offline stand-in so the wiring can be checked without a provider. Never selected by the app.
class EchoModel {
  name = 'echo';
  async runTurn(input) {
    const messages = input.messages ?? [];
    const hasTool = messages.some((m) => m.role === 'tool');
    const last = [...messages].reverse().find((m) => m.role === 'user');
    const ask = last?.parts?.map((p) => p.text ?? '').join('') ?? '';
    const canSpawn = input.tools?.some((t) => t.name === 'spawn_agent');
    const willSpawn = !hasTool && canSpawn && (ask === 'parallel-sleep' || (!ask.startsWith('SUB:') && !ask.startsWith('SLEEP:')));
    process.stderr.write('KEYS ' + Object.keys(input).join(',') + '\n');
    // Name the tool once, on the dispatch turn. A later turn must not.
    if (!hasTool) {
      process.stderr.write('MSG ' + JSON.stringify(messages.slice(-2)) + (willSpawn ? ' spawn_agent' : '') + '\n');
    }
    if (hasTool) {
      return { assistantParts: [{ type: 'text', text: 'done:' + ask }], stopReason: 'end' };
    }
    if (willSpawn && ask === 'parallel-sleep') {
      return {
        assistantParts: [{
          type: 'tool_call',
          id: 'c1',
          name: 'spawn_agent',
          input: { tasks: ['SLEEP:400:a', 'SLEEP:200:b'] },
        }],
        stopReason: 'tool_use',
      };
    }
    if (willSpawn) {
      return {
        assistantParts: [{ type: 'tool_call', id: 'c1', name: 'spawn_agent', input: { task: 'SUB:' + ask } }],
        stopReason: 'tool_use',
      };
    }
    return { assistantParts: [{ type: 'text', text: 'done:' + ask }], stopReason: 'end' };
  }
}
const apiKey = process.env.AGENT_API_KEY ?? '';
const isCli = resolve(process.argv[1] ?? '') === fileURLToPath(import.meta.url);
if (isCli && (!baseUrl || !model || !prompt)) {
  console.error('usage: run.mjs <baseUrl> <model> <prompt> [root]');
  process.exit(2);
}
const dir = resolve(root || process.cwd());

const text = (s) => ({ ok: true, content: String(s).slice(0, 8000) });
const readTool = {
  name: 'read_file',
  description: 'Read a text file under the workspace',
  inputSchema: { type: 'object', properties: { path: { type: 'string' } }, required: ['path'] },
  approvalMode: 'never',
  sideEffectLevel: 'none',
  execute: async (_ctx, args) => {
    const p = resolve(dir, String(args.path ?? ''));
    if (!p.startsWith(dir)) return { ok: false, content: 'outside workspace' };
    return text(readFileSync(p, 'utf8'));
  },
};
const listTool = {
  name: 'list_dir',
  description: 'List a directory under the workspace',
  inputSchema: { type: 'object', properties: { path: { type: 'string' } } },
  approvalMode: 'never',
  sideEffectLevel: 'none',
  execute: async (_ctx, args) => {
    const p = resolve(dir, String(args.path ?? '.'));
    if (!p.startsWith(dir)) return { ok: false, content: 'outside workspace' };
    return text(readdirSync(p).map((n) => {
      const s = statSync(join(p, n));
      return `${s.isDirectory() ? 'd' : 'f'} ${n}`;
    }).join('\n'));
  },
};

function gateBin() {
  return process.env.AGENT_GATE || join(repoRoot, '.build-direct/headless/gate');
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

async function waitAsk(askLine) {
  const askDir = process.env.AGENT_ASK_DIR;
  if (!askDir) return { ok: false, content: 'ask: no approver' };
  const id = randomUUID();
  const req = join(askDir, `${id}.req`);
  try {
    writeFileSync(req + '.tmp', askLine);
    renameSync(req + '.tmp', req);
  } catch (e) {
    return { ok: false, content: String(e?.message ?? e) };
  }
  const resPath = join(askDir, `${id}.res`);
  for (;;) {
    if (existsSync(resPath)) {
      let body = '';
      try { body = readFileSync(resPath, 'utf8'); } catch { return { ok: false, content: 'denied' }; }
      if (body === 'allow') return { ok: true };
      return { ok: false, content: body === 'deny' ? 'deny' : (body || 'denied') };
    }
    await sleep(100);
  }
}

function execShell(command) {
  return new Promise((resolvePromise) => {
    const env = { ...process.env };
    for (const k of ['AGENT_API_KEY', 'AGENT_ASK_DIR', 'AGENT_GATE', 'AGENT_CORE']) delete env[k];
    const child = spawn('/bin/zsh', ['-c', command], { cwd: dir, env, detached: true, stdio: ['ignore', 'pipe', 'pipe'] });
    let out = '';
    let settled = false;
    const finish = (result) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolvePromise(result);
    };
    const take = (chunk) => { out += chunk.toString(); };
    child.stdout.on('data', take);
    child.stderr.on('data', take);
    const timer = setTimeout(() => {
      try { process.kill(-child.pid, 'SIGKILL'); } catch { child.kill('SIGKILL'); }
      const partial = out.slice(0, 7980);
      finish({ ok: false, content: `${partial}${partial ? '\n' : ''}timed out`.slice(0, 8000) });
    }, 120_000);
    child.on('error', (e) => finish({ ok: false, content: String(e?.message ?? e).slice(0, 8000) }));
    child.on('close', (code) => {
      const body = out.slice(0, 8000);
      if (code === 0) finish({ ok: true, content: body });
      else finish({ ok: false, content: body || `exit ${code}` });
    });
  });
}

async function runShell(command) {
  const bin = gateBin();
  if (!existsSync(bin)) return { ok: false, content: 'gate missing' };
  const checked = spawnSync(bin, ['check'], { input: command, encoding: 'utf8' });
  if (checked.error || checked.status !== 0) {
    const reason = `${checked.stdout ?? ''}${checked.stderr ?? ''}${checked.error?.message ?? ''}`.trim();
    return { ok: false, content: reason || 'gate failed' };
  }
  const line = String(checked.stdout ?? '').split('\n')[0] ?? '';
  if (line === 'allow') return execShell(command);
  if (line.startsWith('deny\t')) return { ok: false, content: line.slice(5) || 'deny' };
  if (line.startsWith('ask\t')) {
    const verdict = await waitAsk(line.slice(4));
    if (!verdict.ok) return verdict;
    return execShell(command);
  }
  return { ok: false, content: line || 'unparsed' };
}

const shellTool = {
  name: 'run_shell',
  description: 'Run a shell command in the workspace after Gate check. deny is refused; ask waits for approval.',
  inputSchema: { type: 'object', properties: { command: { type: 'string' } }, required: ['command'] },
  approvalMode: 'never',
  sideEffectLevel: 'none',
  execute: async (_ctx, args) => runShell(String(args.command ?? '')),
};

// A sub-agent is the same loop one level down, without the spawn tool, so it cannot fork again.
async function subagent(task) {
  if (baseUrl === 'echo') {
    const sleepMatch = String(task).match(/^SLEEP:(\d+):/);
    if (sleepMatch) {
      await sleep(Number(sleepMatch[1]));
      return 'done:' + task;
    }
  }
  const { store, surface } = createDefaultMemoryStore({ agent: DEFAULT_EMBED_AGENT });
  const session = surface.createSession({ title: 'sub', mode: 'chat', agentId: DEFAULT_EMBED_AGENT.id });
  surface.appendMessage(session.id, 'user', [{ type: 'text', text: task }]);
  const loop = await createAssembledLoop({
    preset: 'max',
    io: {
      store,
      model: baseUrl === 'echo' ? new EchoModel() : new OpenAiChatAdapter({ apiKey, baseUrl, model, useJsonMode: false }),
      tools: [readTool, listTool, shellTool],
    },
  });
  const handle = loop.createHandle(session.id);
  await handle.run();
  const fold = await handle.fold();
  const last = [...fold].reverse().find((m) => m.role === 'assistant');
  return last?.parts?.map((p) => p.text ?? '').join('') ?? '';
}

function taskList(args) {
  if (Array.isArray(args?.tasks)) return args.tasks.map((t) => String(t));
  if (args?.task != null) return [String(args.task)];
  return [];
}

const spawnTool = {
  name: 'spawn_agent',
  description: 'Hand several self-contained subtasks to sub-agents at once. They can read files, run a gated shell, and return findings in dispatch order.',
  inputSchema: {
    type: 'object',
    properties: {
      tasks: { type: 'array', items: { type: 'string' } },
      task: { type: 'string' },
    },
  },
  approvalMode: 'never',
  sideEffectLevel: 'none',
  execute: async (_ctx, args) => {
    const tasks = taskList(args);
    const bodies = await Promise.all(tasks.map((t) => subagent(t)));
    return text(bodies.map((b, i) => `#${i}\n${b}`).join('\n'));
  },
};

if (isCli) {
  const { store, surface } = createDefaultMemoryStore({ agent: DEFAULT_EMBED_AGENT });
  const session = surface.createSession({ title: 'agent', mode: 'chat', agentId: DEFAULT_EMBED_AGENT.id });
  surface.appendMessage(session.id, 'user', [{ type: 'text', text: prompt }]);
  const loop = await createAssembledLoop({
    preset: 'max',
    io: {
      store,
      model: baseUrl === 'echo' ? new EchoModel() : new OpenAiChatAdapter({ apiKey, baseUrl, model, useJsonMode: false }),
      tools: [readTool, listTool, spawnTool],
    },
  });
  process.stderr.write(`preset ${loop.preset} modules ${loop.loadedModules.length}\n`);
  const handle = loop.createHandle(session.id);
  await handle.run();
  const fold = await handle.fold();
  const last = [...fold].reverse().find((m) => m.role === 'assistant');
  const assistantText = last?.parts?.map((p) => p.text ?? '').join('') ?? '';
  process.stdout.write(assistantText + '\n');
}

export { runShell };
