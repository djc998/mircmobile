import { test } from 'node:test';
import assert from 'node:assert/strict';
import { ago, formatReports } from '../tools/format-reports.js';

const now = Date.parse('2026-11-23T20:00:00Z');

test('no reports', () => {
  assert.equal(formatReports({ reports: [] }, now), 'No reports. Nothing to review.');
});

test('newest first, last 24 hours marked NEW, messages and photos', () => {
  const text = formatReports(
    {
      reports: [
        {
          link: 'https://pics.test/p/abc',
          id: 'abc',
          sender: 'old',
          network: 'irc.oftc.net',
          reason: 'Spam or scam',
          reportedAt: '2026-11-20T20:00:00Z',
        },
        {
          kind: 'message',
          text: 'buy\ncheap pills',
          sender: 'troll',
          network: 'irc.libera.chat',
          room: '#chat',
          reason: 'Spam or scam',
          reportedAt: '2026-11-23T17:00:00Z',
        },
        {
          kind: 'message',
          text: 'hi',
          sender: 'dm',
          network: 'irc.libera.chat',
          room: null,
          reason: '',
          reportedAt: '2026-11-23T19:58:00Z',
        },
      ],
    },
    now,
  );
  const lines = text.split('\n');
  assert.equal(lines[0], '3 reports, 2 in the last 24 hours (review those today).');
  assert.match(lines[2], /^NEW {2}Message from dm on irc\.libera\.chat in a private chat, 2 min ago/);
  assert.match(text, /NEW {2}Message from troll on irc\.libera\.chat in #chat, 3 h ago/);
  assert.match(text, /Text: {3}buy cheap pills/);
  assert.match(text, /Reason: \(none given\)/);
  assert.match(text, / {5}Photo from old on irc\.oftc\.net, 3 days ago/);
  assert.match(text, /Photo: {2}https:\/\/pics\.test\/p\/abc/);
  assert.ok(text.indexOf('dm') < text.indexOf('troll'));
  assert.ok(text.indexOf('troll') < text.indexOf('from old'));
});

test('ago', () => {
  assert.equal(ago('2026-11-23T19:59:50Z', now), 'just now');
  assert.equal(ago('nonsense', now), 'unknown time');
});
