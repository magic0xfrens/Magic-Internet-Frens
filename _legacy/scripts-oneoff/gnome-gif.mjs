import puppeteer from 'puppeteer';
import { execSync } from 'child_process';
import { mkdirSync } from 'fs';
import path from 'path';

const FRAMES_DIR = '/Users/0x0010110/Documents/GitHub/MagicFrens/tmp-gnome-frames';
const OUTPUT = '/Users/0x0010110/Documents/GitHub/MagicFrens/public/gnome-all.gif';
const FACES = 11;
const SIZE = 480;

mkdirSync(FRAMES_DIR, { recursive: true });

const browser = await puppeteer.launch({ headless: true });
const page = await browser.newPage();
await page.setViewport({ width: SIZE, height: SIZE, deviceScaleFactor: 1 });

const htmlUrl = `file://${path.resolve('/Users/0x0010110/Documents/GitHub/MagicFrens/public/frens/gnome-frame.html')}`;
await page.goto(htmlUrl, { waitUntil: 'networkidle0' });

for (let i = 1; i <= FACES; i++) {
  await page.evaluate((n) => window.setFace(n), i);
  // Wait for image to load
  await page.waitForFunction(() => {
    const img = document.getElementById('face');
    return img.complete && img.naturalWidth > 0;
  }, { timeout: 3000 });
  await new Promise(r => setTimeout(r, 150));

  const pad = String(i).padStart(2, '0');
  await page.screenshot({
    path: `${FRAMES_DIR}/frame-${pad}.png`,
    clip: { x: 0, y: 0, width: SIZE, height: SIZE },
    omitBackground: false,
  });
  console.log(`Frame ${i}/${FACES}`);
}

await browser.close();

// Combine into GIF with ffmpeg — 2fps (500ms per face)
console.log('Combining into GIF...');
execSync(
  `ffmpeg -y -framerate 2 -i "${FRAMES_DIR}/frame-%02d.png" ` +
  `-vf "split[s0][s1];[s0]palettegen=max_colors=128[p];[s1][p]paletteuse=dither=bayer:bayer_scale=2" ` +
  `-loop 0 "${OUTPUT}"`,
  { stdio: 'inherit' }
);

console.log(`\nDone! GIF saved to: ${OUTPUT}`);
