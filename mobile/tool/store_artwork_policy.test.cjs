'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { appleArtworkStory, assertAppleArtworkText } = require('./store_artwork_policy.cjs');

const sample = { out: '02-overdue', title: 'Stay on track', sub: 'Reminders on your schedule', access: 'Pro · Annual subscription · First 7 days free', pro: true };
test('Apple Pro artwork drops offers and keeps subscription disclosure in both languages', () => {
  for (const [lang, expected] of [['ko', 'Pro · 구독 필요'], ['en', 'Pro · Subscription required']]) {
    const story = appleArtworkStory(sample, lang);
    assert.equal(story.access, expected);
    assert.equal(story.title, sample.title);
    assert.doesNotThrow(() => assertAppleArtworkText(story, lang));
  }
  assert.equal(sample.access, 'Pro · Annual subscription · First 7 days free');
});
test('basic and widget access text contains no free offer', () => {
  for (const language of ['ko', 'en']) {
    for (const story of [
      { out: '01-calendar', access: 'Calendar · Included for free' },
      { out: '04-repeat', access: '반복 일정 · 무료 기본 기능' },
      { out: '05-widget', access: 'Widget viewing is free', widget: true },
    ]) assert.doesNotThrow(() => assertAppleArtworkText(appleArtworkStory(story, language), language));
  }
});
test('rejects forbidden offers in every artwork field, including localized and currency variants', () => {
  for (const word of ['무료', '처음 7일 체험', '할인', '₩900', '$0.69', '900원', 'USD 0.69', 'Included for free', 'First 7 days free', 'Free trial', 'Discounted']) {
    for (const field of ['title', 'sub', 'access']) {
      assert.throws(() => assertAppleArtworkText({ out: 'guard', [field]: word }, 'en'), /price\/offer/);
    }
  }
});
test('feature durations remain valid without an offer claim', () => {
  assert.doesNotThrow(() => assertAppleArtworkText({ out: 'stats', title: '지난 7일의 통계', sub: 'Review your last 7 days', access: 'Pro · Subscription required', pro: true }, 'en'));
});
test('rejects other platform references and missing paid-feature disclosure', () => {
  for (const word of ['Android', 'Google Play', 'Play Store', '안드로이드', '구글 플레이']) {
    assert.throws(() => assertAppleArtworkText({ out: 'guard', sub: word }, 'ko'), /another platform/);
  }
  assert.throws(() => assertAppleArtworkText({ out: 'guard', access: 'Basic features', pro: true }, 'en'), /subscription access/);
});
