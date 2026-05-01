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

const LEADERBOARD_FILE   = __DIR__ . '/leaderboard.txt';
const LEADERBOARD_DB     = __DIR__ . '/leaderboard.sqlite';
const RATE_LIMIT_FILE    = __DIR__ . '/rate_limit.txt';
const NONCE_FILE         = __DIR__ . '/nonces.txt';
const MAX_ENTRIES        = 100;
const MAX_SCORE          = 999999;
const MAX_NAME_LENGTH    = 24;
const MAX_BODY_BYTES     = 10240; // 10 KB
const RATE_LIMIT_MAX     = 5;     // max POST submissions per window
const RATE_LIMIT_WINDOW  = 60;    // seconds
const NONCE_LIFETIME     = 600;   // seconds a nonce remains valid (10 min)
const NONCE_MIN_AGE      = 4;     // submissions must wait at least this long after issuance
const NONCE_MAX_TRACKED  = 4096;  // hard cap to keep the nonce file bounded

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
 * Returns a PDO instance for the SQLite-backed leaderboard, or null if the
 * SQLite PDO driver is unavailable. Creates the schema on first use and
 * imports any pre-existing flat-file leaderboard.txt as a one-time migration.
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
                saved_at TEXT    NOT NULL
            )'
        );
        $pdo->exec('CREATE INDEX IF NOT EXISTS idx_scores_score ON scores (score DESC, saved_at ASC)');

        // One-time import from the legacy flat file if present.
        if (file_exists(LEADERBOARD_FILE)) {
            $row = $pdo->query('SELECT COUNT(*) FROM scores')->fetchColumn();
            if ((int)$row === 0) {
                $imported = 0;
                $insert = $pdo->prepare('INSERT INTO scores (name, score, saved_at) VALUES (?, ?, ?)');
                $contents = @file_get_contents(LEADERBOARD_FILE);
                if (is_string($contents) && trim($contents) !== '') {
                    $pdo->beginTransaction();
                    foreach (explode("\n", trim($contents)) as $line) {
                        $parts = explode('|', $line);
                        if (count($parts) < 3) {
                            continue;
                        }
                        $name    = trim($parts[0]);
                        $score   = (int)$parts[1];
                        $savedAt = $parts[2];
                        if ($name === '' || $score < 0) {
                            continue;
                        }
                        $insert->execute([$name, $score, $savedAt]);
                        $imported++;
                    }
                    $pdo->commit();
                }
                if ($imported > 0) {
                    @rename(LEADERBOARD_FILE, LEADERBOARD_FILE . '.imported');
                }
            }
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
        $stmt = $db->query(
            'SELECT name, score, saved_at FROM scores ORDER BY score DESC, saved_at ASC LIMIT ' . MAX_ENTRIES
        );
        $entries = [];
        foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
            $entries[] = [
                'name'    => $row['name'],
                'score'   => (int)$row['score'],
                'savedAt' => $row['saved_at']
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

        if ($name === '' || $score < 0) {
            continue;
        }

        $entries[] = [
            'name'    => $name,
            'score'   => $score,
            'savedAt' => $savedAt
        ];
    }

    return $entries;
}

function sort_leaderboard(array $entries): array {
    usort($entries, function ($a, $b) {
        if ($b['score'] !== $a['score']) {
            return $b['score'] <=> $a['score'];
        }

        return strtotime($a['savedAt']) <=> strtotime($b['savedAt']);
    });

    return array_slice($entries, 0, MAX_ENTRIES);
}

function encode_leaderboard_rows(array $entries): string {
    $rows = array_map(function ($entry) {
        return sprintf('%s|%d|%s', $entry['name'], (int)$entry['score'], $entry['savedAt']);
    }, $entries);

    return implode("\n", $rows);
}

function append_score_with_lock(string $name, int $score, string $savedAt): array {
    $db = get_db();
    if ($db !== null) {
        $insert = $db->prepare('INSERT INTO scores (name, score, saved_at) VALUES (?, ?, ?)');
        $insert->execute([$name, $score, $savedAt]);

        // Trim the table to MAX_ENTRIES — keep top scores by (score DESC, saved_at ASC).
        $db->exec(
            'DELETE FROM scores WHERE id NOT IN (
                SELECT id FROM scores ORDER BY score DESC, saved_at ASC LIMIT ' . MAX_ENTRIES . '
            )'
        );

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

            $entryName    = trim($parts[0]);
            $entryScore   = (int)$parts[1];
            $entrySavedAt = $parts[2];

            if ($entryName === '' || $entryScore < 0) {
                continue;
            }

            $entries[] = [
                'name'    => $entryName,
                'score'   => $entryScore,
                'savedAt' => $entrySavedAt
            ];
        }
    }

    $entries[] = [
        'name'    => $name,
        'score'   => $score,
        'savedAt' => $savedAt
    ];
    $entries = sort_leaderboard($entries);

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
    send_json(200, ['entries' => sort_leaderboard(read_leaderboard())]);
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
    $score = $payload['score'] ?? null;
    $nonce = isset($payload['nonce']) ? (string)$payload['nonce'] : '';

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

    // Nonce is mandatory. Clients must obtain a single-use nonce via
    // GET ?action=nonce and present it on submission.
    if (!consume_nonce($nonce)) {
        send_json(400, ['error' => 'Submission expired or invalid. Please try again.']);
    }

    $score   = (int)$score;
    $savedAt = gmdate('c');
    $entries = append_score_with_lock($name, $score, $savedAt);

    send_json(201, [
        'entries' => $entries,
        'saved'   => [
            'name'    => $name,
            'score'   => $score,
            'savedAt' => $savedAt
        ]
    ]);
}

header('Allow: GET, POST, OPTIONS');
send_json(405, ['error' => 'Method not allowed.']);
