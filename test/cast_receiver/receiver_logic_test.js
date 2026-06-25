const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

const repoRoot = path.resolve(__dirname, '..', '..');
const receiverHtml = fs.readFileSync(
  path.join(repoRoot, 'cast_receiver', 'index.html'),
  'utf8',
);

const logicScript = receiverHtml.match(
  /<script>\s*(window\.GlacierReceiverLogic = \(\(\) => \{[\s\S]*?\}\)\(\);)\s*<\/script>/,
);

assert.ok(logicScript, 'receiver must expose GlacierReceiverLogic helpers');

const context = { window: {} };
vm.runInNewContext(logicScript[1], context);
const logic = context.window.GlacierReceiverLogic;

test('receiver does not perform hard latency seeks', () => {
  assert.equal(typeof logic.finiteNumber, 'function');
  assert.doesNotMatch(receiverHtml, /playerManager\.seek/);
  assert.doesNotMatch(receiverHtml, /hard_latency_correction/);
});

test('receiver keeps supported low-latency Shaka configuration values', () => {
  assert.match(receiverHtml, /const STATUS_INTERVAL_MS = 500;/);
  assert.match(receiverHtml, /const TARGET_LATENCY_SECONDS = 2\.25;/);
  assert.match(receiverHtml, /const MAX_DYNAMIC_LATENCY_SECONDS = 5\.0;/);
  assert.match(receiverHtml, /const MANIFEST_REQUEST_TIMEOUT_MS = 2500;/);
  assert.match(receiverHtml, /const SEGMENT_REQUEST_TIMEOUT_MS = 4500;/);
  assert.match(receiverHtml, /autoResumeNumberOfSegments = 1/);
  assert.match(receiverHtml, /targetLatencyTolerance: 0\.15/);
  assert.match(receiverHtml, /bufferingGoal: 4/);
  assert.match(receiverHtml, /rebufferingGoal: 2\.5/);
  assert.match(receiverHtml, /bufferBehind: 6/);
  assert.match(receiverHtml, /segmentPrefetchLimit: 2/);
  assert.match(receiverHtml, /maxPlaybackRate: 1\.01/);
  assert.match(receiverHtml, /minPlaybackRate: 0\.97/);
  assert.match(receiverHtml, /minLatency: TARGET_LATENCY_SECONDS/);
  assert.match(receiverHtml, /maxLatency: MAX_DYNAMIC_LATENCY_SECONDS/);
  assert.match(receiverHtml, /panicMode: false/);
  assert.match(receiverHtml, /availabilityWindowOverride: 30/);
  assert.doesNotMatch(receiverHtml, /enableSmoothLiveRefresh/);
  assert.doesNotMatch(receiverHtml, /ignoreTextStreamFailures/);
});

test('receiver keeps segment timeouts longer than manifest timeouts', () => {
  assert.match(receiverHtml, /manifestRetryParameters = \{/);
  assert.match(receiverHtml, /segmentRetryParameters = \{/);
  assert.match(receiverHtml, /manifest: \{[\s\S]*?retryParameters: manifestRetryParameters/);
  assert.match(receiverHtml, /streaming: \{[\s\S]*?retryParameters: segmentRetryParameters/);
});

test('receiver forwards runtime diagnostics to sender', () => {
  assert.match(receiverHtml, /const RECEIVER_VERSION = '2026-06-24-2';/);
  assert.match(receiverHtml, /type: 'diagnostic'/);
  assert.match(receiverHtml, /action: action/);
  assert.match(receiverHtml, /receiverVersion: RECEIVER_VERSION/);
  assert.match(receiverHtml, /latency_watchdog/);
  assert.match(receiverHtml, /bufferingAgeMs/);
  assert.match(receiverHtml, /playerState/);
  assert.match(receiverHtml, /shaka_stats/);
  assert.match(receiverHtml, /getStats/);
});
