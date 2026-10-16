'use strict';

// Apple 2.3.7: even free/trial offers count as price advertising in artwork.
// Apple 2.3.10: App Store artwork must describe the Apple experience.
// Pro access remains explicit under 2.3.2; no price/offer is necessary.
const APPLE_ARTWORK_POLICY_VERSION = 1;
const appleDevices = ['iphone', 'iphone-large', 'ipad'];
const forbiddenPrice = /(?:\b(?:free|discount(?:ed)?|price|pricing|sale|trial|USD|EUR|KRW)\b|무료|할인|체험|가격|요금|[$€£¥₩]|\d[\d,.]*\s*(?:원|달러))/iu;
const forbiddenPlatform = /(?:\b(?:Android|Google\s*Play|Play\s*Store)\b|안드로이드|구글\s*플레이)/iu;

function assertAppleArtworkText(story, language) {
  const text = ['title', 'sub', 'access'].map(key => story[key] || '').join('\n');
  if (forbiddenPrice.test(text)) throw new Error(`Apple artwork contains a price/offer reference: ${story.out}`);
  if (forbiddenPlatform.test(text)) throw new Error(`Apple artwork mentions another platform: ${story.out}`);
  const required = language === 'en' ? 'Pro · Subscription required' : 'Pro · 구독 필요';
  if (story.pro && story.access !== required) throw new Error(`Apple Pro artwork must disclose subscription access: ${story.out}`);
}

function appleArtworkStory(story, language) {
  const english = language === 'en';
  let access = story.access;
  if (story.pro) access = english ? 'Pro · Subscription required' : 'Pro · 구독 필요';
  if (story.out === '01-calendar') access = english ? 'Calendar · Basic features' : '캘린더 · 기본 기능';
  if (story.out === '04-repeat') access = english ? 'Repeating tasks · Basic features' : '반복 일정 · 기본 기능';
  if (story.widget) access = english
    ? 'Widget viewing · Start and snooze require Pro'
    : '위젯 보기 · 시작·미루기는 Pro 구독 필요';
  const result = { ...story, access };
  assertAppleArtworkText(result, language);
  return result;
}

module.exports = { APPLE_ARTWORK_POLICY_VERSION, appleDevices, appleArtworkStory, assertAppleArtworkText };
