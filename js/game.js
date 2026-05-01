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

  const canvas = document.getElementById('game');
  const ctx = canvas.getContext('2d');
  const scoreEl = document.getElementById('score');
  const speedEl = document.getElementById('speed');
  const bestEl = document.getElementById('best');
  const music = document.getElementById('bgm');
  const musicBtn = document.getElementById('musicBtn');
  const gameOverOverlay = document.getElementById('gameOverOverlay');
  const pauseOverlay = document.getElementById('pauseOverlay');
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

  let gameStarted = false;
  let paused = false;
  let score = 0;
  let best = Number(localStorage.getItem(BEST_KEY) || 0);
  let speedMult = 1;
  let baseSpeed = 4.2;
  let gameOver = false;
  let groundOffset = 0;
  let sceneryOffset = 0;
  let spawnTimer = 0;
  let scheduledGapPx = 0;
  let worldOffset = 0;
  let latestRunScore = 0;
  let lastSpawnAction = null;
  let queuedSpawnAction = null;

  const gravity = 0.75;
  const player = {
    x: 120,
    y: 0,
    w: 48,
    h: 58,
    vy: 0,
    jumpPower: -14,
    onGround: true,
    jumpsLeft: 2
  };
  const baseGroundY = canvas.height - 72;
  const precipiceFloorY = canvas.height - 1;
  player.y = baseGroundY - player.h;

  const obstacles = [];
  const transitionFrameBudget = {
    start: { jump: 24, stay: 20 },
    jump:  { jump: 22, stay: 44 },
    stay:  { jump: 26, stay: 18 }
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
      stay: { jump: 140, stay: 116 }
    },
    minObstacleGapPxInCave: {
      jump: { jump: 230, stay: 168 },
      stay: { jump: 188, stay: 140 }
    }
  };

  // ---------- Audio ----------

  let audioCtx = null;
  let muted = settings.muted === true;

  function getAudioContext() {
    if (audioCtx) return audioCtx;
    const Ctor = window.AudioContext || window.webkitAudioContext;
    if (!Ctor) return null;
    try { audioCtx = new Ctor(); } catch { audioCtx = null; }
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
    jump:   () => playTone(620, 0.09, 'square', 0.06),
    djump:  () => playTone(820, 0.09, 'square', 0.06),
    death:  () => {
      playTone(180, 0.4, 'sawtooth', 0.09);
      setTimeout(() => playTone(90, 0.5, 'sawtooth', 0.07), 90);
    }
  };

  function applyMusicMuted() {
    music.muted = muted;
    if (muted && !music.paused) music.pause();
  }

  function tryPlayMusic() {
    if (muted) return;
    music.volume = 0.55;
    music.play().then(() => {
      musicBtn.textContent = 'Music On';
    }).catch(() => {
      musicBtn.textContent = 'Tap to Enable Music';
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
      musicBtn.textContent = 'Play Music';
    } else {
      tryPlayMusic();
    }
  });

  applyMusicMuted();
  if (muted) musicBtn.textContent = 'Play Music';

  // ---------- Game over UI ----------

  document.getElementById('gameOverRebootBtn').addEventListener('click', resetGame);
  document.getElementById('gameOverSubmitBtn').addEventListener('click', openScoreModal);

  function setLeaderboardStatus(message) {
    leaderboardStatus.textContent = message;
  }

  function setScoreSubmissionState(isEnabled) {
    document.getElementById('gameOverSubmitBtn').disabled = !isEnabled;
  }

  function renderLeaderboard(entries) {
    leaderboardList.innerHTML = '';
    if (!entries.length) {
      const item = document.createElement('li');
      item.textContent = 'No scores yet. Be the first to upload a run!';
      leaderboardList.appendChild(item);
      return;
    }

    entries.forEach((entry, index) => {
      const item = document.createElement('li');
      item.textContent = `#${index + 1} ${entry.name} — ${Math.floor(entry.score)}m`;
      leaderboardList.appendChild(item);
    });
  }

  async function fetchLeaderboard() {
    try {
      const response = await fetch(leaderboardEndpoint, { cache: 'no-store' });
      if (!response.ok) throw new Error('Could not load leaderboard');
      const payload = await response.json();
      renderLeaderboard(payload.entries || []);
      if (!gameStarted) {
        setLeaderboardStatus('Finish a run, then save your score to the global board.');
      }
    } catch {
      renderLeaderboard([]);
      setLeaderboardStatus('Global leaderboard unavailable. Ensure leaderboard.php is deployed and writable.');
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

  async function submitScore(name, runScore) {
    let body;
    try {
      const nonce = await fetchSubmitNonce();
      body = JSON.stringify({ name, score: runScore, nonce });
    } catch {
      // Server may not yet support nonces; fall back to legacy submission.
      body = JSON.stringify({ name, score: runScore });
    }

    const response = await fetch(leaderboardEndpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body
    });

    const payload = await response.json();
    if (!response.ok) {
      throw new Error(payload.error || 'Unable to save score.');
    }

    return payload.entries || [];
  }

  function openScoreModal() {
    if (!scoreModal.hidden) return;
    scoreModalStatus.textContent = '';
    scoreModalName.value = settings.lastName || '';
    scoreModalDist.textContent = `Distance: ${latestRunScore}m`;
    scoreModalSubmit.disabled = false;
    scoreModal.hidden = false;
    scoreModalName.focus();
  }

  function closeScoreModal() {
    scoreModal.hidden = true;
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
      const entries = await submitScore(name, scoreToSave);
      renderLeaderboard(entries);
      setLeaderboardStatus(`Saved ${scoreToSave}m for ${name}. Reboot and beat it!`);
      setScoreSubmissionState(false);
      saveSettings({ lastName: name });
      closeScoreModal();
    } catch (error) {
      scoreModalStatus.textContent = error.message || 'Unable to save your score.';
      scoreModalSubmit.disabled = false;
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
    nextCaveAt: 360
  };

  function rand(min, max) {
    return min + Math.random() * (max - min);
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
    const wave = Math.sin((worldX * 0.04) + cave.phase) * cave.amplitude;
    return cave.baseCeiling + wave;
  }

  function getPrecipiceNear(worldX, padding = 0) {
    return terrain.precipices.find((drop) => worldX >= drop.start - padding && worldX <= drop.end + padding) || null;
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

      const requiredNextY = previousPoint.y + ((requiredGroundY - previousPoint.y) / t);
      adjustedNextY = Math.max(adjustedNextY, requiredNextY);
    }

    for (let sampleX = previousPoint.x + courseSafety.clearanceSampleStep; sampleX < nextPointX; sampleX += courseSafety.clearanceSampleStep) {
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
    scheduledGapPx = gapPx;
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
          phase: rand(0, Math.PI * 2)
        });
        terrain.nextCaveAt = start + rand(520, 880);
      }

      terrain.slope += rand(-0.36, 0.36);
      terrain.slope = clamp(terrain.slope, -1.8, 1.8);
      terrain.currentY += terrain.slope * terrain.step * 0.25;
      terrain.currentY += (baseGroundY - terrain.currentY) * 0.04;
      terrain.currentY = clamp(terrain.currentY, baseGroundY - 110, baseGroundY + 44);

      if (Math.random() < 0.09) {
        terrain.currentY += rand(-26, 22);
        terrain.currentY = clamp(terrain.currentY, baseGroundY - 110, baseGroundY + 44);
      }

      const previousPoint = terrain.points[terrain.points.length - 1];
      terrain.currentY = enforceJumpClearanceOnSegment(previousPoint, terrain.lastX, terrain.currentY);
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

    const typeRoll = Math.random();
    if (typeRoll < 0.34) {
      return { worldX, y: groundY - 20, w: 28, h: 20, type: 'bug', action: 'jump' };
    }
    if (typeRoll < 0.67) {
      return { worldX, y: groundY - 52, w: 36, h: 52, type: 'server', action: 'jump' };
    }
    return { worldX, y: groundY - 24, w: 62, h: 24, type: 'laser', action: 'jump' };
  }

  function pickRandomAction() {
    return Math.random() < 0.24 ? 'stay' : 'jump';
  }

  function getSpawnDelayMs(previousAction, nextAction) {
    const moveSpeed = baseSpeed * speedMult;
    const baselineFrames = Math.round(23 + Math.random() * 35);
    const randomGapPx = baselineFrames * moveSpeed;
    const minGapPx = getMinGapPx(previousAction, nextAction);
    const maxGapPx = minGapPx + moveSpeed * (16 + Math.random() * 18);
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
      if (candidateEnd <= obstacleStart && (!previous || candidateEnd > previous.worldX + previous.w)) {
        previous = candidate;
      }
    }
    return previous;
  }

  function hasCaveInSpan(worldStart, worldEnd) {
    for (let sampleX = worldStart; sampleX <= worldEnd; sampleX += courseSafety.clearanceSampleStep) {
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
    const requiredLandingBuffer = action === 'stay' ? courseSafety.minLandingBufferForStay : courseSafety.minLandingBuffer;
    const requiredTakeoffBuffer = action === 'stay' ? courseSafety.minTakeoffBufferForStay : courseSafety.minTakeoffBuffer;

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
      for (let sampleX = obstacleEnd + courseSafety.clearanceSampleStep; sampleX <= runoutEnd; sampleX += courseSafety.clearanceSampleStep) {
        lowestRunoutGround = Math.max(lowestRunoutGround, getTerrainHeight(sampleX));
      }

      const downhillAfterStay = lowestRunoutGround - postObstacleGround;
      if (downhillAfterStay > courseSafety.maxDownhillAfterStayObstacle) {
        return false;
      }

      const droneApproachStart = obstacleStart - requiredTakeoffBuffer;
      let peakApproachY = getTerrainHeight(droneApproachStart);
      for (let sampleX = droneApproachStart + courseSafety.clearanceSampleStep; sampleX < obstacleStart; sampleX += courseSafety.clearanceSampleStep) {
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

    if (getPrecipiceNear(obstacleStart, courseSafety.precipiceAvoidanceBuffer) || getPrecipiceNear(obstacleEnd, courseSafety.precipiceAvoidanceBuffer)) {
      return false;
    }

    const adjacentPrecipice = terrain.precipices.find((drop) => (
      obstacleStart >= drop.end && obstacleStart - drop.end < requiredLandingBuffer
    ) || (
      obstacleEnd <= drop.start && drop.start - obstacleEnd < requiredTakeoffBuffer
    ));
    if (adjacentPrecipice) {
      return false;
    }

    const ceilingSampleStart = obstacleStart - player.w;
    const ceilingSampleEnd   = obstacleEnd   + player.w;
    for (let sampleX = ceilingSampleStart; sampleX <= ceilingSampleEnd; sampleX += courseSafety.clearanceSampleStep) {
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

  function scheduleNextObstacle() {
    const moveSpeed = baseSpeed * speedMult;
    const spawnEdgeX = worldOffset + canvas.width + 20;
    const preferredAction = queuedSpawnAction;
    const transitionGapPx = lastSpawnAction ? scheduledGapPx : Number.POSITIVE_INFINITY;

    for (let attempt = 0; attempt < 24; attempt++) {
      const nextAction = attempt === 0 && preferredAction ? preferredAction : pickRandomAction();
      if (!canTransition(lastSpawnAction, nextAction, transitionGapPx)) {
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
      const fallbackNextAction = 'jump';
      applySpawnGap(getSpawnDelayMs(fallbackAction, fallbackNextAction) * moveSpeed * (60 / 1000) + fallbackShiftPx, moveSpeed);
      queuedSpawnAction = fallbackNextAction;
      return;
    }
    const fallbackNextAction = 'jump';
    applySpawnGap(getSpawnDelayMs(fallbackAction, fallbackNextAction) * moveSpeed * (60 / 1000), moveSpeed);
    queuedSpawnAction = fallbackNextAction;
  }

  // ---------- Rendering ----------

  function drawSkyline() {
    const parallax = reduceMotion ? 0.05 : 0.3;
    sceneryOffset += (baseSpeed * speedMult) * parallax;

    for (let i = 0; i < 6; i++) {
      const width = 130;
      const x = (i * 170) - (sceneryOffset % 170);
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
    groundOffset += baseSpeed * speedMult;
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
        const wave = Math.sin((worldX * 0.04) + cave.phase) * cave.amplitude;
        ctx.lineTo(sx, cave.baseCeiling + wave);
      }
      const endWave = Math.sin((cave.end * 0.04) + cave.phase) * cave.amplitude;
      ctx.lineTo(endX, cave.baseCeiling + endWave);
      ctx.lineTo(endX, 0);
      ctx.closePath();
      ctx.fill();
    });
  }

  function drawPlayer() {
    const g = ctx.createLinearGradient(player.x, player.y, player.x + player.w, player.y + player.h);
    g.addColorStop(0, '#2ef8ff');
    g.addColorStop(1, '#8e5cff');
    ctx.fillStyle = g;
    roundRect(ctx, player.x, player.y, player.w, player.h, 10);
    ctx.fill();

    ctx.fillStyle = '#e9f6ff';
    ctx.font = 'bold 15px monospace';
    ctx.fillText('</>', player.x + 7, player.y + 34);
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

  function resetGame() {
    closeScoreModal();
    gameOverOverlay.classList.remove('active');
    pauseOverlay.classList.remove('active');
    paused = false;
    gameStarted = true;
    score = 0;
    speedMult = 1;
    baseSpeed = 4.2;
    gameOver = false;
    spawnTimer = 0;
    scheduledGapPx = 0;
    obstacles.length = 0;
    lastSpawnAction = null;
    queuedSpawnAction = null;
    worldOffset = 0;
    latestRunScore = 0;
    setScoreSubmissionState(false);
    setLeaderboardStatus('Finish a run, then save your score to the global board.');
    fetchLeaderboard();
    initTerrain();
    const spawnGround = getTerrainHeight(player.x + player.w * 0.5) || baseGroundY;
    player.y = spawnGround - player.h;
    player.vy = 0;
    player.onGround = true;
    player.jumpsLeft = 2;
    updateHud();
    requestAnimationFrame(loop);
  }

  function updateHud() {
    scoreEl.textContent = Math.floor(score);
    speedEl.textContent = speedMult.toFixed(1);
    bestEl.textContent = Math.floor(best);
  }

  function update() {
    if (gameOver || paused) return;

    score += 0.2 * speedMult;
    speedMult = Math.min(6, 1 + score / 340);

    const moveSpeed = baseSpeed * speedMult;
    worldOffset += moveSpeed;
    ensureTerrainAhead(worldOffset + canvas.width + 460);

    const pruneX = worldOffset - canvas.width * 3;
    let pruneTo = 0;
    while (pruneTo + 1 < terrain.points.length && terrain.points[pruneTo + 1].x < pruneX) {
      pruneTo++;
    }
    if (pruneTo > 0) terrain.points.splice(0, pruneTo);
    terrain.caves = terrain.caves.filter(c => c.end >= pruneX);
    terrain.precipices = terrain.precipices.filter(p => p.end >= pruneX);

    player.vy += gravity;
    player.y += player.vy;

    const playerWorldCenter = worldOffset + player.x + player.w * 0.5;
    const currentGround = getTerrainHeight(playerWorldCenter);
    if (isInPrecipice(playerWorldCenter)) {
      player.onGround = false;
      if (player.y + player.h >= currentGround) {
        gameOver = true;
      }
    } else if (player.y >= currentGround - player.h) {
      player.y = currentGround - player.h;
      player.vy = 0;
      player.onGround = true;
      player.jumpsLeft = 2;
    } else {
      player.onGround = false;
    }

    const activeCave = getCaveAt(playerWorldCenter);
    if (activeCave) {
      const ceilingWave = Math.sin((playerWorldCenter * 0.04) + activeCave.phase) * activeCave.amplitude;
      const ceilingY = activeCave.baseCeiling + ceilingWave;
      if (player.y <= ceilingY) {
        gameOver = true;
      }
    }

    if (player.y > canvas.height + 80) {
      gameOver = true;
    }

    spawnTimer -= 16.7;
    if (spawnTimer <= 0) {
      scheduleNextObstacle();
    }

    for (let i = obstacles.length - 1; i >= 0; i--) {
      const ob = obstacles[i];
      const obScreenX = ob.worldX - worldOffset;

      const hit = player.x < obScreenX + ob.w &&
                  player.x + player.w > obScreenX &&
                  player.y < ob.y + ob.h &&
                  player.y + player.h > ob.y;

      if (hit) {
        gameOver = true;
        finalizeRun();
        return;
      }

      if (obScreenX + ob.w < -20) {
        obstacles.splice(i, 1);
      }
    }

    if (gameOver) finalizeRun();

    updateHud();
  }

  function finalizeRun() {
    best = Math.max(best, score);
    localStorage.setItem(BEST_KEY, String(Math.floor(best)));
    latestRunScore = Math.floor(score);
    setScoreSubmissionState(latestRunScore > 0);
    setLeaderboardStatus(`Run ended at ${latestRunScore}m. Submit your score or press R to restart.`);
    sfx.death();
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
    ctx.fillText('Press R to restart  ·  Use Submit Score to save', canvas.width / 2, canvas.height / 2 + 48);
    ctx.textAlign = 'left';
  }

  function render() {
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    drawSkyline();
    drawGround();
    drawPlayer();
    obstacles.forEach((ob) => {
      const screenObstacle = { ...ob, x: ob.worldX - worldOffset };
      drawObstacle(screenObstacle);
    });
    if (gameOver) {
      drawGameOver();
      gameOverOverlay.classList.add('active');
    }
  }

  function loop() {
    update();
    render();
    if (!gameOver) requestAnimationFrame(loop);
  }

  function jump() {
    if (!gameStarted || gameOver || paused || player.jumpsLeft <= 0) return;
    player.vy = player.jumpPower;
    player.onGround = false;
    player.jumpsLeft -= 1;
    (player.jumpsLeft === 1 ? sfx.jump : sfx.djump)();
  }

  function setPaused(next) {
    if (!gameStarted || gameOver) return;
    if (paused === next) return;
    paused = next;
    pauseOverlay.classList.toggle('active', paused);
    if (!paused) requestAnimationFrame(loop);
  }

  function togglePause() {
    setPaused(!paused);
  }

  // ---------- Input ----------

  window.addEventListener('keydown', (e) => {
    if (!scoreModal.hidden) return;
    const key = e.key.toLowerCase();
    if (key === ' ' || key === 'arrowup' || key === 'w') {
      e.preventDefault();
      jump();
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
      musicBtn.textContent = muted ? 'Play Music' : (music.paused ? 'Tap to Enable Music' : 'Music On');
    }
  });

  canvas.addEventListener('pointerdown', jump);

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
  setInterval(fetchLeaderboard, 60000);

  render();

  function startGame() {
    startOverlay.classList.add('hidden');
    gameStarted = true;
    requestAnimationFrame(loop);
  }

  startBtn.addEventListener('click', startGame);

  window.addEventListener('keydown', (e) => {
    if (!gameStarted) {
      const k = e.key.toLowerCase();
      if (k === ' ' || k === 'arrowup' || k === 'w') {
        e.preventDefault();
        startGame();
      }
    }
  }, { capture: true });

  // ---------- Fullscreen / Scroll-lock ----------

  const fullscreenBtn = document.getElementById('fullscreenBtn');

  function isFullscreenSupported() {
    const el = document.documentElement;
    return !!(el.requestFullscreen || el.webkitRequestFullscreen);
  }

  function isFullscreen() {
    return !!(document.fullscreenElement || document.webkitFullscreenElement);
  }

  const FS_ENTER_SVG     = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" width="20" height="20"><path d="M7 14H5v5h5v-2H7v-3zm-2-4h2V7h3V5H5v5zm12 7h-3v2h5v-5h-2v3zM14 5v2h3v3h2V5h-5z"/></svg>';
  const FS_EXIT_SVG      = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" width="20" height="20"><path d="M5 16h3v3h2v-5H5v2zm3-8H5v2h5V5H8v3zm6 11h2v-3h3v-2h-5v5zm2-11V5h-2v5h5V8h-3z"/></svg>';
  const SCROLL_LOCK_SVG   = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" width="20" height="20"><path d="M18 8h-1V6c0-2.76-2.24-5-5-5S7 3.24 7 6v2H6c-1.1 0-2 .9-2 2v10c0 1.1.9 2 2 2h12c1.1 0 2-.9 2-2V10c0-1.1-.9-2-2-2zm-6 9c-1.1 0-2-.9-2-2s.9-2 2-2 2 .9 2 2-.9 2-2 2zm3.1-9H8.9V6c0-1.71 1.39-3.1 3.1-3.1 1.71 0 3.1 1.39 3.1 3.1v2z"/></svg>';
  const SCROLL_UNLOCK_SVG = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" width="20" height="20"><path d="M12 1C9.24 1 7 3.24 7 6v2H6c-1.1 0-2 .9-2 2v10c0 1.1.9 2 2 2h12c1.1 0 2-.9 2-2V10c0-1.1-.9-2-2-2H9V6c0-1.66 1.34-3 3-3 1.66 0 3 1.34 3 3h2c0-2.76-2.24-5-5-5zm0 15c-1.1 0-2-.9-2-2s.9-2 2-2 2 .9 2 2-.9 2-2 2z"/></svg>';

  if (isFullscreenSupported()) {
    function updateFullscreenBtn() {
      fullscreenBtn.innerHTML = isFullscreen() ? FS_EXIT_SVG : FS_ENTER_SVG;
      fullscreenBtn.setAttribute('aria-label', isFullscreen() ? 'Exit full screen' : 'Enter full screen');
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

    function preventScroll(e) { e.preventDefault(); }
    function preventZoom(e) { if (e.touches.length > 1) e.preventDefault(); }

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
        viewportMeta.content = 'width=device-width, initial-scale=1.0, viewport-fit=cover, user-scalable=no, maximum-scale=1.0';
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
      navigator.serviceWorker.register('/sw.js')
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
