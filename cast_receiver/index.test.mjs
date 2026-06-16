import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const receiverHtml = fs.readFileSync(new URL('./index.html', import.meta.url), 'utf8');
const inlineScriptBody = receiverHtml.match(
	/<script>\s*\(\(\) => \{([\s\S]*)\}\)\(\);\s*<\/script>/,
)?.[1];

if (!inlineScriptBody) {
	throw new Error('Unable to find Cast receiver inline script');
}

const inlineScript = `(() => {${inlineScriptBody}})();`;

const createHarness = ({fetchImpl} = {}) => {
	let nowMs = 0;
	const intervals = [];
	const sentMessages = [];
	const consoleMessages = [];
	const messageListeners = new Map();
	const loadInterceptors = new Map();
	const seekCalls = [];
	const loadCalls = [];
	const peerConnections = [];
	const fetchCalls = [];

	let liveRange = {start: 0, end: 0};
	let currentTimeSec = 0;
	let playerState = 'PLAYING';
	let playbackRate = 1.0;
	let playbackConfig = null;
	let receiverOptions = null;
	const videoElement = {
		autoplay: true,
		playsInline: true,
		srcObject: null,
		style: {},
		playbackRate,
		play: () => Promise.resolve(),
	};
	const castMediaPlayerElement = {
		style: {},
	};

	const playerManager = {
		getLiveSeekableRange: () => liveRange,
		getCurrentTimeSec: () => currentTimeSec,
		getPlayerState: () => playerState,
		getPlaybackRate: () => playbackRate,
		setPlaybackConfig: (config) => {
			playbackConfig = config;
		},
		setMessageInterceptor: (type, interceptor) => {
			loadInterceptors.set(type, interceptor);
		},
		seek: (request) => {
			seekCalls.push(request);
			currentTimeSec = request.currentTime;
		},
		load: (request) => {
			loadCalls.push(request);
			return Promise.resolve();
		},
	};

	const receiverContext = {
		getPlayerManager: () => playerManager,
		getSenders: () => [{id: 'sender-1'}],
		sendCustomMessage: (_namespace, _senderId, message) => {
			sentMessages.push(message);
		},
		addCustomMessageListener: (namespace, listener) => {
			messageListeners.set(namespace, listener);
		},
		start: (options) => {
			receiverOptions = options;
		},
	};

	const sandbox = {
		cast: {
			framework: {
				CastReceiverContext: {
					getInstance: () => receiverContext,
				},
				PlaybackConfig: function PlaybackConfig() {},
				CastReceiverOptions: function CastReceiverOptions() {},
				messages: {
					MessageType: {
						LOAD: 'LOAD',
					},
					ResumeState: {
						PLAYBACK_START: 'PLAYBACK_START',
					},
					StreamType: {
						LIVE: 'LIVE',
					},
				},
			},
		},
		console: {
			log: (message) => {
				consoleMessages.push(String(message));
			},
		},
		Date: {
			now: () => nowMs,
		},
		document: {
			getElementById: (id) => {
				if (id === 'webrtc-video') return videoElement;
				if (id === 'hls-player') return castMediaPlayerElement;
				return null;
			},
			querySelector: (selector) => {
				if (selector === 'video, audio') return {playbackRate};
				if (selector === 'cast-media-player') return castMediaPlayerElement;
				if (selector === 'video') return videoElement;
				return null;
			},
		},
		fetch: fetchImpl || (async (url, options) => {
			fetchCalls.push({url, options});
			return {
				ok: true,
				status: 201,
				text: async () => 'answer-sdp',
			};
		}),
		JSON,
		Math,
		Number,
		RTCPeerConnection: function RTCPeerConnection() {
			const connection = {
				addTransceiver: () => {},
				createOffer: async () => ({type: 'offer', sdp: 'offer-sdp'}),
				setLocalDescription: async (description) => {
					connection.localDescription = description;
				},
				setRemoteDescription: async (description) => {
					connection.remoteDescription = description;
				},
				close: () => {
					connection.closed = true;
				},
				ontrack: null,
				onconnectionstatechange: null,
				connectionState: 'new',
			};
			peerConnections.push(connection);
			return connection;
		},
		RTCSessionDescription: function RTCSessionDescription(description) {
			return description;
		},
		MediaStream: function MediaStream() {
			return {
				tracks: [],
				addTrack(track) {
					this.tracks.push(track);
				},
			};
		},
		setInterval: (callback, delayMs) => {
			intervals.push({callback, delayMs});
			return intervals.length;
		},
	};

	vm.runInNewContext(inlineScript, sandbox);

	const runInterval = (delayMs) => {
		const interval = intervals.find((candidate) => candidate.delayMs === delayMs);
		if (!interval) {
			throw new Error(`Missing interval ${delayMs}`);
		}
		interval.callback();
	};

	const runLoadInterceptor = (loadRequestData) => {
		const interceptor = loadInterceptors.get('LOAD');
		if (!interceptor) {
			throw new Error('Missing LOAD interceptor');
		}
		return interceptor(loadRequestData);
	};

	return {
		get playbackConfig() {
			return playbackConfig;
		},
		get receiverOptions() {
			return receiverOptions;
		},
		sentMessages,
		consoleMessages,
		seekCalls,
		loadCalls,
		setLiveStatus({rangeStart = 0, rangeEnd, currentTime}) {
			liveRange = {start: rangeStart, end: rangeEnd};
			currentTimeSec = currentTime;
		},
		setPlayerState(nextState) {
			playerState = nextState;
		},
		advance(ms) {
			nowMs += ms;
		},
		runLatencyCheck() {
			runInterval(5000);
		},
		runStatusReport() {
			runInterval(1000);
		},
		runLoadInterceptor,
		dispatchCustomMessage(message) {
			const listener = messageListeners.get('urn:x-cast:com.namecallfilter.glacier.cast');
			if (!listener) {
				throw new Error('Missing custom message listener');
			}
			return listener({
				data: message,
				senderId: 'sender-1',
			});
		},
		videoElement,
		castMediaPlayerElement,
		peerConnections,
		fetchCalls,
	};
};

test('configures Shaka for conservative stable HLS live playback', () => {
	const harness = createHarness();

	assert.equal(harness.receiverOptions.useShakaForHls, true);
	assert.equal(harness.playbackConfig.autoResumeNumberOfSegments, 2);
	assert.equal(harness.playbackConfig.enableSmoothLiveRefresh, true);
	assert.equal(harness.playbackConfig.segmentRequestRetryLimit, 5);
	assert.equal(harness.playbackConfig.shakaConfig.streaming.lowLatencyMode, false);
	assert.equal(harness.playbackConfig.shakaConfig.streaming.bufferingGoal, 30);
	assert.equal(harness.playbackConfig.shakaConfig.streaming.rebufferingGoal, 8);
	assert.equal(harness.playbackConfig.shakaConfig.streaming.bufferBehind, 60);
	assert.equal(harness.playbackConfig.shakaConfig.streaming.segmentPrefetchLimit, 0);
	assert.equal(harness.playbackConfig.shakaConfig.streaming.startAtSegmentBoundary, true);
	assert.equal(harness.playbackConfig.shakaConfig.streaming.liveSync.enabled, true);
	assert.equal(harness.playbackConfig.shakaConfig.streaming.liveSync.targetLatency, 20.0);
	assert.equal(harness.playbackConfig.shakaConfig.streaming.liveSync.maxPlaybackRate, 1.03);
	assert.equal(harness.playbackConfig.shakaConfig.streaming.liveSync.minPlaybackRate, 0.97);
	assert.equal(harness.playbackConfig.shakaConfig.streaming.liveSync.panicMode, false);
	assert.equal(harness.playbackConfig.shakaConfig.streaming.liveSync.panicThreshold, 45.0);
	assert.equal(harness.playbackConfig.shakaConfig.manifest.defaultPresentationDelay, 20.0);
	assert.equal(harness.playbackConfig.shakaConfig.manifest.updatePeriod, 2);
});

test('stable HLS does not auto-seek when playback is merely behind live', () => {
	const harness = createHarness();

	harness.setPlayerState('BUFFERING');
	harness.setLiveStatus({rangeEnd: 80, currentTime: 25});
	harness.runLatencyCheck();

	assert.equal(harness.seekCalls.length, 0);
	assert.equal(harness.loadCalls.length, 0);
	assert.ok(
		harness.sentMessages.some((message) =>
			message.mode === 'hls' &&
				message.correction === 'latencyObserved',
		),
	);
});

test('stable HLS only jumps automatically when latency is far outside the safe window', () => {
	const harness = createHarness();

	harness.setPlayerState('BUFFERING');
	harness.setLiveStatus({rangeEnd: 120, currentTime: 30});
	harness.runLatencyCheck();

	assert.equal(harness.seekCalls.length, 1);
	assert.equal(harness.seekCalls[0].currentTime, 100);
	assert.ok(
		harness.consoleMessages.some((message) =>
			message.includes('action=max_latency') &&
				message.includes('latency_ms=90000') &&
				message.includes('emergency=true'),
		),
	);
});

test('stable HLS does not repeatedly reload when playback is behind live', () => {
	const harness = createHarness();
	const loadRequestData = {
		media: {
			contentId: 'http://127.0.0.1:4000/relay/source.m3u8',
		},
	};

	const interceptedLoad = harness.runLoadInterceptor(loadRequestData);

	harness.setPlayerState('BUFFERING');
	harness.setLiveStatus({rangeEnd: 100, currentTime: 45});
	harness.runLatencyCheck();

	assert.equal(harness.seekCalls.length, 0);

	for (let index = 0; index < 3; index += 1) {
		harness.advance(500);
		harness.setLiveStatus({rangeEnd: 100 + index + 1, currentTime: 80});
		harness.runLatencyCheck();
	}

	assert.equal(harness.loadCalls.length, 0);
	assert.equal(interceptedLoad.autoplay, true);
	assert.equal(interceptedLoad.media.streamType, 'LIVE');
});

test('WebRTC mode uses a plain video element and WHEP instead of cast-media-player playback', async () => {
	const harness = createHarness();

	await harness.dispatchCustomMessage({
		type: 'startWebRtc',
		channelLogin: 'streamer',
		title: 'Streamer',
		whepUrl: 'https://media.example.com/streamer/whep',
		gatewayHostedOnPhone: true,
	});

	assert.equal(harness.fetchCalls.length, 1);
	assert.equal(harness.fetchCalls[0].url, 'https://media.example.com/streamer/whep');
	assert.equal(harness.fetchCalls[0].options.method, 'POST');
	assert.equal(harness.fetchCalls[0].options.headers['Content-Type'], 'application/sdp');
	assert.equal(harness.peerConnections.length, 1);
	assert.equal(harness.peerConnections[0].localDescription.sdp, 'offer-sdp');
	assert.equal(harness.peerConnections[0].remoteDescription.type, 'answer');
	assert.notEqual(harness.videoElement.srcObject, null);
	assert.equal(harness.castMediaPlayerElement.style.display, 'none');
	assert.ok(
		harness.sentMessages.some((message) =>
				message.mode === 'webrtc' &&
				message.playerState === 'connecting' &&
				message.gatewayHostedOnPhone === true,
		),
	);
});

test('WebRTC mode reports a clear failure when WHEP setup fails', async () => {
	const harness = createHarness();

	harness.fetchCalls.length = 0;
	await harness.dispatchCustomMessage({
		type: 'startWebRtc',
		channelLogin: 'streamer',
		title: 'Streamer',
		whepUrl: '',
	});

	assert.ok(
		harness.sentMessages.some((message) =>
			message.mode === 'webrtc' &&
				message.playerState === 'failed' &&
				message.error.includes('Missing WHEP URL'),
		),
	);
});

test('WebRTC mode explains phone-hosted gateway reachability failures', async () => {
	const harness = createHarness({
		fetchImpl: async () => {
			throw new TypeError('Failed to fetch');
		},
	});

	await harness.dispatchCustomMessage({
		type: 'startWebRtc',
		channelLogin: 'streamer',
		title: 'Streamer',
		whepUrl: 'http://192.168.5.42:8889/streamer/whep',
		gatewayHostedOnPhone: true,
	});

	assert.ok(
		harness.sentMessages.some((message) =>
			message.mode === 'webrtc' &&
				message.playerState === 'failed' &&
				message.error.includes('Phone WebRTC gateway is unreachable'),
		),
	);
});

test('WebRTC mode includes WHEP response error details', async () => {
	const harness = createHarness({
		fetchImpl: async (url, options) => {
			harness.fetchCalls.push({url, options});
			return {
				ok: false,
				status: 400,
				text: async () => JSON.stringify({
					status: 'error',
					error: 'error getting local interfaces: route ip+net: netlinkrib: permission denied',
				}),
			};
		},
	});

	await harness.dispatchCustomMessage({
		type: 'startWebRtc',
		channelLogin: 'streamer',
		title: 'Streamer',
		whepUrl: 'http://192.168.5.42:8889/streamer/whep',
		gatewayHostedOnPhone: true,
	});

	assert.ok(
		harness.sentMessages.some((message) =>
			message.mode === 'webrtc' &&
				message.playerState === 'failed' &&
				message.error.includes('WHEP request failed with status 400') &&
				message.error.includes('error getting local interfaces'),
		),
	);
});

test('does not keep old custom stall recovery logic', () => {
	assert.equal(receiverHtml.includes('STALL_RECOVERY_'), false);
	assert.equal(receiverHtml.includes('isPlaybackStalled'), false);
	assert.equal(receiverHtml.includes('recoverStalledPlayback'), false);
	assert.equal(receiverHtml.includes('jumpToLiveWithCooldown'), false);
});
