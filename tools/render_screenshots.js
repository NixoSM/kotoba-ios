#!/usr/bin/env node
// Photographs the results pages written by RenderTests (see
// Tests/KotobaAppLogicTests/RenderTests.swift) at the size of an iPhone 15.
//
//   KOTOBA_RENDER_OUT=out swift test --filter RenderTests
//   node tools/render_screenshots.js out
//
// The pages are the app's own HTML. Two things differ from the phone and are
// patched here: fonts come from App/Resources/Fonts instead of the app, and
// Apple's system fonts are replaced by the nearest font this machine has.
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const folder = path.resolve(process.argv[2] || 'out');
const fonts = path.resolve(__dirname, '..', 'App', 'Resources', 'Fonts');
const standIns = `<style>
@font-face{font-family:'Hiragino Sans';src:local('Noto Sans CJK JP'),local('Noto Sans JP'),local('IPAPGothic'),local('IPAGothic');}
@font-face{font-family:'Hiragino Mincho ProN';src:local('Noto Serif CJK JP'),local('IPAPMincho'),local('IPAMincho');}
@font-face{font-family:'-apple-system';font-weight:100 900;src:local('Inter'),local('DejaVu Sans'),local('Liberation Sans');}
</style>`;

function patched(html) {
  return html
    // The page forbids every source but the app's own; here the fonts are files.
    .replace(/<meta http-equiv="Content-Security-Policy"[^>]*>/, standIns)
    .replace(/kotoba-media:\/\/font\//g, 'file://' + fonts + '/');
}

(async () => {
  const pages = fs.readdirSync(folder).filter(f => f.endsWith('.html') && !f.startsWith('_')).sort();
  if (pages.length === 0) { console.error('No pages in ' + folder); process.exit(1); }
  const browser = await chromium.launch();
  const context = await browser.newContext({ viewport: { width: 393, height: 760 }, deviceScaleFactor: 2 });
  for (const file of pages) {
    const copy = path.join(folder, '_' + file);
    fs.writeFileSync(copy, patched(fs.readFileSync(path.join(folder, file), 'utf8')));
    const page = await context.newPage();
    const errors = [];
    page.on('pageerror', e => errors.push(String(e)));
    await page.goto('file://' + copy);
    await page.evaluate(() => document.fonts.ready);
    await page.screenshot({ path: path.join(folder, file.replace(/\.html$/, '.png')) });
    await page.close();
    fs.unlinkSync(copy);
    if (errors.length) { console.error(file + ': ' + errors.join('; ')); process.exitCode = 1; }
    console.log('photographed ' + file);
  }
  // One sheet with every page, to look at them side by side.
  const sheet = path.join(folder, '_sheet.html');
  fs.writeFileSync(sheet, `<body style="margin:0;background:#888;display:grid;grid-template-columns:repeat(4,393px);gap:12px;padding:12px;font:12px sans-serif;color:#fff">`
    + pages.map(f => `<figure style="margin:0"><img src="${f.replace(/\.html$/, '.png')}" width="393"><figcaption>${f.replace(/\.html$/, '')}</figcaption></figure>`).join('')
    + `</body>`);
  const page = await browser.newPage({ viewport: { width: 4 * 393 + 5 * 12, height: 800 }, deviceScaleFactor: 1 });
  await page.goto('file://' + sheet);
  await page.screenshot({ path: path.join(folder, 'all-pages.png'), fullPage: true });
  fs.unlinkSync(sheet);
  await browser.close();
})();
