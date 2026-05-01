// Tech Flow Runner — game logic.
// Extracted from index.html. Loaded as a classic script.

(function () {
  'use strict';

  const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  const SETTINGS_KEY = 'techFlowRunnerSettings';
  const BEST_KEY = 'techFlowRunnerBest';

  function loadSettings() {
    try {
      const raw = localStorage.getItem(SETTINGS_KEY);
      if (!raw) return {};
      const parsed = JSON.parse(raw);
      return parsed && typeof parsed === 'object' ? parsed : {};
    } catch {
      return {};
    }
  }

  function saveSettings(patch) {
    try {
      const next = { ...loadSettings(), ...patch };
      localStorage.setItem(SETTINGS_KEY, JSON.stringify(next));
    } catch {
      /* storage unavailable; ignore */
    }
  }

  const settings = loadSettings();

  const LIFETIME_KEY = 'techFlowRunnerLifetime';
  function loadLifetime() {
    try {
      const raw = localStorage.getItem(LIFETIME_KEY);
      const parsed = raw ? JSON.parse(raw) : {};
      return {
        distance: Number(parsed.distance) || 0,
        bits: Number(parsed.bits) || 0,
        runs: Number(parsed.runs) || 0,
        bossKills: Number(parsed.bossKills) || 0,
      };
    } catch {
      return { distance: 0, bits: 0, runs: 0, bossKills: 0 };
    }
  }
  function saveLifetime(stats) {
    try {
      localStorage.setItem(LIFETIME_KEY, JSON.stringify(stats));
    } catch {
      /* ignore */
    }
  }
  const lifetime = loadLifetime();

  const canvas = document.getElementById('game');
  const ctx = canvas.getContext('2d');
  const scoreEl = document.getElementById('score');
  const speedEl = document.getElementById('speed');
  const bestEl = document.getElementById('best');
  const bitsEl = document.getElementById('bits');
  const comboEl = document.getElementById('combo');
  const levelEl = document.getElementById('level');
  const powerupBar = document.getElementById('powerupBar');
  const music = document.getElementById('bgm');
  const musicBtn = document.getElementById('musicBtn');
  const gameOverOverlay = document.getElementById('gameOverOverlay');
  const pauseOverlay = document.getElementById('pauseOverlay');
  const pauseResumeBtn = document.getElementById('pauseResumeBtn');
  const pauseMenuBtn = document.getElementById('pauseMenuBtn');
  const leaderboardStatus = document.getElementById('leaderboardStatus');
  const leaderboardList = document.getElementById('leaderboardList');
  const leaderboardEndpoint = './leaderboard.php';
  const scoreModal = document.getElementById('scoreModal');
  const scoreModalDist = document.getElementById('scoreModalDist');
  const scoreModalName = document.getElementById('scoreModalName');
  const scoreModalSubmit = document.getElementById('scoreModalSubmit');
  const scoreModalSkip = document.getElementById('scoreModalSkip');
  const scoreModalStatus = document.getElementById('scoreModalStatus');
  const startOverlay = document.getElementById('startOverlay');
  const startBtn = document.getElementById('startBtn');
  const dailyToggle = document.getElementById('dailyToggle');
  const modifierSelect = document.getElementById('modifierSelect');
  const skinSelect = document.getElementById('skinSelect');
  const unlockHint = document.getElementById('unlockHint');

  // ---------- Seedable RNG ----------
  // Mulberry32. When `dailySeed` is on, all gameplay randomness derives from
  // the day's seed so every player runs the same course.
  let rngState = 0;
  function setRngSeed(seed) {
    rngState = seed | 0 || 1;
  }
  function rng() {
    rngState |= 0;
    rngState = (rngState + 0x6d2b79f5) | 0;
    let t = rngState;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  }
  let useSeededRng = false;
  function gameRandom() {
    return useSeededRng ? rng() : Math.random();
  }
  function localDailySeedFallback() {
    const d = new Date();
    return d.getUTCFullYear() * 10000 + (d.getUTCMonth() + 1) * 100 + d.getUTCDate();
  }
  // Cached server-issued daily seed: { date: 'YYYY-MM-DD', seed: <int> }.
  // The server persists today's seed in dailyseed.txt so every player —
  // including incognito sessions and different browsers — gets the same value.
  let dailySeedCache = null;
  let dailySeedFetch = null;
  async function fetchDailySeed() {
    const response = await fetch('/api/daily-seed', { cache: 'no-store' });
    if (!response.ok) throw new Error(`Daily seed request failed (HTTP ${response.status})`);
    const payload = await response.json();
    if (!payload || typeof payload.seed !== 'number' || typeof payload.date !== 'string') {
      throw new Error('Daily seed response was malformed.');
    }
    return { date: payload.date, seed: payload.seed | 0 || 1 };
  }
  function todayUtcDateString() {
    const d = new Date();
    const y = d.getUTCFullYear();
    const m = String(d.getUTCMonth() + 1).padStart(2, '0');
    const day = String(d.getUTCDate()).padStart(2, '0');
    return `${y}-${m}-${day}`;
  }
  async function ensureDailySeed() {
    const today = todayUtcDateString();
    if (dailySeedCache && dailySeedCache.date === today) return dailySeedCache;
    if (!dailySeedFetch) {
      dailySeedFetch = fetchDailySeed()
        .then((value) => {
          dailySeedCache = value;
          return value;
        })
        .catch((error) => {
          dailySeedCache = null;
          throw error;
        })
        .finally(() => {
          dailySeedFetch = null;
        });
    }
    return dailySeedFetch;
  }
  function dailySeedValue() {
    if (dailySeedCache && dailySeedCache.date === todayUtcDateString()) {
      return dailySeedCache.seed;
    }
    // Fallback if the server is unreachable. ensureDailySeed() should be
    // awaited before starting a daily run so this branch is only hit when
    // offline.
    return localDailySeedFallback();
  }

  let gameStarted = false;
  let paused = false;
  let rafId = null;
  let score = 0;
  let best = Number(localStorage.getItem(BEST_KEY) || 0);
  let speedMult = 1;
  let baseSpeed = 4.2;
  let gameOver = false;
  let groundOffset = 0;
  let sceneryOffset = 0;
  let spawnTimer = 0;
  let worldOffset = 0;
  let latestRunScore = 0;
  // Modifier captured at the moment the run ended. Used at submission time so
  // changing the menu picker after death doesn't mis-categorize the score.
  let latestRunModifier = 'none';
  let lastSpawnAction = null;
  let queuedSpawnAction = null;
  // Frames elapsed since the last obstacle was placed. Tracking in frames
  // (not pixels) keeps the reaction-time budget honest as world speed grows.
  let framesSinceLastSpawn = Number.POSITIVE_INFINITY;

  // ---------- Run extras (bits, combo, level, modifier, FX) ----------
  let bitsCollected = 0;
  let combo = 1;
  let comboTimer = 0;
  let level = 1;
  let nextLevelAt = 1500;
  const LEVEL_INTERVAL = 1500;
  const BOSS_INTERVAL = 4500;
  let nextBossAt = BOSS_INTERVAL;
  let activeModifier = 'none';
  let activeSkin = 'default';
  let dailySeedActive = false;
  const bits = [];
  const powerupItems = [];
  const particles = [];
  const projectiles = [];
  let boss = null;
  let bossSpawnsSuppressed = 0;
  let nearMissCooldown = 0;
  let shakeFrames = 0;
  let shakeIntensity = 0;
  let hitstopFrames = 0;
  let levelBannerFrames = 0;
  let levelBannerText = '';
  // Active power-up timers (frames remaining)
  const pwr = { shield: 0, overclock: 0, magnet: 0, slowmo: 0 };
  // Player input-feel state
  let coyoteFrames = 0;
  let jumpBufferFrames = 0;
  let isDucking = false;
  let dashFrames = 0;
  let dashCooldown = 0;
  let wallRunFrames = 0;
  let wallRunCooldown = 0;
  // Per-frame world speed (applied to ground/obstacles, separate from baseSpeed*speedMult).
  let speedMultiplier = 1; // includes overclock / slowmo / dash blend.

  const gravity = 0.75;
  const player = {
    x: 120,
    y: 0,
    w: 48,
    h: 58,
    vy: 0,
    jumpPower: -14,
    onGround: true,
    jumpsLeft: 2,
  };
  const baseGroundY = canvas.height - 72;
  const precipiceFloorY = canvas.height - 1;
  player.y = baseGroundY - player.h;

  const obstacles = [];
  const transitionFrameBudget = {
    start: { jump: 24, stay: 20 },
    jump: { jump: 22, stay: 44 },
    stay: { jump: 26, stay: 18 },
  };
  const courseSafety = {
    minTakeoffBuffer: 96,
    minTakeoffBufferForStay: 176,
    minLandingBuffer: 162,
    minLandingBufferForStay: 220,
    minCaveHeadroom: player.h + 14,
    minCaveHeadroomForJumpObstacle: 168,
    minCaveHeadroomForAnyObstacle: 112,
    jumpObstacleCaveApproachBuffer: 72,
    maxDownhillBeforeJumpObstacle: 34,
    maxDownhillAfterStayObstacle: 24,
    maxDownhillBeforeDrone: 36,
    maxDownhillBeforeDroneInCave: 22,
    stayObstacleRunoutDistance: 154,
    minJumpClearance: player.h + 138,
    clearanceSampleStep: 8,
    maxPrecipiceWidth: 136,
    precipiceAvoidanceBuffer: 80,
    obstacleSpacingBuffer: 28,
    minObstacleGapPx: {
      jump: { jump: 170, stay: 132 },
      stay: { jump: 140, stay: 116 },
    },
    minObstacleGapPxInCave: {
      jump: { jump: 230, stay: 168 },
      stay: { jump: 188, stay: 140 },
    },
  };

  // ---------- Audio ----------

  let audioCtx = null;
  let muted = settings.muted === true;

  function getAudioContext() {
    if (audioCtx) return audioCtx;
    const Ctor = window.AudioContext || window.webkitAudioContext;
    if (!Ctor) return null;
    try {
      audioCtx = new Ctor();
    } catch {
      audioCtx = null;
    }
    return audioCtx;
  }

  function playTone(frequency, duration, type = 'square', gain = 0.08) {
    if (muted) return;
    const ac = getAudioContext();
    if (!ac) return;
    if (ac.state === 'suspended') ac.resume();
    const osc = ac.createOscillator();
    const g = ac.createGain();
    osc.type = type;
    osc.frequency.value = frequency;
    g.gain.value = gain;
    osc.connect(g).connect(ac.destination);
    const now = ac.currentTime;
    g.gain.setValueAtTime(gain, now);
    g.gain.exponentialRampToValueAtTime(0.0001, now + duration);
    osc.start(now);
    osc.stop(now + duration);
  }

  const sfx = {
    jump: () => playTone(620, 0.09, 'square', 0.06),
    djump: () => playTone(820, 0.09, 'square', 0.06),
    death: () => {
      playTone(180, 0.4, 'sawtooth', 0.09);
      setTimeout(() => playTone(90, 0.5, 'sawtooth', 0.07), 90);
    },
  };

  function setMusicButtonState(label) {
    musicBtn.textContent = label;
    // aria-pressed reflects whether music is currently playing (not muted).
    musicBtn.setAttribute('aria-pressed', String(!muted && !music.paused));
  }

  function applyMusicMuted() {
    music.muted = muted;
    if (muted && !music.paused) music.pause();
  }

  function tryPlayMusic() {
    if (muted) return;
    music.volume = 0.55;
    music
      .play()
      .then(() => {
        setMusicButtonState('Music On');
      })
      .catch(() => {
        setMusicButtonState('Tap to Enable Music');
      });
  }

  musicBtn.addEventListener('click', () => {
    if (muted) {
      muted = false;
      saveSettings({ muted: false });
      applyMusicMuted();
      tryPlayMusic();
      return;
    }
    if (!music.paused) {
      music.pause();
      muted = true;
      saveSettings({ muted: true });
      setMusicButtonState('Play Music');
    } else {
      tryPlayMusic();
    }
  });

  applyMusicMuted();
  setMusicButtonState(muted ? 'Play Music' : musicBtn.textContent);

  const sfxExt = {
    bit: () => playTone(1100, 0.05, 'sine', 0.05),
    combo: () => playTone(1500, 0.07, 'triangle', 0.06),
    powerup: () => {
      playTone(660, 0.07, 'square', 0.05);
      setTimeout(() => playTone(990, 0.09, 'square', 0.05), 70);
    },
    shield: () => {
      playTone(440, 0.18, 'square', 0.07);
      setTimeout(() => playTone(880, 0.18, 'square', 0.07), 80);
    },
    levelup: () => {
      playTone(520, 0.1, 'square', 0.07);
      setTimeout(() => playTone(780, 0.12, 'square', 0.07), 90);
      setTimeout(() => playTone(1040, 0.14, 'square', 0.07), 200);
    },
    boss: () => {
      playTone(110, 0.4, 'sawtooth', 0.08);
      setTimeout(() => playTone(75, 0.5, 'sawtooth', 0.07), 200);
    },
    bossDie: () => {
      playTone(880, 0.18, 'square', 0.08);
      setTimeout(() => playTone(1320, 0.2, 'square', 0.08), 100);
      setTimeout(() => playTone(1760, 0.25, 'square', 0.08), 220);
    },
    dash: () => playTone(560, 0.08, 'sawtooth', 0.06),
    laser: () => playTone(220, 0.12, 'sawtooth', 0.05),
  };

  // ---------- Modifiers ----------
  const MODIFIERS = {
    none: {
      label: 'None',
      scoreMult: 1.0,
      noDoubleJump: false,
      bitsMult: 1,
      gravityMult: 1,
      allowShield: true,
    },
    hardcore: {
      label: 'Hardcore',
      scoreMult: 1.5,
      noDoubleJump: true,
      bitsMult: 1,
      gravityMult: 1,
      allowShield: true,
    },
    bitrush: {
      label: 'Bit Rush',
      scoreMult: 1.2,
      noDoubleJump: false,
      bitsMult: 2,
      gravityMult: 1,
      allowShield: false,
    },
    featherfall: {
      label: 'Feather Fall',
      scoreMult: 1.25,
      noDoubleJump: false,
      bitsMult: 1,
      gravityMult: 0.6,
      allowShield: true,
    },
    glasscannon: {
      label: 'Glass Cannon',
      scoreMult: 1.75,
      noDoubleJump: false,
      bitsMult: 1,
      gravityMult: 1,
      allowShield: false,
    },
  };
  function getMod() {
    return MODIFIERS[activeModifier] || MODIFIERS.none;
  }

  // ---------- Skins ----------
  const SKINS = {
    default: { label: 'Pulse', unlock: 0, check: () => true, colors: ['#2ef8ff', '#8e5cff'] },
    sunset: {
      label: 'Sunset (1km)',
      unlock: 1000,
      check: () => lifetime.distance >= 1000,
      colors: ['#ffd95c', '#ff5a7c'],
    },
    matrix: {
      label: 'Matrix (2.5km)',
      unlock: 2500,
      check: () => lifetime.distance >= 2500,
      colors: ['#75ffd4', '#16f06b'],
    },
    plasma: {
      label: 'Plasma (5km)',
      unlock: 5000,
      check: () => lifetime.distance >= 5000,
      colors: ['#ff5cd1', '#8e5cff'],
    },
    bitlord: {
      label: 'Bit Lord (500B)',
      unlock: 500,
      check: () => lifetime.bits >= 500,
      colors: ['#ffd95c', '#2ef8ff'],
    },
    bossbane: {
      label: 'Bossbane (3 bosses)',
      unlock: 3,
      check: () => lifetime.bossKills >= 3,
      colors: ['#ff5a7c', '#ffd95c'],
    },
  };
  function isSkinUnlocked(key) {
    const skin = SKINS[key];
    return skin ? skin.check() : false;
  }
  function getSkinColors() {
    const skin =
      SKINS[activeSkin] && isSkinUnlocked(activeSkin) ? SKINS[activeSkin] : SKINS.default;
    return skin.colors;
  }

  function populateSkinSelect() {
    if (!skinSelect) return;
    skinSelect.innerHTML = '';
    Object.entries(SKINS).forEach(([key, skin]) => {
      const opt = document.createElement('option');
      opt.value = key;
      opt.textContent = skin.label + (isSkinUnlocked(key) ? '' : ' (locked)');
      opt.disabled = !isSkinUnlocked(key);
      skinSelect.appendChild(opt);
    });
    activeSkin = settings.skin && isSkinUnlocked(settings.skin) ? settings.skin : 'default';
    skinSelect.value = activeSkin;
    if (unlockHint) {
      const unlocked = Object.keys(SKINS).filter(isSkinUnlocked).length;
      const total = Object.keys(SKINS).length;
      unlockHint.textContent = `Skins unlocked: ${unlocked}/${total} · Lifetime: ${Math.floor(lifetime.distance)}m, ${lifetime.bits} bits, ${lifetime.bossKills} bosses defeated`;
    }
  }

  // ---------- Game over UI ----------

  document.getElementById('gameOverRebootBtn').addEventListener('click', resetGame);
  document.getElementById('gameOverSubmitBtn').addEventListener('click', openScoreModal);
  const gameOverMenuBtn = document.getElementById('gameOverMenuBtn');
  if (gameOverMenuBtn) {
    gameOverMenuBtn.addEventListener('click', returnToStartMenu);
  }

  const ariaLive = document.getElementById('ariaLive');

  function announce(message) {
    if (!ariaLive) return;
    // Clear-then-set forces some screen readers to re-announce identical text.
    ariaLive.textContent = '';
    ariaLive.textContent = message;
  }

  function setLeaderboardStatus(message) {
    leaderboardStatus.textContent = message;
  }

  function setScoreSubmissionState(isEnabled) {
    document.getElementById('gameOverSubmitBtn').disabled = !isEnabled;
  }

  // Display order + labels for the leaderboard category sections. Keep 'og'
  // first so legacy distance-only scores stay visible as their own bucket.
  const LEADERBOARD_CATEGORIES = [
    { key: 'og', label: 'OG (Original)' },
    { key: 'none', label: 'None' },
    { key: 'hardcore', label: 'Hardcore' },
    { key: 'bitrush', label: 'Bit Rush' },
    { key: 'featherfall', label: 'Feather Fall' },
    { key: 'glasscannon', label: 'Glass Cannon' },
  ];

  function bucketEntriesByModifier(entries) {
    const buckets = {};
    LEADERBOARD_CATEGORIES.forEach(({ key }) => {
      buckets[key] = [];
    });
    (entries || []).forEach((entry) => {
      const key = buckets[entry && entry.modifier] ? entry.modifier : 'og';
      buckets[key].push(entry);
    });
    Object.keys(buckets).forEach((key) => {
      buckets[key].sort((a, b) => {
        if (b.score !== a.score) return b.score - a.score;
        return String(a.savedAt).localeCompare(String(b.savedAt));
      });
      buckets[key] = buckets[key].slice(0, 10);
    });
    return buckets;
  }

  function renderLeaderboard(payload) {
    leaderboardList.innerHTML = '';
    // Accept either { categories: {...} } from the server or a flat array
    // of entries (older payloads). Always re-bucket client-side so the UI
    // stays consistent if the server ever returns extras.
    const flatEntries = Array.isArray(payload)
      ? payload
      : (payload && Array.isArray(payload.entries) ? payload.entries : []);
    const fromServer = payload && payload.categories && typeof payload.categories === 'object'
      ? payload.categories
      : null;
    const buckets = fromServer
      ? LEADERBOARD_CATEGORIES.reduce((acc, { key }) => {
          const arr = Array.isArray(fromServer[key]) ? fromServer[key].slice(0, 10) : [];
          acc[key] = arr;
          return acc;
        }, {})
      : bucketEntriesByModifier(flatEntries);

    const totalEntries = LEADERBOARD_CATEGORIES.reduce(
      (sum, { key }) => sum + (buckets[key] ? buckets[key].length : 0),
      0,
    );
    if (totalEntries === 0) {
      const item = document.createElement('li');
      item.className = 'leaderboard-empty';
      item.textContent = 'No scores yet. Be the first to upload a run!';
      leaderboardList.appendChild(item);
      return;
    }

    LEADERBOARD_CATEGORIES.forEach(({ key, label }) => {
      const entries = buckets[key] || [];
      const section = document.createElement('li');
      section.className = 'leaderboard-category';

      const heading = document.createElement('h3');
      heading.className = 'leaderboard-category-title';
      heading.textContent = label;
      section.appendChild(heading);

      if (entries.length === 0) {
        const empty = document.createElement('p');
        empty.className = 'leaderboard-category-empty';
        empty.textContent = 'No scores yet.';
        section.appendChild(empty);
      } else {
        const list = document.createElement('ol');
        list.className = 'leaderboard-category-list';
        entries.forEach((entry, index) => {
          const row = document.createElement('li');
          row.textContent = `#${index + 1} ${entry.name} — ${Math.floor(entry.score)} pts`;
          list.appendChild(row);
        });
        section.appendChild(list);
      }

      leaderboardList.appendChild(section);
    });
  }

  async function fetchLeaderboard() {
    try {
      const response = await fetch(leaderboardEndpoint, { cache: 'no-store' });
      if (!response.ok) {
        throw new Error(`Leaderboard request failed (HTTP ${response.status})`);
      }
      const payload = await response.json();
      renderLeaderboard(payload);
      if (!gameStarted) {
        setLeaderboardStatus('Finish a run, then save your score to the global board.');
      }
    } catch (error) {
      renderLeaderboard([]);
      if (error instanceof TypeError) {
        setLeaderboardStatus('Network unavailable. Check your connection and try again.');
      } else if (error instanceof SyntaxError) {
        setLeaderboardStatus('Leaderboard returned an invalid response. Please retry shortly.');
      } else {
        setLeaderboardStatus(
          'Global leaderboard unavailable. Ensure leaderboard.php is deployed and writable.'
        );
      }
    }
  }

  async function fetchSubmitNonce() {
    const response = await fetch(`${leaderboardEndpoint}?action=nonce`, { cache: 'no-store' });
    if (!response.ok) throw new Error('Could not start a score submission.');
    const payload = await response.json();
    if (!payload || typeof payload.nonce !== 'string') {
      throw new Error('Score submission unavailable.');
    }
    return payload.nonce;
  }

  // Server enforces a min-age (~4s) before a nonce can be consumed. Prime as
  // early as possible (game over) and, if the user still beats the timer, wait
  // out the remaining age client-side before posting.
  const NONCE_MIN_AGE_MS = 4500;
  let pendingSubmitNonce = null;
  let pendingSubmitNonceIssuedAt = 0;

  function primeSubmitNonce() {
    // Stamp issuedAt only after the GET resolves so the server-side delta is
    // never less than what the client measures — otherwise a slow GET (cold
    // start, slow network) eats into the 4s min-age budget and the server
    // rejects the POST as too young.
    const promise = fetchSubmitNonce().then(
      (nonce) => {
        if (pendingSubmitNonce === promise) {
          pendingSubmitNonceIssuedAt = Date.now();
        }
        return nonce;
      },
      (error) => {
        if (pendingSubmitNonce === promise) {
          pendingSubmitNonce = null;
          pendingSubmitNonceIssuedAt = 0;
        }
        throw error;
      },
    );
    pendingSubmitNonce = promise;
    pendingSubmitNonceIssuedAt = 0;
  }

  async function takeSubmitNonce() {
    if (!pendingSubmitNonce) primeSubmitNonce();
    const promise = pendingSubmitNonce;
    try {
      const nonce = await promise;
      const elapsed = Date.now() - pendingSubmitNonceIssuedAt;
      if (elapsed < NONCE_MIN_AGE_MS) {
        await new Promise((resolve) => setTimeout(resolve, NONCE_MIN_AGE_MS - elapsed));
      }
      return nonce;
    } finally {
      if (pendingSubmitNonce === promise) {
        pendingSubmitNonce = null;
        pendingSubmitNonceIssuedAt = 0;
      }
    }
  }

  async function submitScore(name, runPoints, runModifier, nonce) {
    const body = JSON.stringify({
      name,
      points: runPoints,
      score: runPoints,
      modifier: runModifier,
      nonce,
    });

    const response = await fetch(leaderboardEndpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body,
    });

    let payload;
    try {
      payload = await response.json();
    } catch (parseError) {
      if (parseError instanceof SyntaxError) {
        throw new Error('Server returned an invalid response. Please try again.');
      }
      throw parseError;
    }
    if (!response.ok) {
      throw new Error((payload && payload.error) || 'Unable to save score.');
    }

    // Pass the whole payload through so the renderer can use categories when
    // the server provides them, falling back to flat entries otherwise.
    return payload;
  }

  let scoreModalLastFocus = null;

  function getScoreModalFocusables() {
    return Array.from(
      scoreModal.querySelectorAll('input, button, [tabindex]:not([tabindex="-1"])')
    ).filter((el) => !el.disabled && el.offsetParent !== null);
  }

  function trapScoreModalFocus(event) {
    if (scoreModal.hidden) return;
    if (event.key === 'Escape') {
      event.preventDefault();
      closeScoreModal();
      setLeaderboardStatus(`Run ended at ${latestRunScore} pts. Press R to reboot.`);
      return;
    }
    if (event.key !== 'Tab') return;
    const focusables = getScoreModalFocusables();
    if (focusables.length === 0) return;
    const first = focusables[0];
    const last = focusables[focusables.length - 1];
    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault();
      first.focus();
    }
  }

  function openScoreModal() {
    if (!scoreModal.hidden) return;
    scoreModalLastFocus = document.activeElement;
    scoreModalStatus.textContent = '';
    scoreModalName.value = settings.lastName || '';
    const modLabel = (MODIFIERS[latestRunModifier] && MODIFIERS[latestRunModifier].label) || 'None';
    scoreModalDist.textContent = `Points: ${latestRunScore} · Modifier: ${modLabel}`;
    scoreModalSubmit.disabled = false;
    scoreModal.hidden = false;
    document.addEventListener('keydown', trapScoreModalFocus);
    scoreModalName.focus();
    primeSubmitNonce();
  }

  function closeScoreModal() {
    if (scoreModal.hidden) return;
    scoreModal.hidden = true;
    document.removeEventListener('keydown', trapScoreModalFocus);
    if (scoreModalLastFocus && typeof scoreModalLastFocus.focus === 'function') {
      try {
        scoreModalLastFocus.focus();
      } catch {
        /* ignore — element may have been removed */
      }
    }
    scoreModalLastFocus = null;
  }

  scoreModalSkip.addEventListener('click', () => {
    closeScoreModal();
    setLeaderboardStatus(`Run ended at ${latestRunScore}m. Press R to reboot.`);
  });

  scoreModalSubmit.addEventListener('click', async () => {
    const name = scoreModalName.value.trim();
    if (!name) {
      scoreModalStatus.textContent = 'Please enter your name first.';
      return;
    }

    const scoreToSave = Math.floor(latestRunScore);
    scoreModalSubmit.disabled = true;
    scoreModalStatus.textContent = 'Saving your score...';

    try {
      const nonce = await takeSubmitNonce();
      const submitModifier = MODIFIERS[latestRunModifier] ? latestRunModifier : 'none';
      const payload = await submitScore(name, scoreToSave, submitModifier, nonce);
      renderLeaderboard(payload);
      setLeaderboardStatus(`Saved ${scoreToSave} pts for ${name}. Reboot and beat it!`);
      announce(`Score saved: ${scoreToSave} points for ${name}.`);
      setScoreSubmissionState(false);
      saveSettings({ lastName: name });
      closeScoreModal();
    } catch (error) {
      const message = (error && error.message) || 'Unable to save your score.';
      scoreModalStatus.textContent = message;
      announce(message);
      scoreModalSubmit.disabled = false;
      // Re-prime so the retry has an aged nonce ready to go.
      primeSubmitNonce();
    }
  });

  scoreModalName.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') {
      e.preventDefault();
      scoreModalSubmit.click();
    }
  });

  // ---------- Terrain ----------

  const terrain = {
    step: 34,
    points: [],
    caves: [],
    precipices: [],
    lastX: 0,
    currentY: baseGroundY,
    slope: 0,
    nextPrecipiceAt: 420,
    nextCaveAt: 360,
  };

  function rand(min, max) {
    return min + gameRandom() * (max - min);
  }

  function clamp(value, min, max) {
    return Math.max(min, Math.min(max, value));
  }

  function isInPrecipice(worldX) {
    return terrain.precipices.some((drop) => worldX >= drop.start && worldX <= drop.end);
  }

  function getCaveAt(worldX) {
    return terrain.caves.find((cave) => worldX >= cave.start && worldX <= cave.end) || null;
  }

  function getCaveCeilingAt(worldX) {
    const cave = getCaveAt(worldX);
    if (!cave) return null;
    const wave = Math.sin(worldX * 0.04 + cave.phase) * cave.amplitude;
    return cave.baseCeiling + wave;
  }

  function getPrecipiceNear(worldX, padding = 0) {
    return (
      terrain.precipices.find(
        (drop) => worldX >= drop.start - padding && worldX <= drop.end + padding
      ) || null
    );
  }

  function getRequiredGroundForJumpClearance(worldX) {
    const caveCeilingY = getCaveCeilingAt(worldX);
    if (caveCeilingY == null) return null;
    return caveCeilingY + courseSafety.minJumpClearance;
  }

  function enforceJumpClearanceOnSegment(previousPoint, nextPointX, nextPointY) {
    if (!previousPoint) return nextPointY;

    let adjustedNextY = nextPointY;
    const segmentWidth = nextPointX - previousPoint.x;
    if (segmentWidth <= 0) return adjustedNextY;

    function enforceAtSample(sampleX) {
      const requiredGroundY = getRequiredGroundForJumpClearance(sampleX);
      if (requiredGroundY == null) return;

      const t = (sampleX - previousPoint.x) / segmentWidth;
      if (t <= 0) return;

      const sampleGroundY = previousPoint.y + (adjustedNextY - previousPoint.y) * t;
      if (sampleGroundY >= requiredGroundY) return;

      const requiredNextY = previousPoint.y + (requiredGroundY - previousPoint.y) / t;
      adjustedNextY = Math.max(adjustedNextY, requiredNextY);
    }

    for (
      let sampleX = previousPoint.x + courseSafety.clearanceSampleStep;
      sampleX < nextPointX;
      sampleX += courseSafety.clearanceSampleStep
    ) {
      enforceAtSample(sampleX);
    }
    enforceAtSample(nextPointX);

    return adjustedNextY;
  }

  function findTerrainSegmentIndex(worldX) {
    const points = terrain.points;
    if (points.length < 2) return 0;
    if (worldX <= points[0].x) return 0;

    let low = 0;
    let high = points.length - 2;
    while (low <= high) {
      const mid = Math.floor((low + high) * 0.5);
      const nextPointX = points[mid + 1].x;
      if (nextPointX < worldX) {
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }

    return clamp(low, 0, points.length - 2);
  }

  function getTerrainHeight(worldX) {
    if (isInPrecipice(worldX)) {
      return precipiceFloorY;
    }

    const points = terrain.points;
    const i = findTerrainSegmentIndex(worldX);
    const p1 = points[i];
    const p2 = points[Math.min(i + 1, points.length - 1)];
    if (!p1 || !p2) return baseGroundY;
    if (p1.x === p2.x) return p1.y;
    const t = (worldX - p1.x) / (p2.x - p1.x);
    return p1.y + (p2.y - p1.y) * t;
  }

  function applySpawnGap(gapPx, moveSpeed) {
    spawnTimer = (gapPx / moveSpeed) * (1000 / 60);
  }

  function ensureTerrainAhead(maxWorldX) {
    while (terrain.lastX < maxWorldX) {
      terrain.lastX += terrain.step;

      if (terrain.lastX > terrain.nextPrecipiceAt) {
        const precipiceStart = terrain.lastX + rand(40, 150);
        const precipiceWidth = rand(80, courseSafety.maxPrecipiceWidth);
        terrain.precipices.push({ start: precipiceStart, end: precipiceStart + precipiceWidth });
        terrain.nextPrecipiceAt = precipiceStart + rand(460, 780);
      }

      if (terrain.lastX > terrain.nextCaveAt) {
        const start = terrain.lastX + rand(60, 140);
        const length = rand(240, 430);
        const ceiling = rand(70, 140);
        terrain.caves.push({
          start,
          end: start + length,
          baseCeiling: ceiling,
          amplitude: rand(8, 18),
          phase: rand(0, Math.PI * 2),
        });
        terrain.nextCaveAt = start + rand(520, 880);
      }

      terrain.slope += rand(-0.36, 0.36);
      terrain.slope = clamp(terrain.slope, -1.8, 1.8);
      terrain.currentY += terrain.slope * terrain.step * 0.25;
      terrain.currentY += (baseGroundY - terrain.currentY) * 0.04;
      terrain.currentY = clamp(terrain.currentY, baseGroundY - 110, baseGroundY + 44);

      if (gameRandom() < 0.09) {
        terrain.currentY += rand(-26, 22);
        terrain.currentY = clamp(terrain.currentY, baseGroundY - 110, baseGroundY + 44);
      }

      const previousPoint = terrain.points[terrain.points.length - 1];
      terrain.currentY = enforceJumpClearanceOnSegment(
        previousPoint,
        terrain.lastX,
        terrain.currentY
      );
      terrain.currentY = clamp(terrain.currentY, baseGroundY - 110, baseGroundY + 44);

      terrain.points.push({ x: terrain.lastX, y: terrain.currentY });
    }
  }

  function initTerrain() {
    terrain.points.length = 0;
    terrain.caves.length = 0;
    terrain.precipices.length = 0;
    terrain.lastX = 0;
    terrain.currentY = baseGroundY;
    terrain.slope = 0;
    terrain.nextPrecipiceAt = 420;
    terrain.nextCaveAt = 360;
    terrain.points.push({ x: 0, y: baseGroundY });
    ensureTerrainAhead(canvas.width * 2);
  }

  // ---------- Obstacles ----------

  function createObstacle(action, worldX) {
    let groundY = getTerrainHeight(worldX);
    if (isInPrecipice(worldX)) {
      const precipice = terrain.precipices.find((seg) => worldX >= seg.start && worldX <= seg.end);
      worldX = (precipice ? precipice.end : worldX) + 50;
      groundY = getTerrainHeight(worldX);
    }

    if (action === 'stay') {
      return { worldX, y: groundY - 138, w: 72, h: 22, type: 'drone', action: 'stay' };
    }

    const typeRoll = gameRandom();
    if (typeRoll < 0.34) {
      return { worldX, y: groundY - 20, w: 28, h: 20, type: 'bug', action: 'jump' };
    }
    if (typeRoll < 0.67) {
      return { worldX, y: groundY - 52, w: 36, h: 52, type: 'server', action: 'jump' };
    }
    return { worldX, y: groundY - 24, w: 62, h: 24, type: 'laser', action: 'jump' };
  }

  function pickRandomAction() {
    return gameRandom() < 0.24 ? 'stay' : 'jump';
  }

  function getSpawnDelayMs(previousAction, nextAction) {
    const moveSpeed = baseSpeed * speedMult;
    const baselineFrames = Math.round(23 + gameRandom() * 35);
    const randomGapPx = baselineFrames * moveSpeed;
    const minGapPx = getMinGapPx(previousAction, nextAction);
    const maxGapPx = minGapPx + moveSpeed * (16 + gameRandom() * 18);
    const gapPx = Math.max(minGapPx, Math.min(randomGapPx, maxGapPx));
    return (gapPx / moveSpeed) * (1000 / 60);
  }

  function getMinGapPx(previousAction, nextAction) {
    const moveSpeed = baseSpeed * speedMult;
    const prevKey = previousAction || 'start';
    const requiredFrames = transitionFrameBudget[prevKey][nextAction];
    return requiredFrames * moveSpeed;
  }

  function canTransition(previousAction, nextAction, gapPx) {
    return gapPx >= getMinGapPx(previousAction, nextAction);
  }

  function hasNearbyObstacle(worldStart, worldEnd, ignoreObstacle = null) {
    return obstacles.some((placed) => {
      if (ignoreObstacle && placed === ignoreObstacle) return false;
      const placedStart = placed.worldX - courseSafety.obstacleSpacingBuffer;
      const placedEnd = placed.worldX + placed.w + courseSafety.obstacleSpacingBuffer;
      return worldStart < placedEnd && worldEnd > placedStart;
    });
  }

  function getPreviousObstacle(obstacleStart) {
    let previous = null;
    for (const candidate of obstacles) {
      const candidateEnd = candidate.worldX + candidate.w;
      if (
        candidateEnd <= obstacleStart &&
        (!previous || candidateEnd > previous.worldX + previous.w)
      ) {
        previous = candidate;
      }
    }
    return previous;
  }

  function hasCaveInSpan(worldStart, worldEnd) {
    for (
      let sampleX = worldStart;
      sampleX <= worldEnd;
      sampleX += courseSafety.clearanceSampleStep
    ) {
      if (getCaveCeilingAt(sampleX) != null) {
        return true;
      }
    }
    return getCaveCeilingAt(worldEnd) != null;
  }

  function getRequiredObstacleGap(previousAction, nextAction, inCave) {
    const gapTable = inCave ? courseSafety.minObstacleGapPxInCave : courseSafety.minObstacleGapPx;
    const fromAction = previousAction || 'jump';
    return gapTable[fromAction][nextAction];
  }

  function isObstaclePlacementWinnable(obstacle, action) {
    const obstacleStart = obstacle.worldX;
    const obstacleEnd = obstacle.worldX + obstacle.w;
    const obstacleCenter = obstacleStart + obstacle.w * 0.5;
    const requiredLandingBuffer =
      action === 'stay' ? courseSafety.minLandingBufferForStay : courseSafety.minLandingBuffer;
    const requiredTakeoffBuffer =
      action === 'stay' ? courseSafety.minTakeoffBufferForStay : courseSafety.minTakeoffBuffer;

    if (action === 'jump') {
      const approachStart = obstacleStart - courseSafety.jumpObstacleCaveApproachBuffer;
      if (hasCaveInSpan(approachStart, obstacleEnd)) {
        return false;
      }

      const uphillSampleX = obstacleStart - player.w;
      const downhillAmount = getTerrainHeight(obstacleStart) - getTerrainHeight(uphillSampleX);
      if (downhillAmount > courseSafety.maxDownhillBeforeJumpObstacle) {
        return false;
      }
    } else if (action === 'stay') {
      const postObstacleGround = getTerrainHeight(obstacleEnd);
      let lowestRunoutGround = postObstacleGround;
      const runoutEnd = obstacleEnd + courseSafety.stayObstacleRunoutDistance;
      for (
        let sampleX = obstacleEnd + courseSafety.clearanceSampleStep;
        sampleX <= runoutEnd;
        sampleX += courseSafety.clearanceSampleStep
      ) {
        lowestRunoutGround = Math.max(lowestRunoutGround, getTerrainHeight(sampleX));
      }

      const downhillAfterStay = lowestRunoutGround - postObstacleGround;
      if (downhillAfterStay > courseSafety.maxDownhillAfterStayObstacle) {
        return false;
      }

      const droneApproachStart = obstacleStart - requiredTakeoffBuffer;
      let peakApproachY = getTerrainHeight(droneApproachStart);
      for (
        let sampleX = droneApproachStart + courseSafety.clearanceSampleStep;
        sampleX < obstacleStart;
        sampleX += courseSafety.clearanceSampleStep
      ) {
        peakApproachY = Math.min(peakApproachY, getTerrainHeight(sampleX));
      }
      const approachDrop = getTerrainHeight(obstacleStart) - peakApproachY;
      const approachHasCave = hasCaveInSpan(droneApproachStart, obstacleEnd);
      const maxApproachDrop = approachHasCave
        ? courseSafety.maxDownhillBeforeDroneInCave
        : courseSafety.maxDownhillBeforeDrone;
      if (approachDrop > maxApproachDrop) {
        return false;
      }
    }

    if (hasNearbyObstacle(obstacleStart, obstacleEnd, obstacle)) {
      return false;
    }

    const previousObstacle = getPreviousObstacle(obstacleStart);
    if (previousObstacle) {
      const prevEnd = previousObstacle.worldX + previousObstacle.w;
      const transitionStart = prevEnd;
      const transitionEnd = obstacleStart + obstacle.w * 0.2;
      const inCaveTransition = hasCaveInSpan(transitionStart, transitionEnd);
      const requiredGap = getRequiredObstacleGap(previousObstacle.action, action, inCaveTransition);
      if (obstacleStart - prevEnd < requiredGap) {
        return false;
      }
    }

    if (
      getPrecipiceNear(obstacleStart, courseSafety.precipiceAvoidanceBuffer) ||
      getPrecipiceNear(obstacleEnd, courseSafety.precipiceAvoidanceBuffer)
    ) {
      return false;
    }

    const adjacentPrecipice = terrain.precipices.find(
      (drop) =>
        (obstacleStart >= drop.end && obstacleStart - drop.end < requiredLandingBuffer) ||
        (obstacleEnd <= drop.start && drop.start - obstacleEnd < requiredTakeoffBuffer)
    );
    if (adjacentPrecipice) {
      return false;
    }

    const ceilingSampleStart = obstacleStart - player.w;
    const ceilingSampleEnd = obstacleEnd + player.w;
    for (
      let sampleX = ceilingSampleStart;
      sampleX <= ceilingSampleEnd;
      sampleX += courseSafety.clearanceSampleStep
    ) {
      const groundY = getTerrainHeight(sampleX);
      const caveCeilingY = getCaveCeilingAt(sampleX);

      if (caveCeilingY != null) {
        const headroom = groundY - caveCeilingY;
        if (headroom < courseSafety.minCaveHeadroomForAnyObstacle) {
          return false;
        }
        if (action === 'jump' && headroom < courseSafety.minCaveHeadroomForJumpObstacle) {
          return false;
        }
        if (action === 'jump' && headroom - obstacle.h < player.h * 2.0) {
          return false;
        }
      }

      if (hasNearbyObstacle(sampleX - 8, sampleX + 8, obstacle) && caveCeilingY != null) {
        const localHeadroom = groundY - caveCeilingY;
        if (localHeadroom < courseSafety.minCaveHeadroom + 10) {
          return false;
        }
      }
    }

    const centerGroundY = getTerrainHeight(obstacleCenter);
    const centerCaveCeilingY = getCaveCeilingAt(obstacleCenter);
    if (centerCaveCeilingY != null) {
      const centerHeadroom = centerGroundY - centerCaveCeilingY;
      if (centerHeadroom < courseSafety.minCaveHeadroom) {
        return false;
      }
      if (action === 'jump' && centerHeadroom - obstacle.h < player.h * 2.0) {
        return false;
      }
    }

    return true;
  }

  function hasFrameBudgetFor(prevAction, nextAction) {
    // Frame budget represents the player's reaction window between actions.
    // We measure in elapsed frames so the gate stays valid even when world
    // speed grew during the wait (a stale pixel-gap check would block spawns
    // at high levels and let the player coast).
    if (!prevAction) return true;
    const requiredFrames = transitionFrameBudget[prevAction][nextAction];
    return framesSinceLastSpawn >= requiredFrames;
  }

  function scheduleNextObstacle() {
    const moveSpeed = baseSpeed * speedMult;
    const spawnEdgeX = worldOffset + canvas.width + 20;
    const preferredAction = queuedSpawnAction;

    for (let attempt = 0; attempt < 24; attempt++) {
      const nextAction = attempt === 0 && preferredAction ? preferredAction : pickRandomAction();
      if (!hasFrameBudgetFor(lastSpawnAction, nextAction)) {
        continue;
      }

      const obstacle = createObstacle(nextAction, spawnEdgeX);
      if (!isObstaclePlacementWinnable(obstacle, nextAction)) {
        continue;
      }

      const spawnShiftPx = Math.max(0, obstacle.worldX - spawnEdgeX);
      obstacles.push(obstacle);
      lastSpawnAction = nextAction;
      queuedSpawnAction = null;
      framesSinceLastSpawn = 0;

      for (let previewAttempt = 0; previewAttempt < 24; previewAttempt++) {
        const previewAction = pickRandomAction();
        const previewGapPx = getSpawnDelayMs(nextAction, previewAction) * moveSpeed * (60 / 1000);
        if (!canTransition(nextAction, previewAction, previewGapPx)) {
          continue;
        }

        applySpawnGap(previewGapPx + spawnShiftPx, moveSpeed);
        queuedSpawnAction = previewAction;
        return;
      }

      const fallbackGapPx = getSpawnDelayMs(nextAction, 'jump') * moveSpeed * (60 / 1000);
      applySpawnGap(fallbackGapPx + spawnShiftPx, moveSpeed);
      queuedSpawnAction = 'jump';
      return;
    }

    const fallbackAction = preferredAction || 'jump';
    const fallbackObstacle = createObstacle(fallbackAction, spawnEdgeX);
    if (isObstaclePlacementWinnable(fallbackObstacle, fallbackAction)) {
      const fallbackShiftPx = Math.max(0, fallbackObstacle.worldX - spawnEdgeX);
      obstacles.push(fallbackObstacle);
      lastSpawnAction = fallbackAction;
      framesSinceLastSpawn = 0;
      const fallbackNextAction = 'jump';
      applySpawnGap(
        getSpawnDelayMs(fallbackAction, fallbackNextAction) * moveSpeed * (60 / 1000) +
          fallbackShiftPx,
        moveSpeed
      );
      queuedSpawnAction = fallbackNextAction;
      return;
    }
    const fallbackNextAction = 'jump';
    applySpawnGap(
      getSpawnDelayMs(fallbackAction, fallbackNextAction) * moveSpeed * (60 / 1000),
      moveSpeed
    );
    queuedSpawnAction = fallbackNextAction;
  }

  // ---------- Bits, power-ups, particles, projectiles, boss ----------

  function spawnBitArc(startWorldX) {
    // 5–8 bits in a low arc, jumpable but tempting to grab.
    const count = 5 + Math.floor(gameRandom() * 4);
    const ground = getTerrainHeight(startWorldX);
    const peakHeight = 80 + gameRandom() * 50;
    for (let i = 0; i < count; i++) {
      const t = i / Math.max(1, count - 1);
      const x = startWorldX + i * 30;
      const arc = -peakHeight * Math.sin(t * Math.PI);
      bits.push({ worldX: x, y: ground + arc - 18, w: 14, h: 14, vy: 0, alive: true, value: 1 });
    }
  }

  function spawnBitLine(startWorldX, atY) {
    const count = 4 + Math.floor(gameRandom() * 3);
    for (let i = 0; i < count; i++) {
      bits.push({
        worldX: startWorldX + i * 26,
        y: atY,
        w: 14,
        h: 14,
        vy: 0,
        alive: true,
        value: 1,
      });
    }
  }

  function maybeSpawnBitsAround(obstacle) {
    // 60% of the time, drop a small reward arc that spans the obstacle so the
    // jump itself doubles as a collection move.
    if (gameRandom() > 0.6) return;
    const ahead = obstacle.worldX - 60;
    spawnBitArc(ahead);
  }

  const POWERUP_KINDS = ['shield', 'overclock', 'magnet', 'slowmo'];
  function maybeSpawnPowerup() {
    // ~1 every ~600m of distance, biased to ground level.
    if (gameRandom() > 0.012) return;
    const allowed = POWERUP_KINDS.filter((k) => k !== 'shield' || getMod().allowShield);
    const kind = allowed[Math.floor(gameRandom() * allowed.length)];
    const worldX = worldOffset + canvas.width + 40;
    const ground = getTerrainHeight(worldX);
    powerupItems.push({
      worldX,
      y: ground - 70 - gameRandom() * 40,
      w: 24,
      h: 24,
      kind,
      alive: true,
      bob: gameRandom() * Math.PI * 2,
    });
  }

  function activatePowerup(kind) {
    if (kind === 'shield') pwr.shield = 1; // boolean (single hit absorb)
    if (kind === 'overclock') pwr.overclock = 5 * 60;
    if (kind === 'magnet') pwr.magnet = 7 * 60;
    if (kind === 'slowmo') pwr.slowmo = 4 * 60;
    sfxExt.powerup();
    announce(`${kind} active`);
    spawnBurst(player.x + player.w / 2, player.y + player.h / 2, 14, '#ffd95c');
  }

  function spawnBurst(x, y, count, color) {
    for (let i = 0; i < count; i++) {
      const a = (Math.PI * 2 * i) / count + Math.random() * 0.4;
      const sp = 2 + Math.random() * 4;
      particles.push({
        x,
        y,
        vx: Math.cos(a) * sp,
        vy: Math.sin(a) * sp - 1,
        life: 22 + Math.random() * 12,
        color,
      });
    }
  }

  function spawnTrail() {
    // Speed-tied trail particle behind the player.
    if (reduceMotion) return;
    if (Math.random() > 0.4) return;
    const colors = getSkinColors();
    particles.push({
      x: player.x + 4 + Math.random() * 4,
      y: player.y + player.h * 0.55 + Math.random() * 6,
      vx: -1.5 - Math.random() * 1.5,
      vy: -0.4 + Math.random() * 0.8,
      life: 18 + Math.random() * 10,
      color: Math.random() < 0.5 ? colors[0] : colors[1],
    });
  }

  function triggerShake(intensity, frames) {
    if (reduceMotion) return;
    shakeIntensity = Math.max(shakeIntensity, intensity);
    shakeFrames = Math.max(shakeFrames, frames);
  }

  function spawnBoss() {
    if (boss) return;
    boss = {
      worldX: worldOffset + canvas.width + 80,
      y: (40 + (baseGroundY - 70 - 30)) / 2,
      w: 110,
      h: 70,
      hp: 100,
      maxHp: 100,
      timer: 12 * 60, // survive ~12s to win
      cooldown: 60,
      pattern: 0,
    };
    bossSpawnsSuppressed = boss.timer + 60;
    sfxExt.boss();
    triggerShake(6, 30);
    announce('Mainframe boss incoming');
    levelBannerText = '⚠ MAINFRAME BOSS ⚠';
    levelBannerFrames = 120;
  }

  function bossDefeated() {
    if (!boss) return;
    sfxExt.bossDie();
    triggerShake(10, 40);
    spawnBurst(boss.worldX - worldOffset + boss.w / 2, boss.y + boss.h / 2, 36, '#ffd95c');
    // Reward: bit shower + temporary overclock + persistent stat.
    const bx = boss.worldX - 200;
    const by = boss.y + boss.h + 20;
    spawnBitLine(bx, by);
    spawnBitLine(bx + 30, by + 20);
    pwr.overclock = Math.max(pwr.overclock, 4 * 60);
    lifetime.bossKills += 1;
    saveLifetime(lifetime);
    populateSkinSelect();
    boss = null;
  }

  function bossUpdate() {
    if (!boss) return;
    // Drift to a fixed screen position for telegraphed dodging.
    const targetWorldX = worldOffset + canvas.width - boss.w - 8;
    boss.worldX += (targetWorldX - boss.worldX) * 0.04;
    // Patrol vertically across the playfield so the player must dodge.
    const yMin = 18;
    const yMax = baseGroundY - boss.h;
    const yCenter = (yMin + yMax) / 2;
    const yAmp = (yMax - yMin) / 2;
    boss.y = yCenter + Math.sin(performance.now() * 0.0015) * yAmp;
    boss.timer -= 1;
    boss.cooldown -= 1;
    if (boss.cooldown <= 0) {
      // Fire a 3-laser fan staggered by pattern step.
      const baseY = boss.y + boss.h - 8;
      const baseX = boss.worldX + 12;
      for (let i = 0; i < 3; i++) {
        projectiles.push({
          worldX: baseX,
          y: baseY + i * 14,
          w: 22,
          h: 8,
          vx: -7 - speedMult * 0.6,
          vy: 0,
          life: 240,
        });
      }
      sfxExt.laser();
      boss.cooldown = 70 - Math.min(40, level * 4);
      boss.pattern += 1;
    }
    if (boss.timer <= 0) {
      bossDefeated();
    }
  }

  // ---------- Rendering ----------

  function drawSkyline() {
    const parallax = reduceMotion ? 0.05 : 0.3;
    sceneryOffset += baseSpeed * speedMult * speedMultiplier * parallax;

    for (let i = 0; i < 6; i++) {
      const width = 130;
      const x = i * 170 - (sceneryOffset % 170);
      const h = 110 + (i % 3) * 30;
      ctx.fillStyle = 'rgba(141,89,255,0.22)';
      ctx.fillRect(x, baseGroundY - h, width, h);

      ctx.fillStyle = 'rgba(46,248,255,0.6)';
      for (let wy = baseGroundY - h + 12; wy < baseGroundY - 10; wy += 20) {
        for (let wx = x + 12; wx < x + width - 10; wx += 22) {
          ctx.fillRect(wx, wy, 8, 9);
        }
      }
    }

    ctx.fillStyle = 'rgba(255,255,255,0.7)';
    for (let i = 0; i < 45; i++) {
      const starX = (i * 41 + 17) % canvas.width;
      const starY = (i * 29 + 23) % (baseGroundY - 130);
      ctx.fillRect((starX + sceneryOffset * 0.12) % canvas.width, starY, 2, 2);
    }
  }

  function drawGround() {
    groundOffset += baseSpeed * speedMult * speedMultiplier;
    const renderWorldOffset = Math.floor(worldOffset);
    const endWorld = renderWorldOffset + canvas.width + terrain.step * 2;
    const groundSampleStep = 6;
    ensureTerrainAhead(endWorld + 300);

    ctx.fillStyle = '#16233f';
    ctx.beginPath();
    ctx.moveTo(0, canvas.height);
    for (let sx = -terrain.step; sx <= canvas.width + terrain.step; sx += groundSampleStep) {
      const worldX = renderWorldOffset + sx;
      const gy = Math.round(getTerrainHeight(worldX));
      ctx.lineTo(sx, gy);
    }
    ctx.lineTo(canvas.width, canvas.height);
    ctx.closePath();
    ctx.fill();

    for (let x = -(groundOffset % 42); x < canvas.width; x += 42) {
      const gy = getTerrainHeight(worldOffset + x + 8);
      if (gy >= canvas.height - 4) continue;
      ctx.fillStyle = 'rgba(46,248,255,0.7)';
      ctx.fillRect(x, gy + 20, 24, 4);
    }

    ctx.fillStyle = '#16233f';
    terrain.caves.forEach((cave) => {
      if (cave.end < worldOffset - 40 || cave.start > worldOffset + canvas.width + 40) return;
      const startX = cave.start - renderWorldOffset;
      const endX = cave.end - renderWorldOffset;
      ctx.beginPath();
      ctx.moveTo(startX, 0);
      ctx.lineTo(startX, cave.baseCeiling);
      for (let worldX = cave.start; worldX <= cave.end; worldX += 16) {
        const sx = worldX - renderWorldOffset;
        const wave = Math.sin(worldX * 0.04 + cave.phase) * cave.amplitude;
        ctx.lineTo(sx, cave.baseCeiling + wave);
      }
      const endWave = Math.sin(cave.end * 0.04 + cave.phase) * cave.amplitude;
      ctx.lineTo(endX, cave.baseCeiling + endWave);
      ctx.lineTo(endX, 0);
      ctx.closePath();
      ctx.fill();
    });
  }

  function drawPlayer() {
    const colors = getSkinColors();
    // While ducking, hitbox uses player.h directly; we just visually flatten.
    const drawY = player.y;
    const drawH = player.h;
    const g = ctx.createLinearGradient(player.x, drawY, player.x + player.w, drawY + drawH);
    g.addColorStop(0, colors[0]);
    g.addColorStop(1, colors[1]);
    ctx.fillStyle = g;
    roundRect(ctx, player.x, drawY, player.w, drawH, 10);
    ctx.fill();

    ctx.fillStyle = '#e9f6ff';
    ctx.font = 'bold 15px monospace';
    if (drawH >= 30) {
      ctx.fillText('</>', player.x + 7, drawY + Math.min(34, drawH - 14));
    }

    // Shield aura
    if (pwr.shield > 0) {
      ctx.save();
      ctx.strokeStyle = 'rgba(46,248,255,0.85)';
      ctx.lineWidth = 3;
      ctx.beginPath();
      ctx.arc(
        player.x + player.w / 2,
        drawY + drawH / 2,
        Math.max(player.w, drawH) * 0.65,
        0,
        Math.PI * 2
      );
      ctx.stroke();
      ctx.restore();
    }
    // Overclock outline
    if (pwr.overclock > 0) {
      ctx.save();
      ctx.strokeStyle = 'rgba(255,217,92,0.9)';
      ctx.lineWidth = 2;
      ctx.strokeRect(player.x - 3, drawY - 3, player.w + 6, drawH + 6);
      ctx.restore();
    }
    // Dash trail emphasis
    if (dashFrames > 0) {
      ctx.save();
      ctx.fillStyle = 'rgba(255,255,255,0.25)';
      ctx.fillRect(player.x - 18, drawY + 6, 18, drawH - 12);
      ctx.fillStyle = 'rgba(255,255,255,0.12)';
      ctx.fillRect(player.x - 36, drawY + 12, 18, drawH - 24);
      ctx.restore();
    }
  }

  function drawObstacle(ob) {
    if (ob.type === 'bug') {
      ctx.font = '28px serif';
      ctx.fillText('🐞', ob.x, ob.y + ob.h);
    } else if (ob.type === 'server') {
      ctx.fillStyle = '#ff5a7c';
      roundRect(ctx, ob.x, ob.y, ob.w, ob.h, 7);
      ctx.fill();
      ctx.fillStyle = '#12020a';
      ctx.fillRect(ob.x + 8, ob.y + 12, ob.w - 16, 6);
      ctx.fillRect(ob.x + 8, ob.y + 26, ob.w - 16, 6);
    } else if (ob.type === 'drone') {
      ctx.fillStyle = 'rgba(255, 202, 95, 0.9)';
      roundRect(ctx, ob.x, ob.y, ob.w, ob.h, 8);
      ctx.fill();
      ctx.fillStyle = '#3e2b09';
      ctx.fillRect(ob.x + 10, ob.y + 8, ob.w - 20, 6);
      ctx.fillStyle = '#ffd95c';
      ctx.fillRect(ob.x + 30, ob.y + ob.h, 12, 12);
    } else {
      const lg = ctx.createLinearGradient(ob.x, ob.y, ob.x, ob.y + ob.h);
      lg.addColorStop(0, 'rgba(255,83,112,0.95)');
      lg.addColorStop(1, 'rgba(255,83,112,0.25)');
      ctx.fillStyle = lg;
      ctx.fillRect(ob.x, ob.y, ob.w, ob.h);
    }
  }

  function roundRect(ctx, x, y, w, h, r) {
    ctx.beginPath();
    ctx.moveTo(x + r, y);
    ctx.arcTo(x + w, y, x + w, y + h, r);
    ctx.arcTo(x + w, y + h, x, y + h, r);
    ctx.arcTo(x, y + h, x, y, r);
    ctx.arcTo(x, y, x + w, y, r);
    ctx.closePath();
  }

  // ---------- Game loop ----------

  function resetRunState() {
    closeScoreModal();
    gameOverOverlay.classList.remove('active');
    pauseOverlay.classList.remove('active');
    paused = false;
    gameOver = false;
    score = 0;
    speedMult = 1;
    baseSpeed = 4.2;
    spawnTimer = 0;
    obstacles.length = 0;
    lastSpawnAction = null;
    queuedSpawnAction = null;
    framesSinceLastSpawn = Number.POSITIVE_INFINITY;
    worldOffset = 0;
    latestRunScore = 0;
    bitsCollected = 0;
    combo = 1;
    comboTimer = 0;
    level = 1;
    nextLevelAt = LEVEL_INTERVAL;
    nextBossAt = BOSS_INTERVAL;
    bits.length = 0;
    powerupItems.length = 0;
    particles.length = 0;
    projectiles.length = 0;
    boss = null;
    bossSpawnsSuppressed = 0;
    pwr.shield = 0;
    pwr.overclock = 0;
    pwr.magnet = 0;
    pwr.slowmo = 0;
    coyoteFrames = 0;
    jumpBufferFrames = 0;
    isDucking = false;
    dashFrames = 0;
    dashCooldown = 0;
    wallRunFrames = 0;
    wallRunCooldown = 0;
    nearMissCooldown = 0;
    shakeFrames = 0;
    shakeIntensity = 0;
    hitstopFrames = 0;
    levelBannerFrames = 0;
    document.body.removeAttribute('data-palette');
    setScoreSubmissionState(false);
    initTerrain();
    const spawnGround = getTerrainHeight(player.x + player.w * 0.5) || baseGroundY;
    player.h = 58;
    player.y = spawnGround - player.h;
    player.vy = 0;
    player.onGround = true;
    player.jumpsLeft = getMod().noDoubleJump ? 1 : 2;
    updateHud();
    renderPowerupPills();
  }

  function resetGame() {
    resetRunState();
    gameStarted = true;
    setLeaderboardStatus('Finish a run, then save your score to the global board.');
    fetchLeaderboard();
    // Re-seed RNG for daily mode so reboot replays the same course.
    useSeededRng = dailySeedActive;
    if (useSeededRng) setRngSeed(dailySeedValue());
    initTerrain();
    const spawnGround = getTerrainHeight(player.x + player.w * 0.5) || baseGroundY;
    player.y = spawnGround - player.h;
    scheduleLoop();
  }

  function returnToStartMenu() {
    if (rafId !== null) {
      cancelAnimationFrame(rafId);
      rafId = null;
    }
    resetRunState();
    gameStarted = false;
    startOverlay.classList.remove('hidden');
    populateSkinSelect();
    setLeaderboardStatus('Finish a run, then save your score to the global board.');
    render();
  }

  function updateHud() {
    scoreEl.textContent = Math.floor(score);
    speedEl.textContent = speedMult.toFixed(1);
    bestEl.textContent = Math.floor(best);
    if (bitsEl) bitsEl.textContent = bitsCollected;
    if (comboEl) comboEl.textContent = 'x' + combo.toFixed(1);
    if (levelEl) levelEl.textContent = level;
  }

  function renderPowerupPills() {
    if (!powerupBar) return;
    powerupBar.innerHTML = '';
    const entries = [];
    if (pwr.shield > 0) entries.push(['shield', 'SHIELD']);
    if (pwr.overclock > 0)
      entries.push(['overclock', 'OVERCLOCK ' + Math.ceil(pwr.overclock / 60) + 's']);
    if (pwr.magnet > 0) entries.push(['magnet', 'MAGNET ' + Math.ceil(pwr.magnet / 60) + 's']);
    if (pwr.slowmo > 0) entries.push(['slowmo', 'SLOW-MO ' + Math.ceil(pwr.slowmo / 60) + 's']);
    entries.forEach(([kind, label]) => {
      const div = document.createElement('div');
      div.className = 'powerup-pill';
      div.dataset.kind = kind;
      div.textContent = label;
      powerupBar.appendChild(div);
    });
  }

  function tryHandleHit(_source) {
    // Returns true if hit was absorbed/avoided; false if it kills the run.
    if (pwr.shield > 0) {
      pwr.shield = 0;
      sfxExt.shield();
      triggerShake(8, 18);
      hitstopFrames = 6;
      // Brief invuln window via tiny upward bump.
      player.vy = Math.min(player.vy, -6);
      spawnBurst(player.x + player.w / 2, player.y + player.h / 2, 18, '#2ef8ff');
      return true;
    }
    return false;
  }

  function maybeLevelUp() {
    if (score < nextLevelAt) return;
    level += 1;
    nextLevelAt += LEVEL_INTERVAL;
    baseSpeed = Math.min(7.0, baseSpeed + 0.1);
    levelBannerText = `LEVEL ${level}`;
    levelBannerFrames = 90;
    sfxExt.levelup();
    document.body.setAttribute('data-palette', String(((level - 1) % 6) + 1));
    announce(`Level ${level}`);
    triggerShake(3, 14);
  }

  function update() {
    if (gameOver || paused) return;
    if (hitstopFrames > 0) {
      hitstopFrames -= 1;
      updateHud();
      return;
    }

    // Power-up timers
    if (pwr.overclock > 0) pwr.overclock -= 1;
    if (pwr.magnet > 0) pwr.magnet -= 1;
    if (pwr.slowmo > 0) pwr.slowmo -= 1;
    if (dashFrames > 0) dashFrames -= 1;
    if (dashCooldown > 0) dashCooldown -= 1;
    if (wallRunFrames > 0) wallRunFrames -= 1;
    if (wallRunCooldown > 0) wallRunCooldown -= 1;
    if (nearMissCooldown > 0) nearMissCooldown -= 1;
    if (bossSpawnsSuppressed > 0) bossSpawnsSuppressed -= 1;
    if (levelBannerFrames > 0) levelBannerFrames -= 1;

    // Combo decay (resets after ~3s without bit pickups)
    if (comboTimer > 0) {
      comboTimer -= 1;
      if (comboTimer === 0) combo = 1;
    }

    // Points formula: each frame contributes distance-derived points scaled by
    // speed, combo, overclock, and the active modifier's scoreMult. Bits add
    // 8 * bitValue points on pickup (bitValue already includes the modifier's
    // bitsMult), and near-misses add a flat 5-point bonus. The leaderboard
    // submits the floored running total as the run's points.
    const overclockMult = pwr.overclock > 0 ? 2 : 1;
    const scoreGain = 0.2 * speedMult * combo * overclockMult * getMod().scoreMult;
    score += scoreGain;
    // Sub-linear (sqrt) ramp so each level's speed bump shrinks instead of
    // compounding — keeps later levels from feeling like a brick wall.
    speedMult = Math.min(5, 1 + Math.sqrt(score) * 0.04);

    // Slow-mo halves world speed but keeps player physics responsive.
    const slowFactor = pwr.slowmo > 0 ? 0.55 : 1;
    // Boss fights force the world to crawl so the player has time to actually
    // dodge lasers and trade hits instead of speeding past the encounter.
    const bossFactor = boss ? 0.5 : 1;
    speedMultiplier = overclockMult * slowFactor * bossFactor;
    const moveSpeed = baseSpeed * speedMult * speedMultiplier;
    const dashBoost = dashFrames > 0 ? 4 : 0;
    worldOffset += moveSpeed + dashBoost;
    ensureTerrainAhead(worldOffset + canvas.width + 460);

    const pruneX = worldOffset - canvas.width * 3;
    let pruneTo = 0;
    while (pruneTo + 1 < terrain.points.length && terrain.points[pruneTo + 1].x < pruneX) {
      pruneTo++;
    }
    if (pruneTo > 0) terrain.points.splice(0, pruneTo);
    terrain.caves = terrain.caves.filter((c) => c.end >= pruneX);
    terrain.precipices = terrain.precipices.filter((p) => p.end >= pruneX);

    // Apply gravity (modified by Feather Fall)
    const grav = gravity * getMod().gravityMult;
    player.vy += grav;
    // Wall-run suspends gravity briefly
    if (wallRunFrames > 0) player.vy = Math.min(player.vy, -1.5);
    player.y += player.vy;

    // Duck shrinks the hitbox; release expands. Hold-duck while jumping is
    // honored so the player can tuck through low ceilings mid-air.
    const targetH = isDucking ? 32 : 58;
    if (player.h !== targetH) {
      const groundDelta = targetH - player.h;
      player.h = targetH;
      // Keep feet planted when ducking on ground.
      if (player.onGround) player.y -= groundDelta;
    }

    const playerWorldCenter = worldOffset + player.x + player.w * 0.5;
    const currentGround = getTerrainHeight(playerWorldCenter);
    let nowOnGround = false;
    if (isInPrecipice(playerWorldCenter)) {
      player.onGround = false;
      if (player.y + player.h >= currentGround) {
        if (!tryHandleHit('fall')) {
          gameOver = true;
        } else {
          player.y = currentGround - player.h - 40;
        }
      }
    } else if (player.y >= currentGround - player.h) {
      player.y = currentGround - player.h;
      player.vy = 0;
      player.onGround = true;
      nowOnGround = true;
      player.jumpsLeft = getMod().noDoubleJump ? 1 : 2;
      coyoteFrames = 6;
    } else {
      player.onGround = false;
      if (coyoteFrames > 0) coyoteFrames -= 1;
    }

    // Cave ceiling: enable wall-run if player presses jump near ceiling.
    const activeCave = getCaveAt(playerWorldCenter);
    if (activeCave) {
      const ceilingWave =
        Math.sin(playerWorldCenter * 0.04 + activeCave.phase) * activeCave.amplitude;
      const ceilingY = activeCave.baseCeiling + ceilingWave;
      if (player.y <= ceilingY) {
        // If player is wall-running, stick just below the ceiling.
        if (wallRunFrames > 0) {
          player.y = ceilingY + 2;
          player.vy = 0;
        } else if (!tryHandleHit('ceiling')) {
          gameOver = true;
        } else {
          player.y = ceilingY + 8;
          player.vy = 6;
        }
      }
    }

    // Honor jump buffer if we just landed.
    if (jumpBufferFrames > 0 && (nowOnGround || coyoteFrames > 0)) {
      doJump();
      jumpBufferFrames = 0;
    } else if (jumpBufferFrames > 0) {
      jumpBufferFrames -= 1;
    }

    if (player.y > canvas.height + 80) {
      gameOver = true;
    }

    // Trail particles
    spawnTrail();

    // Obstacle spawning suspended during boss fight
    if (boss == null) {
      if (framesSinceLastSpawn !== Number.POSITIVE_INFINITY) framesSinceLastSpawn += 1;
      spawnTimer -= 16.7;
      if (spawnTimer <= 0) {
        scheduleNextObstacle();
        // chance to drop bits/powerups around the latest obstacle
        const last = obstacles[obstacles.length - 1];
        if (last) maybeSpawnBitsAround(last);
        maybeSpawnPowerup();
      }
    }

    // Boss spawning: every 1500m, suppressed during current encounter
    if (boss == null && score >= nextBossAt && bossSpawnsSuppressed === 0) {
      spawnBoss();
      nextBossAt += BOSS_INTERVAL;
    }
    bossUpdate();

    // Obstacle collisions + near-miss detection
    for (let i = obstacles.length - 1; i >= 0; i--) {
      const ob = obstacles[i];
      const obScreenX = ob.worldX - worldOffset;

      const hit =
        player.x < obScreenX + ob.w &&
        player.x + player.w > obScreenX &&
        player.y < ob.y + ob.h &&
        player.y + player.h > ob.y;

      if (hit) {
        if (!tryHandleHit('obstacle')) {
          gameOver = true;
          finalizeRun();
          return;
        }
        obstacles.splice(i, 1);
        continue;
      }

      // Near-miss: obstacle just passed and was within ~14px vertically
      if (
        obScreenX + ob.w < player.x &&
        obScreenX + ob.w > player.x - 6 &&
        nearMissCooldown === 0
      ) {
        const verticalGap = Math.min(
          Math.abs(ob.y + ob.h - player.y),
          Math.abs(ob.y - (player.y + player.h))
        );
        if (verticalGap > 0 && verticalGap < 14) {
          nearMissCooldown = 30;
          combo = Math.min(8, combo + 0.2);
          comboTimer = 180;
          score += 5;
          spawnBurst(player.x + player.w, player.y + player.h * 0.3, 6, '#ffd95c');
          sfxExt.combo();
        }
      }

      if (obScreenX + ob.w < -20) {
        obstacles.splice(i, 1);
      }
    }

    // Bits update + collection
    const magnetActive = pwr.magnet > 0;
    for (let i = bits.length - 1; i >= 0; i--) {
      const bit = bits[i];
      const sx = bit.worldX - worldOffset;
      // Magnet effect: pull bit toward player in world space.
      if (magnetActive) {
        const playerWorldX = worldOffset + player.x + player.w / 2;
        const dx = playerWorldX - bit.worldX;
        const dy = player.y + player.h / 2 - bit.y;
        const dist2 = dx * dx + dy * dy;
        if (dist2 < 230 * 230) {
          const d = Math.sqrt(dist2) || 1;
          bit.worldX += (dx / d) * 5;
          bit.y += (dy / d) * 5;
        }
      }
      const collide =
        player.x < sx + bit.w &&
        player.x + player.w > sx &&
        player.y < bit.y + bit.h &&
        player.y + player.h > bit.y;
      if (collide) {
        bits.splice(i, 1);
        const value = bit.value * getMod().bitsMult;
        bitsCollected += value;
        combo = Math.min(8, combo + 0.1 * value);
        comboTimer = 180;
        score += 8 * value;
        spawnBurst(sx + 4, bit.y + 4, 5, '#ffd95c');
        sfxExt.bit();
        continue;
      }
      if (sx + bit.w < -20) bits.splice(i, 1);
    }

    // Power-up items
    for (let i = powerupItems.length - 1; i >= 0; i--) {
      const it = powerupItems[i];
      it.bob += 0.1;
      const sx = it.worldX - worldOffset;
      const drawY = it.y + Math.sin(it.bob) * 4;
      const collide =
        player.x < sx + it.w &&
        player.x + player.w > sx &&
        player.y < drawY + it.h &&
        player.y + player.h > drawY;
      if (collide) {
        activatePowerup(it.kind);
        powerupItems.splice(i, 1);
        continue;
      }
      if (sx + it.w < -20) powerupItems.splice(i, 1);
    }

    // Projectile collisions
    for (let i = projectiles.length - 1; i >= 0; i--) {
      const p = projectiles[i];
      p.worldX += p.vx;
      p.life -= 1;
      const sx = p.worldX - worldOffset;
      const collide =
        player.x < sx + p.w &&
        player.x + player.w > sx &&
        player.y < p.y + p.h &&
        player.y + player.h > p.y;
      if (collide) {
        projectiles.splice(i, 1);
        if (!tryHandleHit('laser')) {
          gameOver = true;
          finalizeRun();
          return;
        }
        continue;
      }
      if (sx < -40 || p.life <= 0) projectiles.splice(i, 1);
    }

    // Particles
    for (let i = particles.length - 1; i >= 0; i--) {
      const p = particles[i];
      p.x += p.vx;
      p.y += p.vy;
      p.vy += 0.15;
      p.life -= 1;
      if (p.life <= 0) particles.splice(i, 1);
    }

    // Shake decay
    if (shakeFrames > 0) {
      shakeFrames -= 1;
      if (shakeFrames === 0) shakeIntensity = 0;
    }

    maybeLevelUp();

    if (gameOver) finalizeRun();

    updateHud();
    renderPowerupPills();
  }

  function finalizeRun() {
    best = Math.max(best, score);
    localStorage.setItem(BEST_KEY, String(Math.floor(best)));
    latestRunScore = Math.floor(score);
    latestRunModifier = MODIFIERS[activeModifier] ? activeModifier : 'none';
    setScoreSubmissionState(latestRunScore > 0);
    if (latestRunScore > 0) primeSubmitNonce();
    setLeaderboardStatus(
      `Run ended at ${latestRunScore} pts. Submit your score or press R to restart.`
    );
    announce(`Signal lost. ${latestRunScore} points. ${bitsCollected} bits.`);
    sfx.death();
    triggerShake(10, 30);
    spawnBurst(player.x + player.w / 2, player.y + player.h / 2, 24, '#ff5a7c');
    // Persist lifetime stats for skin unlocks.
    lifetime.distance += score;
    lifetime.bits += bitsCollected;
    lifetime.runs += 1;
    saveLifetime(lifetime);
    populateSkinSelect();
    updateHud();
  }

  function drawGameOver() {
    ctx.fillStyle = 'rgba(3, 7, 18, 0.74)';
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.fillStyle = '#fff';
    ctx.textAlign = 'center';
    ctx.font = '700 44px Segoe UI';
    ctx.fillText('Signal Lost', canvas.width / 2, canvas.height / 2 - 28);
    ctx.font = '600 24px Segoe UI';
    ctx.fillText(`Distance: ${Math.floor(score)}m`, canvas.width / 2, canvas.height / 2 + 12);
    ctx.font = '500 18px Segoe UI';
    ctx.fillText(
      'Press R to restart  ·  Use Submit Score to save',
      canvas.width / 2,
      canvas.height / 2 + 48
    );
    ctx.textAlign = 'left';
  }

  function drawBit(bit) {
    const sx = bit.worldX - worldOffset;
    const sy = bit.y;
    ctx.save();
    ctx.fillStyle = '#ffd95c';
    ctx.shadowColor = 'rgba(255,217,92,0.85)';
    ctx.shadowBlur = 8;
    ctx.beginPath();
    ctx.moveTo(sx + bit.w / 2, sy);
    ctx.lineTo(sx + bit.w, sy + bit.h / 2);
    ctx.lineTo(sx + bit.w / 2, sy + bit.h);
    ctx.lineTo(sx, sy + bit.h / 2);
    ctx.closePath();
    ctx.fill();
    ctx.restore();
  }

  function drawPowerupItem(it) {
    const sx = it.worldX - worldOffset;
    const sy = it.y + Math.sin(it.bob) * 4;
    const colorMap = {
      shield: '#2ef8ff',
      overclock: '#ffd95c',
      magnet: '#ff5cd1',
      slowmo: '#75ffd4',
    };
    const labelMap = { shield: 'S', overclock: 'O', magnet: 'M', slowmo: '~' };
    ctx.save();
    ctx.fillStyle = colorMap[it.kind] || '#fff';
    ctx.shadowColor = colorMap[it.kind] || '#fff';
    ctx.shadowBlur = 12;
    roundRect(ctx, sx, sy, it.w, it.h, 6);
    ctx.fill();
    ctx.shadowBlur = 0;
    ctx.fillStyle = '#0a1330';
    ctx.font = 'bold 14px monospace';
    ctx.textAlign = 'center';
    ctx.fillText(labelMap[it.kind] || '?', sx + it.w / 2, sy + it.h - 7);
    ctx.textAlign = 'left';
    ctx.restore();
  }

  function drawProjectile(p) {
    const sx = p.worldX - worldOffset;
    ctx.save();
    const lg = ctx.createLinearGradient(sx, p.y, sx + p.w, p.y);
    lg.addColorStop(0, 'rgba(255,83,112,0.0)');
    lg.addColorStop(1, 'rgba(255,83,112,1.0)');
    ctx.fillStyle = lg;
    ctx.fillRect(sx, p.y, p.w, p.h);
    ctx.restore();
  }

  function drawBoss() {
    if (!boss) return;
    const sx = boss.worldX - worldOffset;
    ctx.save();
    ctx.fillStyle = 'rgba(255,90,124,0.92)';
    roundRect(ctx, sx, boss.y, boss.w, boss.h, 14);
    ctx.fill();
    ctx.fillStyle = '#220009';
    ctx.fillRect(sx + 18, boss.y + 18, 14, 14);
    ctx.fillRect(sx + boss.w - 32, boss.y + 18, 14, 14);
    ctx.fillStyle = '#ffd95c';
    ctx.fillRect(sx + 24, boss.y + boss.h - 18, boss.w - 48, 6);
    // Survival bar
    ctx.fillStyle = 'rgba(0,0,0,0.4)';
    ctx.fillRect(sx, boss.y - 12, boss.w, 6);
    ctx.fillStyle = '#ffd95c';
    const bossMaxTimer = 12 * 60;
    const fill = clamp(1 - boss.timer / bossMaxTimer, 0, 1);
    ctx.fillRect(sx, boss.y - 12, boss.w * fill, 6);
    ctx.restore();
  }

  function drawParticles() {
    particles.forEach((p) => {
      const a = clamp(p.life / 30, 0, 1);
      ctx.save();
      ctx.globalAlpha = a;
      ctx.fillStyle = p.color || '#fff';
      ctx.fillRect(p.x, p.y, 3, 3);
      ctx.restore();
    });
  }

  function drawLevelBanner() {
    if (levelBannerFrames <= 0) return;
    const a = clamp(levelBannerFrames / 90, 0, 1);
    ctx.save();
    ctx.globalAlpha = a;
    ctx.fillStyle = '#ffd95c';
    ctx.font = '700 36px Segoe UI';
    ctx.textAlign = 'center';
    ctx.shadowColor = 'rgba(255,217,92,0.7)';
    ctx.shadowBlur = 18;
    ctx.fillText(levelBannerText, canvas.width / 2, 90);
    ctx.textAlign = 'left';
    ctx.restore();
  }

  function render() {
    ctx.save();
    if (shakeFrames > 0 && shakeIntensity > 0) {
      const dx = (Math.random() - 0.5) * 2 * shakeIntensity;
      const dy = (Math.random() - 0.5) * 2 * shakeIntensity;
      ctx.translate(dx, dy);
    }
    ctx.clearRect(-20, -20, canvas.width + 40, canvas.height + 40);
    drawSkyline();
    drawGround();
    obstacles.forEach((ob) => {
      const screenObstacle = { ...ob, x: ob.worldX - worldOffset };
      drawObstacle(screenObstacle);
    });
    bits.forEach(drawBit);
    powerupItems.forEach(drawPowerupItem);
    projectiles.forEach(drawProjectile);
    drawBoss();
    drawPlayer();
    drawParticles();
    drawLevelBanner();
    ctx.restore();
    if (gameOver) {
      drawGameOver();
      gameOverOverlay.classList.add('active');
    }
  }

  let inLoop = false;

  function loop() {
    rafId = null;
    if (paused || gameOver) return;
    inLoop = true;
    update();
    render();
    inLoop = false;
    // Re-check pause/gameOver in case they flipped during update/render so we
    // don't queue a frame the user has already asked us to stop.
    if (paused || gameOver) return;
    rafId = requestAnimationFrame(loop);
  }

  function scheduleLoop() {
    // inLoop guard: if loop is mid-execution, it will schedule the next frame
    // itself when it finishes. A second scheduleLoop here would double-queue
    // and effectively double the simulation rate.
    if (rafId !== null || inLoop) return;
    if (paused || gameOver) return;
    rafId = requestAnimationFrame(loop);
  }

  function doJump() {
    player.vy = player.jumpPower;
    player.onGround = false;
    player.jumpsLeft -= 1;
    coyoteFrames = 0;
    (player.jumpsLeft >= 1 ? sfx.jump : sfx.djump)();
  }

  function jump() {
    if (!gameStarted || gameOver || paused) return;
    // Wall-run: if near a cave ceiling and rising, allow a short stick.
    const playerWorldCenter = worldOffset + player.x + player.w * 0.5;
    const cave = getCaveAt(playerWorldCenter);
    if (cave && wallRunFrames === 0 && wallRunCooldown === 0 && !player.onGround) {
      const ceilingWave = Math.sin(playerWorldCenter * 0.04 + cave.phase) * cave.amplitude;
      const ceilingY = cave.baseCeiling + ceilingWave;
      if (player.y < ceilingY + 60 && player.y > ceilingY) {
        wallRunFrames = 30;
        wallRunCooldown = 90;
        player.vy = -2;
        sfxExt.dash();
        return;
      }
    }
    if (player.onGround || coyoteFrames > 0) {
      player.jumpsLeft = getMod().noDoubleJump ? 1 : 2;
      doJump();
      return;
    }
    if (player.jumpsLeft > 0 && !getMod().noDoubleJump) {
      doJump();
      return;
    }
    // Buffer the jump for ~6 frames so a too-early press still lands.
    jumpBufferFrames = 6;
  }

  function startDuck() {
    isDucking = true;
  }
  function endDuck() {
    isDucking = false;
  }

  function startDash() {
    if (!gameStarted || gameOver || paused) return;
    if (dashCooldown > 0 || dashFrames > 0) return;
    dashFrames = 18;
    dashCooldown = 90;
    sfxExt.dash();
    spawnBurst(player.x, player.y + player.h / 2, 8, '#ffffff');
  }

  function setPaused(next) {
    if (!gameStarted || gameOver) return;
    if (paused === next) return;
    paused = next;
    pauseOverlay.classList.toggle('active', paused);
    if (paused) {
      if (rafId !== null) {
        cancelAnimationFrame(rafId);
        rafId = null;
      }
    } else {
      scheduleLoop();
    }
  }

  function togglePause() {
    setPaused(!paused);
  }

  if (pauseResumeBtn) {
    pauseResumeBtn.addEventListener('click', () => setPaused(false));
  }
  if (pauseMenuBtn) {
    pauseMenuBtn.addEventListener('click', returnToStartMenu);
  }

  // ---------- Input ----------

  // Skip game key handling when focus is on a form control inside the start
  // overlay — otherwise space/arrows/shift hijack the run-option pulldowns
  // (toggling Daily Seed, navigating Modifier/Skin selects).
  function isFormElementFocused() {
    const el = document.activeElement;
    if (!el || el === document.body) return false;
    const tag = el.tagName;
    if (tag === 'INPUT' || tag === 'SELECT' || tag === 'TEXTAREA') return true;
    return false;
  }

  window.addEventListener('keydown', (e) => {
    if (!scoreModal.hidden) return;
    if (isFormElementFocused()) return;
    const key = e.key.toLowerCase();
    if (key === ' ' || key === 'arrowup' || key === 'w') {
      e.preventDefault();
      jump();
    }
    if (key === 'arrowdown' || key === 's') {
      e.preventDefault();
      startDuck();
    }
    if (key === 'shift') {
      e.preventDefault();
      startDash();
    }
    if (gameOver && key === 'r') {
      resetGame();
    }
    if (key === 'p' || key === 'escape') {
      e.preventDefault();
      togglePause();
    }
    if (key === 'm') {
      muted = !muted;
      saveSettings({ muted });
      applyMusicMuted();
      musicBtn.textContent = muted
        ? 'Play Music'
        : music.paused
          ? 'Tap to Enable Music'
          : 'Music On';
    }
  });

  window.addEventListener('keyup', (e) => {
    const key = e.key.toLowerCase();
    if (key === 'arrowdown' || key === 's') endDuck();
  });

  // Touch: tap = jump, swipe down = duck (held), swipe right = dash.
  let touchStartX = 0;
  let touchStartY = 0;
  let touchActive = false;
  canvas.addEventListener('pointerdown', (e) => {
    touchActive = true;
    touchStartX = e.clientX;
    touchStartY = e.clientY;
    jump();
  });
  canvas.addEventListener('pointermove', (e) => {
    if (!touchActive) return;
    const dx = e.clientX - touchStartX;
    const dy = e.clientY - touchStartY;
    if (dy > 30 && Math.abs(dy) > Math.abs(dx)) {
      startDuck();
    }
    if (dx > 50 && Math.abs(dx) > Math.abs(dy)) {
      startDash();
      touchActive = false;
    }
  });
  canvas.addEventListener('pointerup', () => {
    touchActive = false;
    endDuck();
  });
  canvas.addEventListener('pointercancel', () => {
    touchActive = false;
    endDuck();
  });

  document.addEventListener('visibilitychange', () => {
    if (document.hidden && gameStarted && !gameOver) setPaused(true);
  });

  // ---------- Boot ----------

  initTerrain();
  const initialGround = getTerrainHeight(player.x + player.w * 0.5) || baseGroundY;
  player.y = initialGround - player.h;

  updateHud();
  setScoreSubmissionState(false);
  fetchLeaderboard();

  // Visibility-aware refresh: only poll the leaderboard while the tab is
  // visible. Re-fetch immediately on visibility regain so users returning to
  // the tab see fresh scores without waiting for the next tick.
  const LEADERBOARD_REFRESH_MS = 60000;
  let leaderboardTimer = null;

  function startLeaderboardPolling() {
    if (leaderboardTimer != null) return;
    leaderboardTimer = setInterval(fetchLeaderboard, LEADERBOARD_REFRESH_MS);
  }

  function stopLeaderboardPolling() {
    if (leaderboardTimer == null) return;
    clearInterval(leaderboardTimer);
    leaderboardTimer = null;
  }

  if (!document.hidden) startLeaderboardPolling();

  document.addEventListener('visibilitychange', () => {
    if (document.hidden) {
      stopLeaderboardPolling();
    } else {
      fetchLeaderboard();
      startLeaderboardPolling();
    }
  });

  render();

  // Wire run-option controls to settings before first start.
  if (modifierSelect) {
    activeModifier = settings.modifier && MODIFIERS[settings.modifier] ? settings.modifier : 'none';
    modifierSelect.value = activeModifier;
    modifierSelect.addEventListener('change', () => {
      activeModifier = modifierSelect.value;
      saveSettings({ modifier: activeModifier });
    });
  }
  if (skinSelect) {
    populateSkinSelect();
    skinSelect.addEventListener('change', () => {
      if (!isSkinUnlocked(skinSelect.value)) {
        skinSelect.value = activeSkin;
        return;
      }
      activeSkin = skinSelect.value;
      saveSettings({ skin: activeSkin });
    });
  }
  if (dailyToggle) {
    dailyToggle.checked = false;
    dailyToggle.addEventListener('change', () => {
      dailySeedActive = dailyToggle.checked;
      // Prime the seed early so startGame() doesn't pay the round trip.
      if (dailySeedActive) ensureDailySeed().catch(() => {});
    });
  }

  async function startGame() {
    // Apply chosen options for this run.
    dailySeedActive = !!(dailyToggle && dailyToggle.checked);
    activeModifier = modifierSelect ? modifierSelect.value : 'none';
    activeSkin = skinSelect && isSkinUnlocked(skinSelect.value) ? skinSelect.value : 'default';
    if (dailySeedActive) {
      try {
        await ensureDailySeed();
      } catch {
        // Fall through to local fallback so the player isn't blocked on a
        // network hiccup; dailySeedValue() handles the offline case.
      }
    }
    startOverlay.classList.add('hidden');
    gameStarted = true;
    useSeededRng = dailySeedActive;
    if (useSeededRng) setRngSeed(dailySeedValue());
    // Reset terrain with new RNG so the seed actually matters from frame zero.
    initTerrain();
    const sg = getTerrainHeight(player.x + player.w * 0.5) || baseGroundY;
    player.y = sg - player.h;
    scheduleLoop();
  }

  startBtn.addEventListener('click', startGame);

  window.addEventListener(
    'keydown',
    (e) => {
      if (!gameStarted) {
        // Don't hijack space/arrows when the user is interacting with a
        // run-option pulldown (Daily Seed checkbox / Modifier / Skin select).
        if (isFormElementFocused()) return;
        const k = e.key.toLowerCase();
        if (k === ' ' || k === 'arrowup' || k === 'w') {
          e.preventDefault();
          startGame();
        }
      }
    },
    { capture: true }
  );

  // ---------- Fullscreen / Scroll-lock ----------

  const fullscreenBtn = document.getElementById('fullscreenBtn');

  function isFullscreenSupported() {
    const el = document.documentElement;
    return !!(el.requestFullscreen || el.webkitRequestFullscreen);
  }

  function isFullscreen() {
    return !!(document.fullscreenElement || document.webkitFullscreenElement);
  }

  const FS_ENTER_SVG =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" width="20" height="20"><path d="M7 14H5v5h5v-2H7v-3zm-2-4h2V7h3V5H5v5zm12 7h-3v2h5v-5h-2v3zM14 5v2h3v3h2V5h-5z"/></svg>';
  const FS_EXIT_SVG =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" width="20" height="20"><path d="M5 16h3v3h2v-5H5v2zm3-8H5v2h5V5H8v3zm6 11h2v-3h3v-2h-5v5zm2-11V5h-2v5h5V8h-3z"/></svg>';
  const SCROLL_LOCK_SVG =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" width="20" height="20"><path d="M18 8h-1V6c0-2.76-2.24-5-5-5S7 3.24 7 6v2H6c-1.1 0-2 .9-2 2v10c0 1.1.9 2 2 2h12c1.1 0 2-.9 2-2V10c0-1.1-.9-2-2-2zm-6 9c-1.1 0-2-.9-2-2s.9-2 2-2 2 .9 2 2-.9 2-2 2zm3.1-9H8.9V6c0-1.71 1.39-3.1 3.1-3.1 1.71 0 3.1 1.39 3.1 3.1v2z"/></svg>';
  const SCROLL_UNLOCK_SVG =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" width="20" height="20"><path d="M12 1C9.24 1 7 3.24 7 6v2H6c-1.1 0-2 .9-2 2v10c0 1.1.9 2 2 2h12c1.1 0 2-.9 2-2V10c0-1.1-.9-2-2-2H9V6c0-1.66 1.34-3 3-3 1.66 0 3 1.34 3 3h2c0-2.76-2.24-5-5-5zm0 15c-1.1 0-2-.9-2-2s.9-2 2-2 2 .9 2 2-.9 2-2 2z"/></svg>';

  if (isFullscreenSupported()) {
    function updateFullscreenBtn() {
      fullscreenBtn.innerHTML = isFullscreen() ? FS_EXIT_SVG : FS_ENTER_SVG;
      fullscreenBtn.setAttribute(
        'aria-label',
        isFullscreen() ? 'Exit full screen' : 'Enter full screen'
      );
      document.body.classList.toggle('game-fullscreen', isFullscreen());
    }

    fullscreenBtn.style.display = 'inline-block';
    updateFullscreenBtn();

    fullscreenBtn.addEventListener('click', () => {
      if (!isFullscreen()) {
        const el = document.documentElement;
        if (el.requestFullscreen) el.requestFullscreen();
        else if (el.webkitRequestFullscreen) el.webkitRequestFullscreen();
      } else {
        if (document.exitFullscreen) document.exitFullscreen();
        else if (document.webkitExitFullscreen) document.webkitExitFullscreen();
      }
    });

    document.addEventListener('fullscreenchange', updateFullscreenBtn);
    document.addEventListener('webkitfullscreenchange', updateFullscreenBtn);
  } else if (navigator.maxTouchPoints > 0) {
    let scrollLocked = false;
    let savedScrollY = 0;
    const viewportMeta = document.querySelector('meta[name="viewport"]');

    function preventScroll(e) {
      e.preventDefault();
    }
    function preventZoom(e) {
      if (e.touches.length > 1) e.preventDefault();
    }

    function lockBodyScroll() {
      savedScrollY = window.scrollY;
      document.body.style.position = 'fixed';
      document.body.style.top = `-${savedScrollY}px`;
      document.body.style.left = '0';
      document.body.style.right = '0';
      document.body.style.width = '100%';
      document.body.style.overscrollBehavior = 'none';
      document.documentElement.style.overscrollBehavior = 'none';
      document.addEventListener('touchmove', preventScroll, { passive: false });
      document.addEventListener('touchstart', preventZoom, { passive: false });
      if (viewportMeta) {
        viewportMeta.content =
          'width=device-width, initial-scale=1.0, viewport-fit=cover, user-scalable=no, maximum-scale=1.0';
      }
    }

    function unlockBodyScroll() {
      document.body.style.position = '';
      document.body.style.top = '';
      document.body.style.left = '';
      document.body.style.right = '';
      document.body.style.width = '';
      document.body.style.overscrollBehavior = '';
      document.documentElement.style.overscrollBehavior = '';
      document.removeEventListener('touchmove', preventScroll);
      document.removeEventListener('touchstart', preventZoom);
      if (viewportMeta) {
        viewportMeta.content = 'width=device-width, initial-scale=1.0, viewport-fit=cover';
      }
      window.scrollTo(0, savedScrollY);
    }

    function updateScrollLockBtn() {
      fullscreenBtn.innerHTML = scrollLocked ? SCROLL_LOCK_SVG : SCROLL_UNLOCK_SVG;
      fullscreenBtn.setAttribute('aria-label', scrollLocked ? 'Unlock scroll' : 'Lock scroll');
      fullscreenBtn.dataset.locked = scrollLocked;
    }

    fullscreenBtn.style.display = 'inline-block';
    updateScrollLockBtn();

    fullscreenBtn.addEventListener('click', () => {
      scrollLocked = !scrollLocked;
      if (scrollLocked) {
        lockBodyScroll();
      } else {
        unlockBodyScroll();
      }
      updateScrollLockBtn();
    });

    window.addEventListener('orientationchange', () => {
      if (scrollLocked) {
        scrollLocked = false;
        unlockBodyScroll();
        updateScrollLockBtn();
      }
    });
  }

  // ---------- PWA install prompt ----------

  let deferredInstallPrompt = null;
  const installBtn = document.getElementById('installBtn');

  window.addEventListener('beforeinstallprompt', (e) => {
    e.preventDefault();
    deferredInstallPrompt = e;
    installBtn.style.display = 'inline-block';
  });

  installBtn.addEventListener('click', () => {
    if (!deferredInstallPrompt) return;
    deferredInstallPrompt.prompt();
    deferredInstallPrompt.userChoice.then(() => {
      deferredInstallPrompt = null;
      installBtn.style.display = 'none';
    });
  });

  window.addEventListener('appinstalled', () => {
    deferredInstallPrompt = null;
    installBtn.style.display = 'none';
  });

  // ---------- Service worker ----------

  if ('serviceWorker' in navigator) {
    window.addEventListener('load', () => {
      navigator.serviceWorker
        .register('/sw.js')
        .then((reg) => {
          reg.update();
          reg.onupdatefound = () => {
            const newWorker = reg.installing;
            newWorker.onstatechange = () => {
              if (newWorker.state === 'installed' && navigator.serviceWorker.controller) {
                window.location.reload();
              }
            };
          };
        })
        .catch((error) => {
          console.warn('Service worker registration failed:', error);
        });
    });
  }
})();
