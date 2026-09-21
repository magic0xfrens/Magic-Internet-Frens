#!/usr/bin/env node
// Source-backed graph extraction. AST/type checking only: no bytecode build,
// broadcasts, network, Foundry artifact/cache writes, or security verdicts.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { spawnSync } from 'node:child_process';

const [sourceArg, graphArg, reportArg, compilersArg] = process.argv.slice(2);
if (!compilersArg) throw new Error('usage: compiler_graph.mjs SOURCE GRAPH REPORT INSTALLED_SOLC_DIRECTORY');
const sourceRoot = path.resolve(sourceArg);
const graphRoot = path.resolve(graphArg);
const reportRoot = path.resolve(reportArg);
const sha = data => crypto.createHash('sha256').update(data).digest('hex');
const readJson = file => JSON.parse(fs.readFileSync(file, 'utf8'));
const clusters = readJson(path.join(graphRoot, 'clusters.json'));
const files = Object.values(clusters).flat();
const base = readJson(path.join(sourceRoot, 'out/CauldronRegistry.sol/CauldronRegistry.json'));
const settings = typeof base.metadata === 'string' ? JSON.parse(base.metadata).settings : base.metadata.settings;
const groups = new Map();
const selectionNotes = [];

// Artifacts select an installed compatible compiler only. Every AST is then
// regenerated from CURRENT SOURCE; old artifact AST/ABI is never reused.
for (const file of files) {
  const artifactDir = path.join(sourceRoot, 'out', path.basename(file));
  const versions = new Set();
  if (fs.existsSync(artifactDir)) for (const entry of fs.readdirSync(artifactDir)) {
    if (!entry.endsWith('.json')) continue;
    const artifact = readJson(path.join(artifactDir, entry));
    const meta = typeof artifact.metadata === 'string' ? JSON.parse(artifact.metadata) : artifact.metadata;
    if (Object.hasOwn(meta?.settings?.compilationTarget ?? {}, file)) {
      versions.add(meta.compiler.version.split('+')[0]);
    }
  }
  if (versions.size > 1 && !versions.has('0.8.30')) throw new Error(`Ambiguous compiler for ${file}: ${[...versions]}`);
  const version = versions.has('0.8.30') ? '0.8.30' : ([...versions][0] ?? '0.8.30');
  if (versions.size > 1) selectionNotes.push(`${file}: artifacts from ${[...versions].join(', ')}; select production-hook-compatible 0.8.30 for fresh type checks, not bytecode parity`);
  if (!versions.size) selectionNotes.push(`${file}: no artifact; attempt installed 0.8.30 with current-source type checks`);
  if (!groups.has(version)) groups.set(version, []);
  groups.get(version).push(file);
}

fs.mkdirSync(reportRoot, { recursive: true });
const report = { sourceRoot, selectionNotes, compilers: [], declarations: [], sites: [], edges: [],
  contractSurfaces: [], targets: {}, sourceHashes: {}, unresolved: [], unresolvedSelectors: [],
  limitations: [
    'Compiler reference identity is static dispatch evidence, not deployed target identity or authorization.',
    'Dynamic low-level calls retain expression/type/source and require manual target and dataflow review.',
    'No AST or selector inventory is an economic invariant test or completed security review.',
    'Assembly internals remain explicit review sites; Yul is not silently treated as ordinary Solidity calls.',
    'Compiler selections inferred from artifacts must be reconciled with the final deployment profile.',
  ] };

for (const [version, roots] of groups) {
  const compiler = path.resolve(compilersArg, version, `solc-${version}`);
  const input = { language: 'Solidity', sources: Object.fromEntries(roots.map(file => [file, { urls: [file] }])),
    settings: { remappings: settings.remappings, evmVersion: 'cancun',
      outputSelection: { '*': { '': ['ast'], '*': ['abi', 'storageLayout', 'evm.methodIdentifiers'] } } } };
  const inputString = JSON.stringify(input);
  const start = Date.now();
  const result = spawnSync(compiler, ['--base-path', sourceRoot, '--allow-paths', sourceRoot, '--standard-json'],
    { cwd: sourceRoot, input: inputString, encoding: 'utf8', maxBuffer: 256 * 1024 * 1024 });
  if (result.error) throw result.error;
  const output = JSON.parse(result.stdout);
  const errors = (output.errors ?? []).filter(error => error.severity === 'error');
  if (result.status !== 0 || errors.length) {
    throw new Error(`solc ${version}: ${errors.map(error => error.formattedMessage).join('\n') || result.stderr}`);
  }
  report.compilers.push({ version, roots, elapsedMs: Date.now() - start,
    binary_sha256: sha(fs.readFileSync(compiler)), input_sha256: sha(inputString),
    warnings: (output.errors ?? []).map(error => ({ code: error.errorCode, message: error.message })) });
  const sourcesById = new Map();
  const definitions = new Map();
  const id = n => `${version}:${n}`;
  for (const [file, unit] of Object.entries(output.sources)) {
    const bytes = fs.readFileSync(path.join(sourceRoot, file));
    sourcesById.set(unit.id, { file, bytes });
    report.sourceHashes[file] = sha(bytes);
  }
  function location(src) {
    const [offset, length, sourceId] = (src ?? '-1:0:-1').split(':').map(Number);
    const source = sourcesById.get(sourceId);
    if (!source || offset < 0) return null;
    return { file: source.file, line: source.bytes.subarray(0, offset).toString().split('\n').length,
      offset, length, text: source.bytes.subarray(offset, offset + length).toString() };
  }
  function walk(value, visit, owner = null, func = null) {
    if (!value || typeof value !== 'object') return;
    if (Array.isArray(value)) { for (const child of value) walk(child, visit, owner, func); return; }
    const contract = value.nodeType === 'ContractDefinition' ? value : owner;
    const fn = ['FunctionDefinition', 'ModifierDefinition'].includes(value.nodeType) ? value : func;
    if (value.nodeType) visit(value, contract, fn);
    for (const [key, child] of Object.entries(value)) {
      if (!['typeDescriptions', 'documentation'].includes(key)) walk(child, visit, contract, fn);
    }
  }
  for (const unit of Object.values(output.sources)) walk(unit.ast, (node, owner) => {
    if (Number.isInteger(node.id)) definitions.set(node.id, { node, owner, loc: location(node.src) });
  });
  function target(ref) {
    const found = definitions.get(ref);
    if (!found) return null;
    const key = id(ref);
    if (!report.targets[key]) report.targets[key] = {
      name: found.node.name ?? found.node.kind, kind: found.node.nodeType,
      contract: found.owner?.name, source: found.loc && { file: found.loc.file, line: found.loc.line },
      type: found.node.typeDescriptions?.typeString, stateVariable: found.node.stateVariable ?? false,
      visibility: found.node.visibility, mutability: found.node.mutability ?? found.node.stateMutability,
    };
    return key;
  }
  for (const [file, unit] of Object.entries(output.sources)) {
    // Imported first-party sources can appear in more than one compiler group.
    // Emit declarations only in the group selected for that source file.
    if (!roots.includes(file)) continue;
    walk(unit.ast, (node, owner, fn) => {
      const loc = location(node.src);
      if (['FunctionDefinition', 'ModifierDefinition'].includes(node.nodeType)) {
        const body = node.body ? location(node.body.src) : null;
        report.declarations.push({ id: id(node.id), file, contract: owner?.name, name: node.name,
          kind: node.kind ?? 'modifier', line: loc.line, signature: loc.text.split('{')[0].trim(),
          visibility: node.visibility, stateMutability: node.stateMutability,
          selector: node.functionSelector ?? null, body_sha256: body ? sha(body.text) : null,
          modifiers: (node.modifiers ?? []).map(m => ({ target: target(m.modifierName.referencedDeclaration), source: location(m.src) })) });
      }
      if (node.nodeType === 'InlineAssembly') {
        report.sites.push({ kind: 'assembly', parent: fn ? id(fn.id) : null, source: loc,
          externalReferences: node.externalReferences });
      }
      if (node.nodeType !== 'FunctionCall' || node.kind === 'typeConversion') return;
      let expression = node.expression;
      if (expression.nodeType === 'FunctionCallOptions') expression = expression.expression;
      const ref = expression.referencedDeclaration ?? expression.typeName?.referencedDeclaration;
      const resolved = Number.isInteger(ref) && ref >= 0 ? target(ref) : null;
      const call = { parent: fn ? id(fn.id) : null, source: loc, expression: location(expression.src)?.text,
        expressionType: expression.typeDescriptions?.typeString, target: resolved,
        memberName: expression.nodeType === 'MemberAccess' ? expression.memberName : null,
        receiver: expression.nodeType === 'MemberAccess' ? {
          text: location(expression.expression.src)?.text,
          type: expression.expression.typeDescriptions?.typeString,
          declaration: Number.isInteger(expression.expression.referencedDeclaration)
            && expression.expression.referencedDeclaration >= 0
            ? target(expression.expression.referencedDeclaration) : null,
        } : null,
        kind: expression.nodeType === 'NewExpression' ? 'create' : node.kind,
        builtinOrDynamic: !resolved };
      report.edges.push(call);
      if (expression.memberName === 'delegatecall') report.sites.push({ kind: 'delegatecall', parent: call.parent, source: loc });
      if (Number.isInteger(ref) && ref >= 0 && !resolved) report.unresolved.push(call);
    });
    for (const [contract, compiled] of Object.entries(output.contracts?.[file] ?? {})) {
      const definition = unit.ast.nodes.find(n => n.nodeType === 'ContractDefinition' && n.name === contract);
      const bySelector = new Map();
      // Solidity gives the most-derived contract first. Retain the first
      // override/getter for each selector, including imported inherited members.
      for (const baseId of definition?.linearizedBaseContracts ?? []) {
        for (const member of definitions.get(baseId)?.node.nodes ?? []) {
          if (member.functionSelector && !bySelector.has(member.functionSelector)) {
            bySelector.set(member.functionSelector, target(member.id));
          }
        }
      }
      const selectorBindings = {};
      for (const [signature, selector] of Object.entries(compiled.evm?.methodIdentifiers ?? {})) {
        selectorBindings[signature] = bySelector.get(selector) ?? null;
        if (!selectorBindings[signature]) report.unresolvedSelectors.push({ file, contract, signature, selector });
      }
      report.contractSurfaces.push({ file, contract, compiler: version, source_sha256: report.sourceHashes[file],
        methodIdentifiers: compiled.evm?.methodIdentifiers ?? {}, selectorBindings,
        storageLayout: compiled.storageLayout, abi: compiled.abi });
    }
  }
}
fs.writeFileSync(path.join(reportRoot, 'COMPILER_GRAPH.json'), JSON.stringify(report, null, 2) + '\n');
console.log(JSON.stringify({ compilers: report.compilers.map(c => ({ version: c.version, elapsedMs: c.elapsedMs })),
  declarations: report.declarations.length, calls: report.edges.length, sensitiveSites: report.sites.length,
  contractSurfaces: report.contractSurfaces.length, unresolvedCompilerReferences: report.unresolved.length,
  unresolvedSelectors: report.unresolvedSelectors.length }));
if (report.unresolved.length || report.unresolvedSelectors.length) process.exitCode = 1;
