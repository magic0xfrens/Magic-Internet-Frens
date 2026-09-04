import { createServer } from 'node:http';
import { writeFile, mkdir } from 'node:fs/promises';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const FRENS_DIR = join(__dirname, 'public', 'frens');
const EXPORT_DIR = join(__dirname, 'public', 'exports');
const PORT = 8766;

await mkdir(EXPORT_DIR, { recursive: true });

const server = createServer(async (req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') { res.writeHead(204); res.end(); return; }

  if (req.method === 'POST') {
    const chunks = [];
    for await (const c of req) chunks.push(c);
    const body = JSON.parse(Buffer.concat(chunks).toString());

    if (req.url === '/save') {
      const filePath = join(FRENS_DIR, body.filename);
      await writeFile(filePath, body.content, 'utf8');
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ ok: true, path: filePath }));
      console.log(`Saved ${body.filename}`);
      return;
    }

    if (req.url === '/export-png') {
      const filePath = join(EXPORT_DIR, body.filename);
      await writeFile(filePath, Buffer.from(body.base64, 'base64'));
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ ok: true, path: filePath }));
      console.log(`Exported ${body.filename}`);
      return;
    }
  }

  res.writeHead(404);
  res.end('Not found');
});

server.listen(PORT, () => console.log(`Pixel editor API running on http://localhost:${PORT}`));
