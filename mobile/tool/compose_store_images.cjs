// Export marketing artwork from actual Flutter/native-widget captures.
// No UI is redrawn or replaced. Requires sharp and the bundled Pretendard font.
'use strict';
const fs = require('node:fs/promises');
const syncFs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const store = path.join(root, 'store');
const fontfile = path.join(root, 'assets/fonts/PretendardVariable.ttf');
// Keep font caches in this workspace; no user font installation is necessary.
const cache = path.resolve(root, '../.tools/store-fontconfig');
syncFs.mkdirSync(cache, { recursive: true });
const config = path.join(cache, 'fonts.conf');
syncFs.writeFileSync(config, `<?xml version="1.0"?><!DOCTYPE fontconfig SYSTEM "fonts.dtd"><fontconfig><dir>${path.dirname(fontfile).replaceAll('\\', '/')}</dir><cachedir>${cache.replaceAll('\\', '/')}</cachedir></fontconfig>`);
process.env.FONTCONFIG_FILE = config;
const sharp = require(process.env.HANGEOREUM_SHARP_MODULE || 'sharp');
const partial = process.argv.includes('--partial');
const language = process.argv.find(arg => arg.startsWith('--language='))?.split('=')[1] || 'ko';
if (!['ko', 'en'].includes(language)) throw new Error(`Unsupported language: ${language}`);
const english = language === 'en';
const captureRoot = path.join(store, 'captures', ...(english ? ['en'] : []));
const outputRoot = path.join(store, 'screenshots', ...(english ? ['en'] : []));
// Native widget captures are included only after regeneration from the current
// build. Until then use the real statistics detail, never stale branding.
const nativeWidgets = process.argv.includes('--native-widgets');
const ink = '#292c29', muted = '#616875', red = '#8f303a';
const devices = {
  iphone: { width: 1179, height: 2556, label: 'iPhone · medium' },
  'iphone-large': { width: 1320, height: 2868, label: 'iPhone · large', sourceDevice: 'iphone' },
  ipad: { width: 2064, height: 2752, label: 'iPad' },
  android: { width: 1080, height: 1920, label: 'Android' },
};
// Re-export one device without changing artwork already approved for others.
const deviceArg = process.argv.find(arg => arg.startsWith('--device='));
const selectedDevice = deviceArg?.slice('--device='.length);
if (selectedDevice && !Object.hasOwn(devices, selectedDevice)) {
  throw new Error(`Unknown device: ${selectedDevice}`);
}
const stories = [
  { out: '01-calendar', source: '01-calendar', title: '오늘 할 일, 한눈에', sub: '날짜를 누르면 그날의 일정이 펼쳐져요', access: '캘린더 · 기본 기능' },
  { out: '02-overdue', source: '02-overdue', title: '끝내지 못한 일도\n잊지 않게', sub: '남은 일을 모아 보고, 원하는 주기로 다시 알림', access: 'Pro · 구독 필요 · 처음 7일 체험', pro: true },
  { out: '03-start', source: '03-small-start', title: '어렵다면,\n5분만 시작해요', sub: '미루던 일도 작은 첫걸음부터', access: 'Pro · 구독 필요 · 처음 7일 체험', pro: true },
  { out: '04-repeat', source: '04-repeat', title: '반복 일정은\n내 생활에 맞게', sub: '요일과 주기, 시작일과 종료일까지', access: '반복 일정 · 기본 기능' },
  { out: '05-widget', source: 'widget', title: '다음 할 일은\n홈 화면에서', sub: '가까운 일정과 우선순위를 바로 확인해요', access: '위젯 보기 무료 · 시작·미루기는 Pro', widget: true },
  { out: '06-stats', source: '06-statistics', title: '내가 해낸 일을\n돌아보기', sub: '완료한 일과 미룬 기록을 한눈에', access: 'Pro · 구독 필요 · 처음 7일 체험', pro: true },
  { out: '07-privacy', source: '07-privacy', title: '내 일정은\n내 기기에', sub: '회원가입 없이, 할 일과 메모를 로컬에 저장', access: '할 일·메모를 개발자 서버로 보내지 않아요' },
];
// Android OS capture is unavailable on this PC (unsupported HAXM). Use the
// actual 30-day statistics screen for its fifth slide, never an iOS widget.
const androidDetails = { out: '05-stats-detail', source: '06-statistics-detail', title: '나의 실행 패턴을\n알아봐요', sub: '최근 30일의 완료율과 미룬 시간을 확인해요', access: 'Pro · 구독 필요 · 처음 7일 체험', pro: true };
const englishStories = [
  { out: '01-calendar', source: '01-calendar', title: 'Your day, at a glance', sub: 'Tap a date to see what is planned', access: 'Calendar · Included for free' },
  { out: '02-overdue', source: '02-overdue', title: 'Keep unfinished tasks\nin sight', sub: 'See what is left, with reminders on your schedule', access: 'Pro · Annual subscription · First 7 days free', pro: true },
  { out: '03-start', source: '03-small-start', title: 'Start small.\nTry five minutes.', sub: 'Make the first step easier', access: 'Pro · Annual subscription · First 7 days free', pro: true },
  { out: '04-repeat', source: '04-repeat', title: 'Routines that fit\nyour life', sub: 'Choose days, intervals, and an end date', access: 'Repeating tasks · Included for free' },
  { out: '05-widget', source: 'widget', title: 'Your next task,\non your home screen', sub: 'Upcoming tasks and priorities at a glance', access: 'Widget viewing is free · Start and snooze with Pro', widget: true },
  { out: '06-stats', source: '06-statistics', title: 'See what you\nhave accomplished', sub: 'Review completions and snooze history', access: 'Pro · Annual subscription · First 7 days free', pro: true },
  { out: '07-privacy', source: '07-privacy', title: 'Your plans stay\non your device', sub: 'No account. Tasks and notes are saved locally.', access: 'Tasks and notes are not sent to a developer server' },
];
const englishDetails = { out: '05-stats-detail', source: '06-statistics-detail', title: 'Find your\nexecution patterns', sub: 'Review completion and snooze statistics over 30 days', access: 'Pro · Annual subscription · First 7 days free', pro: true };
const storyFor = (device, index) => index === 4 && (device === 'android' || !nativeWidgets)
  ? (english ? englishDetails : androidDetails)
  : (english ? englishStories : stories)[index];
const xml = s => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
async function textLayer(text, size, color = ink, weight = 600, maxWidth) {
  const markup = `<span foreground="${color}" weight="${weight}">${xml(text)}</span>`;
  let buf, info;
  do {
    buf = await sharp({ text: { text: markup, font: `Pretendard ${size}`, fontfile, rgba: true, spacing: Math.round(size * .15) } }).png().toBuffer();
    info = await sharp(buf).metadata();
    if (!maxWidth || info.width <= maxWidth) break;
    size -= 1;
  } while (size >= 12);
  if (maxWidth && info.width > maxWidth) throw new Error(`Text overflows: ${text}`);
  return { input: buf, width: info.width, height: info.height };
}
async function addText(layers, text, left, top, size, color, weight, width) {
  const t = await textLayer(text, size, color, weight, width);
  layers.push({ input: t.input, left: Math.round(left), top: Math.round(top) });
  return t;
}
async function exists(file) { try { await fs.access(file); return true; } catch { return false; } }
async function exportScreen(device, d, s) {
  // Keep the approved production pixels; export an additional Apple display
  // canvas without pretending it is a separate native-device screenshot.
  const sourceDevice = d.sourceDevice || device;
  const input = path.join(captureRoot, sourceDevice, `${s.source}.png`);
  if (!await exists(input)) {
    if (partial) return;
    throw new Error(`Missing actual UI capture: ${input}`);
  }
  const { width: w, height: h } = d;
  const isTablet = device === 'ipad';
  const isPhone = sourceDevice === 'iphone';
  const unit = w / 1080;
  const left = Math.round(w * .066), maxWidth = w - left * 2;
  const header = Math.round(h * .185);
  const layers = [];
  await addText(layers, '첫칸', left, Math.round(header * .095), Math.round(26 * unit), muted, 600, maxWidth);
  const titleSize = Math.round((isTablet ? 46 : 52) * unit);
  const title = await addText(layers, s.title, left, Math.round(header * .24), titleSize, ink, 700, maxWidth);
  const subY = Math.round(header * .24) + title.height + Math.round(21 * unit);
  const sub = await addText(layers, s.sub, left, subY, Math.round(28 * unit), muted, 400, maxWidth);
  const accessY = Math.min(header - Math.round(31 * unit), subY + sub.height + Math.round(20 * unit));
  const access = await addText(layers, s.access, left, accessY, Math.round(23 * unit), s.pro ? red : muted, 500, maxWidth);
  if (subY + sub.height > accessY - 8 || accessY + access.height > header + 2) throw new Error(`Header collision: ${device}/${s.out}`);
  // iPhone's tall canvas needs content-based spacing: a one-line headline
  // should not leave the same empty header as a two-line headline.
  const imageTop = isPhone
    ? accessY + access.height + Math.round(52 * unit)
    : header + Math.round(21 * unit);
  if (s.widget) {
    // These are pixels rendered by WidgetKit / Android RemoteViews, not a fake home screen.
    const previewWidth = Math.round(w * .84);
    const preview = await sharp(input).resize({ width: previewWidth }).png().toBuffer();
    const previewMeta = await sharp(preview).metadata();
    const widgetTop = imageTop + (isPhone ? 0 : Math.round(70 * unit));
    layers.push({ input: preview, left: Math.round((w - previewWidth) / 2), top: widgetTop });
    const captionTop = widgetTop + previewMeta.height + Math.round(42 * unit);
    await addText(layers, english ? 'iOS home widget' : 'iOS 홈 위젯', left, captionTop, Math.round(35 * unit), ink, 600, maxWidth);
    await addText(layers, english ? 'Upcoming tasks, with important ones first' : '가장 가까운 일정부터, 중요한 일은 먼저', left, captionTop + Math.round(59 * unit), Math.round(27 * unit), muted, 400, maxWidth);
    const smallFile = path.join(captureRoot, sourceDevice, 'widget-small.png');
    if (device !== 'android' && await exists(smallFile)) {
      const smallWidth = Math.round(w * (isTablet ? .35 : .46));
      const smallTop = captionTop + Math.round(153 * unit);
      const small = await sharp(smallFile).resize({ width: smallWidth }).png().toBuffer();
      layers.push({ input: small, left, top: smallTop });
      await addText(layers, english ? 'Small widget, too' : '작은 위젯에서도', left + smallWidth + Math.round(27 * unit), smallTop + Math.round(80 * unit), Math.round(32 * unit), ink, 600, w - left * 2 - smallWidth - Math.round(27 * unit));
      await addText(layers, english ? 'See your next task\nwith a quick glance' : '다음 할 일 하나를\n바로 확인해요', left + smallWidth + Math.round(27 * unit), smallTop + Math.round(142 * unit), Math.round(27 * unit), muted, 400, w - left * 2 - smallWidth - Math.round(27 * unit));
      if (smallTop + smallWidth > h - 20) throw new Error(`Widget overflow: ${device}`);
    }
  } else {
    const available = h - imageTop - Math.round(24 * unit);
    const preview = await sharp(input).resize({ width: maxWidth, height: available, fit: 'inside' }).png().toBuffer();
    const m = await sharp(preview).metadata();
    const x = Math.round((w - m.width) / 2);
    layers.push({ input: Buffer.from(`<svg width="${w}" height="${h}"><rect x="${x - 1}" y="${imageTop - 1}" width="${m.width + 2}" height="${m.height + 2}" rx="12" fill="none" stroke="#d9dde1" stroke-width="2"/></svg>`), left: 0, top: 0 });
    layers.push({ input: preview, left: x, top: imageTop });
  }
  const dir = path.join(outputRoot, device);
  await fs.mkdir(dir, { recursive: true });
  await sharp({ create: { width: w, height: h, channels: 3, background: '#ffffff' } }).composite(layers).removeAlpha().png({ compressionLevel: 9 }).toFile(path.join(dir, `${s.out}.png`));
  console.log(`${device}/${s.out}.png ${w}x${h} RGB`);
}
async function featureGraphic() {
  const layers = [];
  const icon = await sharp(path.join(store, 'assets/app-store-icon-1024.png')).resize(58, 58).png().toBuffer();
  layers.push({ input: icon, left: 52, top: 49 });
  await addText(layers, '첫칸', 129, 57, 33, ink, 650, 420);
  await addText(layers, english ? 'Start with\none small step' : '미루던 일,\n한 가지부터', 52, 154, 54, ink, 700, 520);
  await addText(layers, english ? 'Tasks and notes stay on your device' : '할 일과 메모는 내 기기에', 54, 345, 23, muted, 400, 540);
  await addText(layers, english ? 'Reminders, snooze, and statistics require Pro' : '알림·미루기·통계는 Pro 구독 기능', 54, 413, 18, muted, 500, 540);
  const src = path.join(captureRoot, 'android/01-calendar.png');
  const app = await sharp(src).resize({ height: 469 }).png().toBuffer();
  const am = await sharp(app).metadata();
  layers.push({ input: Buffer.from(`<svg width="1024" height="500"><rect x="${974 - am.width - 1}" y="15" width="${am.width + 2}" height="471" rx="8" fill="none" stroke="#c9cdd3"/></svg>`), left: 0, top: 0 });
  layers.push({ input: app, left: 974 - am.width, top: 16 });
  await sharp({ create: { width: 1024, height: 500, channels: 3, background: '#fff' } }).composite(layers).removeAlpha().png().toFile(path.join(store, `assets/play-feature-1024x500${english ? '-en' : ''}.png`));
}
async function contactSheet() {
  const width = 1800, top = 135, cell = 240, gap = 12, left = 24;
  const layers = [];
  await addText(layers, english ? '첫칸 · Store images in English' : '첫칸 · 스토어 소개 이미지', left, 31, 40, ink, 650, 1700);
  await addText(layers, english ? 'iPhone medium + large / iPad / Android · 7 images each · Actual app components' : 'iPhone 중형 + 대형 / iPad / Android · 규격별 7장씩 · 실제 앱 화면 기반', left, 89, 21, muted, 400, 1700);
  let rowTop = top;
  for (const [device, d] of Object.entries(devices)) {
    await addText(layers, d.label, left, rowTop, 26, ink, 600, 1700);
    rowTop += 45;
    const height = device === 'ipad' ? 320 : 520;
    for (let i = 0; i < stories.length; i++) {
      const story = storyFor(device, i);
      const file = path.join(outputRoot, device, `${story.out}.png`);
      if (!await exists(file)) continue;
      const b = await sharp(file).resize({ width: cell, height, fit: 'inside' }).png().toBuffer();
      const m = await sharp(b).metadata();
      layers.push({ input: b, left: left + i * (cell + gap), top: rowTop });
      await addText(layers, `${i + 1}. ${story.title.replace('\n', ' ')}`, left + i * (cell + gap), rowTop + height + 12, 16, muted, 500, cell);
    }
    rowTop += height + 72;
  }
  await sharp({ create: { width, height: rowTop, channels: 3, background: '#f5f6f7' } }).composite(layers).removeAlpha().png().toFile(path.join(store, `assets/store-contact-sheet${english ? '-en' : ''}.png`));
}
(async () => {
  for (const [device, d] of Object.entries(devices)) {
    if (selectedDevice && selectedDevice !== device) continue;
    for (let i = 0; i < stories.length; i++) await exportScreen(device, d, storyFor(device, i));
  }
  if ((!selectedDevice || selectedDevice === 'android') && await exists(path.join(captureRoot, 'android/01-calendar.png'))) await featureGraphic();
  await contactSheet();
  await fs.writeFile(path.join(outputRoot, 'manifest.json'), JSON.stringify({ language, nativeWidgets, devices: Object.keys(devices), specifications: devices, images: stories.map((_, i) => storyFor('iphone', i).out + '.png') }, null, 2));
})().catch(e => { console.error(e); process.exitCode = 1; });
