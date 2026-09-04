#!/usr/bin/env node
/**
 * Tiny save + static server for pixel-editor.html
 * Listens on port 8766
 * GET  /              → serves pixel-editor.html
 * GET  /frens/*       → serves SVG files
 * POST /save          → saves SVG to frens/
 * POST /export-png    → saves PNG to frens/
 */
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';

const PORT = 8766;
const PUBLIC_DIR = path.resolve(import.meta.dirname, '..', 'public');
const FRENS_DIR = path.join(PUBLIC_DIR, 'frens');

const MIME_TYPES = {
  '.html': 'text/html',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.js': 'application/javascript',
  '.css': 'text/css',
  '.json': 'application/json',
};

function cors(res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on('data', c => chunks.push(c));
    req.on('end', () => resolve(Buffer.concat(chunks).toString()));
    req.on('error', reject);
  });
}

const server = http.createServer(async (req, res) => {
  cors(res);

  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    return res.end();
  }

  // --- Static file serving ---
  if (req.method === 'GET') {
    let urlPath = req.url.split('?')[0]; // strip query params
    if (urlPath === '/' || urlPath === '/pixel-editor.html') {
      urlPath = '/pixel-editor.html';
    }

    const filePath = path.join(PUBLIC_DIR, urlPath);
    const safePath = path.resolve(filePath);
    if (!safePath.startsWith(PUBLIC_DIR)) {
      res.writeHead(403);
      return res.end('Forbidden');
    }

    if (fs.existsSync(safePath) && fs.statSync(safePath).isFile()) {
      const ext = path.extname(safePath).toLowerCase();
      const mime = MIME_TYPES[ext] || 'application/octet-stream';
      res.writeHead(200, { 'Content-Type': mime });
      fs.createReadStream(safePath).pipe(res);
      return;
    }
  }

  // --- POST /save ---
  if (req.method === 'POST' && req.url === '/save') {
    try {
      const body = JSON.parse(await readBody(req));
      const { filename, content } = body;
      if (!filename || !content) throw new Error('Missing filename or content');

      const safe = path.basename(filename);
      if (safe !== filename) throw new Error('Invalid filename');

      const target = path.join(FRENS_DIR, safe);
      fs.writeFileSync(target, content, 'utf-8');

      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ ok: true, path: target }));
      console.log(`Saved: ${safe} (${content.length} bytes)`);
    } catch (e) {
      res.writeHead(400, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ ok: false, error: e.message }));
    }
    return;
  }

  // --- POST /export-png ---
  if (req.method === 'POST' && req.url === '/export-png') {
    try {
      const body = JSON.parse(await readBody(req));
      const { filename, base64 } = body;
      if (!filename || !base64) throw new Error('Missing filename or base64');

      const safe = path.basename(filename);
      const target = path.join(FRENS_DIR, safe);

      fs.writeFileSync(target, Buffer.from(base64, 'base64'));

      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ ok: true, path: target }));
      console.log(`Exported PNG: ${safe}`);
    } catch (e) {
      res.writeHead(400, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ ok: false, error: e.message }));
    }
    return;
  }

  res.writeHead(404, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ error: 'Not found' }));
});

server.listen(PORT, () => {
  console.log(`Pixel editor running at http://localhost:${PORT}`);
  console.log(`Serving from: ${PUBLIC_DIR}`);
  console.log(`Saving to: ${FRENS_DIR}`);
});
