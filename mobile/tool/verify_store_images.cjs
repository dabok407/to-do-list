'use strict';
const fs = require('node:fs/promises');
const path = require('node:path');
const crypto = require('node:crypto');
const { APPLE_ARTWORK_POLICY_VERSION, appleDevices, assertAppleArtworkText } = require('./store_artwork_policy.cjs');
const sharp = require(process.env.HANGEOREUM_SHARP_MODULE || 'sharp');
const store = path.resolve(__dirname, '../store');
const names = ['01-calendar','02-overdue','03-start','04-repeat','05-stats-detail','06-stats','07-privacy'];
// These are accepted Apple display slots (medium + large iPhone, 13-inch
// iPad) and the Play portrait canvas. Console upload/review is still separate.
const specs = { iphone: [1179,2556], 'iphone-large': [1320,2868], ipad: [2064,2752], android: [1080,1920] };
(async () => {
  const results = [];
  for (const language of ['ko', 'en']) {
   const relativeRoot = language === 'en' ? ['en'] : [];
   const expectedBrand = language === 'en' ? 'Todoniq' : '투두닉';
   const manifest = JSON.parse(await fs.readFile(path.join(store, 'screenshots', ...relativeRoot, 'manifest.json'), 'utf8'));
   if (manifest.language !== language || manifest.brand !== expectedBrand || manifest.nativeWidgets !== false) throw new Error(`Wrong artwork manifest: ${language}`);
   if (manifest.apple_artwork_policy !== APPLE_ARTWORK_POLICY_VERSION) throw new Error(`Regenerate Apple artwork under the current text policy: ${language}`);
   for (const device of ['iphone', 'ipad', 'android']) {
    const source = JSON.parse(await fs.readFile(path.join(store, 'captures', ...relativeRoot, device, 'source.json'), 'utf8'));
    if (source.language !== language || source.display_name !== expectedBrand || source.native_device_capture !== false) throw new Error(`Stale source capture: ${language}/${device}`);
   }
   for (const [device, [width,height]] of Object.entries(specs)) {
    const folder = path.join('screenshots', ...(language === 'en' ? ['en'] : []), device);
    for (const name of names) {
      const file = path.join(store, folder, `${name}.png`);
      const data = await fs.readFile(file);
      const m = await sharp(data).metadata();
      if (m.width !== width || m.height !== height || m.hasAlpha || m.channels !== 3 || m.format !== 'png') throw new Error(`Wrong format: ${file}`);
      if (data.length < 12000) throw new Error(`Suspiciously empty image: ${file}`);
      if (appleDevices.includes(device)) {
        const artwork = manifest.artwork?.[device]?.find(story => story.out === name);
        if (!artwork) throw new Error(`Missing Apple artwork provenance: ${language}/${device}/${name}`);
        assertAppleArtworkText(artwork, language);
        const actual = crypto.createHash('sha256').update(data).digest('hex');
        if (artwork.sha256 !== actual) throw new Error(`Apple image changed since composition: ${file}`);
        const sourceDevice = device === 'iphone-large' ? 'iphone' : device;
        const capture = await fs.readFile(path.join(store, 'captures', ...relativeRoot, sourceDevice, `${artwork.source}.png`));
        if (artwork.capture_sha256 !== crypto.createHash('sha256').update(capture).digest('hex')) throw new Error(`Apple source changed since composition: ${language}/${device}/${name}`);
      }
      results.push({ file: `${folder.replaceAll('\\', '/')}/${name}.png`, language, width, height, channels: m.channels, bytes: data.length, sha256: crypto.createHash('sha256').update(data).digest('hex') });
    }
  }
  }
  for (const [name,width,height,alpha] of [['play-feature-1024x500',1024,500,false],['play-feature-1024x500-en',1024,500,false],['app-store-icon-1024',1024,1024,false],['play-icon-512',512,512,true]]) {
    const data = await fs.readFile(path.join(store, 'assets', `${name}.png`));
    const m = await sharp(data).metadata();
    if (m.width !== width || m.height !== height || m.hasAlpha !== alpha) throw new Error(`Wrong asset: ${name}`);
    if (name === 'play-icon-512' && data.length > 1024*1024) throw new Error('Play icon exceeds 1MB');
    results.push({ file: `assets/${name}.png`, width, height, channels: m.channels, bytes: data.length, sha256: crypto.createHash('sha256').update(data).digest('hex') });
  }
  await fs.writeFile(path.join(store, 'assets/image-verification.json'), JSON.stringify({ verified_at: new Date().toISOString(), brands: { ko: '투두닉', en: 'Todoniq' }, screenshots: 56, assets: 4, specifications: specs, apple_artwork_policy: APPLE_ARTWORK_POLICY_VERSION, apple_artwork_text_reviewed: 42, source_pixels: 'Production Flutter captures, composed without retouching; visual source-content review is separate', apple_specification_reference: 'https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/', results }, null, 2) + '\n');
  console.log('PASS: 56 localized screenshots + 4 store assets; formats verified. All 42 Apple artworks pass offer/platform text and composed/source SHA-256 checks.');
})().catch(e => { console.error(e); process.exitCode = 1; });
