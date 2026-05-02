<?php
header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');
header("Content-Security-Policy: default-src 'none'");
header('X-Content-Type-Options: nosniff');
header('X-Frame-Options: DENY');
header('Referrer-Policy: no-referrer');

// CORS allowlist. Defaults to same-origin only. Set the ALLOWED_ORIGINS
// environment variable (comma-separated) to permit cross-origin API access.
$allowedOriginsEnv = getenv('ALLOWED_ORIGINS') ?: '';
$ALLOWED_ORIGINS = array_filter(array_map('trim', explode(',', $allowedOriginsEnv)));
$requestOrigin = $_SERVER['HTTP_ORIGIN'] ?? '';
if ($requestOrigin !== '' && in_array($requestOrigin, $ALLOWED_ORIGINS, true)) {
    header('Access-Control-Allow-Origin: ' . $requestOrigin);
    header('Vary: Origin');
    header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
    header('Access-Control-Allow-Headers: Content-Type');
    header('Access-Control-Max-Age: 600');
}

// Persisted state lives in a writable directory (mounted via Docker so the
// app's read-only root filesystem doesn't block writes). Override paths via
// DATA_DIR or the per-file env vars for non-Docker deployments.
$DATA_DIR = getenv('DATA_DIR') ?: '/app/data';
if (!is_dir($DATA_DIR)) {
    @mkdir($DATA_DIR, 0755, true);
}
define('LEADERBOARD_FILE', getenv('LEADERBOARD_FILE') ?: $DATA_DIR . '/leaderboard.txt');
define('LEADERBOARD_DB',   getenv('LEADERBOARD_DB')   ?: $DATA_DIR . '/leaderboard.sqlite');
define('RATE_LIMIT_FILE',  getenv('RATE_LIMIT_FILE')  ?: $DATA_DIR . '/rate_limit.txt');
define('NONCE_FILE',       getenv('NONCE_FILE')       ?: $DATA_DIR . '/nonces.txt');
const MAX_PER_CATEGORY   = 10;    // top-N retained per modifier category
const MAX_SCORE          = 999999;
const MAX_NAME_LENGTH    = 24;
const MAX_BODY_BYTES     = 10240; // 10 KB
const RATE_LIMIT_MAX     = 5;     // max POST submissions per window
const RATE_LIMIT_WINDOW  = 60;    // seconds
const NONCE_LIFETIME     = 600;   // seconds a nonce remains valid (10 min)
const NONCE_MIN_AGE      = 4;     // submissions must wait at least this long after issuance
const NONCE_MAX_TRACKED  = 4096;  // hard cap to keep the nonce file bounded

// Modifier categories. 'og' is reserved for legacy entries from the original
// distance-only scoring system; everything else maps to a current run modifier.
const VALID_MODIFIERS = ['og', 'none', 'hardcore', 'bitrush', 'featherfall', 'glasscannon'];

function send_json(int $statusCode, array $payload): void {
    http_response_code($statusCode);
    echo json_encode($payload);
    exit;
}

function get_client_ip(): string {
    // Only trust REMOTE_ADDR. Never X-Forwarded-For without a verified trusted proxy.
    return $_SERVER['REMOTE_ADDR'] ?? '0.0.0.0';
}

/**
 * Import scores from the legacy flat file `leaderboard.txt` into the given
 * SQLite handle. Called whenever the `scores` table is empty so a redeploy
 * (or a wiped DB) can recover from the flat file if it's still around.
 *
 * Returns the number of rows imported. Leaves `leaderboard.txt` in place so
 * it can act as a recovery source on future cold starts.
 */
function import_leaderboard_txt(PDO $pdo): int {
    if (!file_exists(LEADERBOARD_FILE)) {
        return 0;
    }

    $contents = @file_get_contents(LEADERBOARD_FILE);
    if (!is_string($contents) || trim($contents) === '') {
        return 0;
    }

    $insert   = $pdo->prepare('INSERT INTO scores (name, score, saved_at, modifier) VALUES (?, ?, ?, ?)');
    $imported = 0;

    $pdo->beginTransaction();
    try {
        foreach (explode("\n", trim($contents)) as $line) {
            $parts = explode('|', $line);
            if (count($parts) < 3) {
                continue;
            }
            $name    = trim($parts[0]);
            $score   = (int)$parts[1];
            $savedAt = $parts[2];
            // Optional 4th field: modifier. Legacy entries default to 'og'.
            $modifier = isset($parts[3]) ? trim($parts[3]) : 'og';
            if (!in_array($modifier, VALID_MODIFIERS, true)) {
                $modifier = 'og';
            }
            if ($name === '' || $score < 0) {
                continue;
            }
            $insert->execute([$name, $score, $savedAt, $modifier]);
            $imported++;
        }
        $pdo->commit();
    } catch (Throwable $error) {
        $pdo->rollBack();
        return 0;
    }

    return $imported;
}

/**
 * Returns a PDO instance for the SQLite-backed leaderboard, or null if the
 * SQLite PDO driver is unavailable. Creates the schema on first use and, if
 * the `scores` table is empty, imports any existing `leaderboard.txt` as a
 * recovery / migration step.
 */
function get_db(): ?PDO {
    static $pdo = null;
    static $tried = false;

    if ($tried) {
        return $pdo;
    }
    $tried = true;

    if (!class_exists('PDO') || !in_array('sqlite', PDO::getAvailableDrivers(), true)) {
        return null;
    }

    try {
        $pdo = new PDO('sqlite:' . LEADERBOARD_DB);
        $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
        $pdo->exec('PRAGMA journal_mode = WAL');
        $pdo->exec('PRAGMA synchronous = NORMAL');
        $pdo->exec(
            'CREATE TABLE IF NOT EXISTS scores (
                id       INTEGER PRIMARY KEY AUTOINCREMENT,
                name     TEXT    NOT NULL,
                score    INTEGER NOT NULL,
                saved_at TEXT    NOT NULL,
                modifier TEXT    NOT NULL DEFAULT \'og\'
            )'
        );
        // Backfill `modifier` column on databases created before categorization
        // landed. Pre-existing rows are treated as 'og' (original game).
        $columns = $pdo->query("PRAGMA table_info('scores')")->fetchAll(PDO::FETCH_ASSOC);
        $hasModifier = false;
        foreach ($columns as $col) {
            if (($col['name'] ?? '') === 'modifier') {
                $hasModifier = true;
                break;
            }
        }
        if (!$hasModifier) {
            $pdo->exec("ALTER TABLE scores ADD COLUMN modifier TEXT NOT NULL DEFAULT 'og'");
            $pdo->exec("UPDATE scores SET modifier = 'og' WHERE modifier IS NULL OR modifier = ''");
        }
        $pdo->exec('CREATE INDEX IF NOT EXISTS idx_scores_score ON scores (score DESC, saved_at ASC)');
        $pdo->exec('CREATE INDEX IF NOT EXISTS idx_scores_modifier ON scores (modifier, score DESC, saved_at ASC)');

        // If the scores table is empty, try to seed it from the legacy flat
        // file. This handles both first-time migrations from a flat-file
        // deployment and any later cold start where SQLite was reset but the
        // .txt file is still around.
        $existing = (int)$pdo->query('SELECT COUNT(*) FROM scores')->fetchColumn();
        if ($existing === 0) {
            import_leaderboard_txt($pdo);
        }
    } catch (Throwable $error) {
        $pdo = null;
    }

    return $pdo;
}

function check_rate_limit(): void {
    $ipHash = hash('sha256', get_client_ip());
    $now    = time();

    $handle = @fopen(RATE_LIMIT_FILE, 'c+');
    if ($handle === false) {
        return; // Fail open: if the rate-limit file is unavailable, allow the request.
    }

    if (!flock($handle, LOCK_EX)) {
        fclose($handle);
        return; // Fail open on lock failure.
    }

    $rawContents = stream_get_contents($handle);
    $windowStart = $now - RATE_LIMIT_WINDOW;
    $ipCount     = 0;
    $kept        = [];

    if ($rawContents !== false && trim($rawContents) !== '') {
        foreach (explode("\n", trim($rawContents)) as $line) {
            $parts = explode('|', $line, 2);
            if (count($parts) !== 2) {
                continue;
            }
            $entryHash = $parts[0];
            $entryTs   = (int)$parts[1];

            if ($entryTs < $windowStart) {
                continue; // Prune expired entries.
            }

            $kept[] = $line;
            if ($entryHash === $ipHash) {
                $ipCount++;
            }
        }
    }

    if ($ipCount >= RATE_LIMIT_MAX) {
        flock($handle, LOCK_UN);
        fclose($handle);
        send_json(429, ['error' => 'Too many requests. Please wait before submitting again.']);
    }

    $kept[] = $ipHash . '|' . $now;
    $payload = implode("\n", $kept);

    rewind($handle);
    ftruncate($handle, 0);
    fwrite($handle, $payload);
    fflush($handle);
    flock($handle, LOCK_UN);
    fclose($handle);
}

function ensure_leaderboard_file_exists(): void {
    if (file_exists(LEADERBOARD_FILE)) {
        return;
    }

    $handle = fopen(LEADERBOARD_FILE, 'c+');
    if ($handle === false) {
        send_json(500, ['error' => 'Leaderboard unavailable.']);
    }

    fclose($handle);
    chmod(LEADERBOARD_FILE, 0644); // owner rw, group/others read-only
}

function clean_player_name($rawName): string {
    // Allow only printable ASCII: letters, digits, spaces, and a limited punctuation set.
    $name = preg_replace('/[^a-zA-Z0-9 .\'\\-_!?@#*()+]/', '', (string)$rawName);
    $name = trim($name ?? '');

    if (function_exists('mb_substr')) {
        return mb_substr($name, 0, MAX_NAME_LENGTH);
    }

    return substr($name, 0, MAX_NAME_LENGTH);
}

function read_leaderboard(): array {
    $db = get_db();
    if ($db !== null) {
        $stmt = $db->query('SELECT name, score, saved_at, modifier FROM scores');
        $entries = [];
        foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
            $modifier = (string)($row['modifier'] ?? 'og');
            if (!in_array($modifier, VALID_MODIFIERS, true)) {
                $modifier = 'og';
            }
            $entries[] = [
                'name'     => $row['name'],
                'score'    => (int)$row['score'],
                'savedAt'  => $row['saved_at'],
                'modifier' => $modifier,
            ];
        }
        return $entries;
    }

    ensure_leaderboard_file_exists();

    $rawContents = file_get_contents(LEADERBOARD_FILE);
    if ($rawContents === false) {
        send_json(500, ['error' => 'Leaderboard unavailable.']);
    }

    $raw = trim($rawContents);
    if ($raw === '') {
        return [];
    }

    $entries = [];
    foreach (explode("\n", $raw) as $line) {
        $parts = explode('|', $line);
        if (count($parts) < 3) {
            continue;
        }

        $name    = trim($parts[0]);
        $score   = (int)$parts[1];
        $savedAt = $parts[2];
        // Optional 4th field: modifier. Legacy rows are categorized as 'og'.
        $modifier = isset($parts[3]) ? trim($parts[3]) : 'og';
        if (!in_array($modifier, VALID_MODIFIERS, true)) {
            $modifier = 'og';
        }

        if ($name === '' || $score < 0) {
            continue;
        }

        $entries[] = [
            'name'     => $name,
            'score'    => $score,
            'savedAt'  => $savedAt,
            'modifier' => $modifier,
        ];
    }

    return $entries;
}

/**
 * Group entries by their `modifier` field, sort each bucket by score (desc)
 * with savedAt (asc) as the tiebreaker, and trim each bucket to MAX_PER_CATEGORY.
 *
 * Categories that don't appear in $entries still show up (as empty arrays) so
 * the client can render a consistent set of sections.
 */
function categorize_leaderboard(array $entries): array {
    $categories = [];
    foreach (VALID_MODIFIERS as $modifier) {
        $categories[$modifier] = [];
    }
    foreach ($entries as $entry) {
        $modifier = $entry['modifier'] ?? 'og';
        if (!in_array($modifier, VALID_MODIFIERS, true)) {
            $modifier = 'og';
        }
        $categories[$modifier][] = $entry;
    }
    foreach ($categories as $modifier => &$bucket) {
        usort($bucket, function ($a, $b) {
            if ($b['score'] !== $a['score']) {
                return $b['score'] <=> $a['score'];
            }
            return strtotime($a['savedAt']) <=> strtotime($b['savedAt']);
        });
        $bucket = array_slice($bucket, 0, MAX_PER_CATEGORY);
    }
    unset($bucket);
    return $categories;
}

/**
 * Flatten categorized entries back to a single trimmed list — used when
 * persisting to the legacy flat file so it stays at the top-N-per-category cap.
 */
function flatten_categories(array $categories): array {
    $flat = [];
    foreach ($categories as $bucket) {
        foreach ($bucket as $entry) {
            $flat[] = $entry;
        }
    }
    return $flat;
}

function encode_leaderboard_rows(array $entries): string {
    $rows = array_map(function ($entry) {
        $modifier = $entry['modifier'] ?? 'og';
        if (!in_array($modifier, VALID_MODIFIERS, true)) {
            $modifier = 'og';
        }
        return sprintf('%s|%d|%s|%s', $entry['name'], (int)$entry['score'], $entry['savedAt'], $modifier);
    }, $entries);

    return implode("\n", $rows);
}

function append_score_with_lock(string $name, int $score, string $savedAt, string $modifier): array {
    $db = get_db();
    if ($db !== null) {
        $insert = $db->prepare('INSERT INTO scores (name, score, saved_at, modifier) VALUES (?, ?, ?, ?)');
        $insert->execute([$name, $score, $savedAt, $modifier]);

        // Trim each category bucket to its top MAX_PER_CATEGORY by (score DESC, saved_at ASC).
        // Done as a single delete that whitelists the per-category top-N IDs.
        $delete = $db->prepare(
            'DELETE FROM scores WHERE id NOT IN (
                SELECT id FROM scores AS s1
                WHERE (
                    SELECT COUNT(*) FROM scores AS s2
                    WHERE s2.modifier = s1.modifier
                      AND (
                        s2.score > s1.score
                        OR (s2.score = s1.score AND s2.saved_at < s1.saved_at)
                        OR (s2.score = s1.score AND s2.saved_at = s1.saved_at AND s2.id < s1.id)
                      )
                ) < :cap
            )'
        );
        $delete->bindValue(':cap', MAX_PER_CATEGORY, PDO::PARAM_INT);
        $delete->execute();

        return read_leaderboard();
    }

    ensure_leaderboard_file_exists();

    $handle = fopen(LEADERBOARD_FILE, 'c+');
    if ($handle === false) {
        send_json(500, ['error' => 'Leaderboard unavailable.']);
    }

    if (!flock($handle, LOCK_EX)) {
        fclose($handle);
        send_json(500, ['error' => 'Leaderboard unavailable.']);
    }

    $rawContents = stream_get_contents($handle);
    if ($rawContents === false) {
        flock($handle, LOCK_UN);
        fclose($handle);
        send_json(500, ['error' => 'Leaderboard unavailable.']);
    }

    $entries = [];
    $raw     = trim($rawContents);
    if ($raw !== '') {
        foreach (explode("\n", $raw) as $line) {
            $parts = explode('|', $line);
            if (count($parts) < 3) {
                continue;
            }

            $entryName     = trim($parts[0]);
            $entryScore    = (int)$parts[1];
            $entrySavedAt  = $parts[2];
            $entryModifier = isset($parts[3]) ? trim($parts[3]) : 'og';
            if (!in_array($entryModifier, VALID_MODIFIERS, true)) {
                $entryModifier = 'og';
            }

            if ($entryName === '' || $entryScore < 0) {
                continue;
            }

            $entries[] = [
                'name'     => $entryName,
                'score'    => $entryScore,
                'savedAt'  => $entrySavedAt,
                'modifier' => $entryModifier,
            ];
        }
    }

    $entries[] = [
        'name'     => $name,
        'score'    => $score,
        'savedAt'  => $savedAt,
        'modifier' => $modifier,
    ];
    $categories = categorize_leaderboard($entries);
    $entries    = flatten_categories($categories);

    $payload = encode_leaderboard_rows($entries);

    rewind($handle);
    if (!ftruncate($handle, 0) || ($payload !== '' && fwrite($handle, $payload) === false)) {
        flock($handle, LOCK_UN);
        fclose($handle);
        send_json(500, ['error' => 'Leaderboard unavailable.']);
    }

    fflush($handle);
    flock($handle, LOCK_UN);
    fclose($handle);

    return $entries;
}

/**
 * Issue a new nonce and persist it. Returns the nonce string.
 *
 * Nonces add a required round-trip before submission, deterring trivial replays
 * and direct-POST scripted spam. They are NOT cryptographic anti-cheat — a JS
 * client cannot keep secrets from a determined attacker.
 */
function issue_nonce(): string {
    $nonce = bin2hex(random_bytes(16));
    $now   = time();

    $handle = @fopen(NONCE_FILE, 'c+');
    if ($handle === false) {
        // Fail open: if we can't persist nonces, still return one so the client flow works.
        return $nonce;
    }

    if (!flock($handle, LOCK_EX)) {
        fclose($handle);
        return $nonce;
    }

    $rawContents = stream_get_contents($handle);
    $cutoff      = $now - NONCE_LIFETIME;
    $kept        = [];

    if ($rawContents !== false && trim($rawContents) !== '') {
        foreach (explode("\n", trim($rawContents)) as $line) {
            $parts = explode('|', $line, 2);
            if (count($parts) !== 2) {
                continue;
            }
            $entryTs = (int)$parts[1];
            if ($entryTs < $cutoff) {
                continue;
            }
            $kept[] = $line;
        }
    }

    $kept[] = $nonce . '|' . $now;

    // Hard cap on tracked entries — drop oldest if we somehow blow past the limit.
    if (count($kept) > NONCE_MAX_TRACKED) {
        $kept = array_slice($kept, -NONCE_MAX_TRACKED);
    }

    rewind($handle);
    ftruncate($handle, 0);
    fwrite($handle, implode("\n", $kept));
    fflush($handle);
    flock($handle, LOCK_UN);
    fclose($handle);

    return $nonce;
}

/**
 * Consume a nonce. Returns true if the nonce existed, was issued at least
 * NONCE_MIN_AGE seconds ago, and is still within NONCE_LIFETIME. The nonce is
 * removed on success.
 */
function consume_nonce(string $nonce): bool {
    if ($nonce === '' || !ctype_xdigit($nonce)) {
        return false;
    }

    $handle = @fopen(NONCE_FILE, 'c+');
    if ($handle === false) {
        // Fail closed: if we cannot validate, reject.
        return false;
    }

    if (!flock($handle, LOCK_EX)) {
        fclose($handle);
        return false;
    }

    $rawContents = stream_get_contents($handle);
    $now         = time();
    $cutoff      = $now - NONCE_LIFETIME;
    $kept        = [];
    $matched     = false;
    $matchTs     = 0;

    if ($rawContents !== false && trim($rawContents) !== '') {
        foreach (explode("\n", trim($rawContents)) as $line) {
            $parts = explode('|', $line, 2);
            if (count($parts) !== 2) {
                continue;
            }
            $entryNonce = $parts[0];
            $entryTs    = (int)$parts[1];

            if ($entryTs < $cutoff) {
                continue; // Expired — drop.
            }

            if (!$matched && hash_equals($entryNonce, $nonce)) {
                $matched = true;
                $matchTs = $entryTs;
                continue; // Consume — do not keep.
            }

            $kept[] = $line;
        }
    }

    rewind($handle);
    ftruncate($handle, 0);
    fwrite($handle, implode("\n", $kept));
    fflush($handle);
    flock($handle, LOCK_UN);
    fclose($handle);

    if (!$matched) {
        return false;
    }

    // Reject submissions that arrive too quickly after issuance — basic anti-script gate.
    return ($now - $matchTs) >= NONCE_MIN_AGE;
}

$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';

if ($method === 'OPTIONS') {
    if ($requestOrigin !== '' && in_array($requestOrigin, $ALLOWED_ORIGINS, true)) {
        http_response_code(204);
        exit;
    }
    send_json(403, ['error' => 'Origin not allowed.']);
}

if ($method === 'GET') {
    $action = $_GET['action'] ?? '';
    if ($action === 'nonce') {
        send_json(200, ['nonce' => issue_nonce()]);
    }
    $categories = categorize_leaderboard(read_leaderboard());
    // `entries` is retained as a flattened convenience for older clients;
    // `categories` carries the per-modifier top-10 buckets.
    send_json(200, [
        'categories' => $categories,
        'entries'    => flatten_categories($categories),
    ]);
}

if ($method === 'POST') {
    check_rate_limit();

    // Enforce body size limit before reading.
    $contentLength = (int)($_SERVER['CONTENT_LENGTH'] ?? 0);
    if ($contentLength > MAX_BODY_BYTES) {
        send_json(413, ['error' => 'Request too large.']);
    }

    $inputHandle = fopen('php://input', 'r');
    if ($inputHandle === false) {
        send_json(500, ['error' => 'Leaderboard unavailable.']);
    }
    $rawBody = stream_get_contents($inputHandle, MAX_BODY_BYTES + 1);
    fclose($inputHandle);

    if ($rawBody === false || strlen($rawBody) > MAX_BODY_BYTES) {
        send_json(413, ['error' => 'Request too large.']);
    }

    $payload = json_decode($rawBody, true);
    if (!is_array($payload)) {
        send_json(400, ['error' => 'Invalid request.']);
    }

    $name  = clean_player_name($payload['name'] ?? '');
    // Accept either `points` (current clients) or `score` (legacy field name).
    $score = $payload['points'] ?? $payload['score'] ?? null;
    $nonce = isset($payload['nonce']) ? (string)$payload['nonce'] : '';
    $modifier = isset($payload['modifier']) ? (string)$payload['modifier'] : 'none';

    if ($name === '') {
        send_json(400, ['error' => 'Player name is required.']);
    }

    // Score must be a whole number in range [0, MAX_SCORE].
    if (
        !is_numeric($score) ||
        (int)$score != $score ||
        (int)$score < 0 ||
        (int)$score > MAX_SCORE
    ) {
        send_json(400, ['error' => 'Score must be a whole number between 0 and ' . MAX_SCORE . '.']);
    }

    // Modifier must be one of the known categories. 'og' is reserved for
    // legacy migration and rejected on direct submission.
    if (!in_array($modifier, VALID_MODIFIERS, true) || $modifier === 'og') {
        send_json(400, ['error' => 'Unknown run modifier.']);
    }

    // Nonce is mandatory. Clients must obtain a single-use nonce via
    // GET ?action=nonce and present it on submission.
    if (!consume_nonce($nonce)) {
        send_json(400, ['error' => 'Submission expired or invalid. Please try again.']);
    }

    $score      = (int)$score;
    $savedAt    = gmdate('c');
    $entries    = append_score_with_lock($name, $score, $savedAt, $modifier);
    $categories = categorize_leaderboard($entries);

    send_json(201, [
        'categories' => $categories,
        'entries'    => flatten_categories($categories),
        'saved'      => [
            'name'     => $name,
            'score'    => $score,
            'points'   => $score,
            'savedAt'  => $savedAt,
            'modifier' => $modifier,
        ],
    ]);
}

header('Allow: GET, POST, OPTIONS');
send_json(405, ['error' => 'Method not allowed.']);
