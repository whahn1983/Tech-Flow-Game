<?php
header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');
header("Content-Security-Policy: default-src 'none'");
header('X-Content-Type-Options: nosniff');
header('X-Frame-Options: DENY');

const LEADERBOARD_FILE  = __DIR__ . '/leaderboard.txt';
const RATE_LIMIT_FILE   = __DIR__ . '/rate_limit.txt';
const MAX_ENTRIES       = 25;
const MAX_SCORE         = 999999;
const MAX_NAME_LENGTH   = 24;
const MAX_BODY_BYTES    = 10240; // 10 KB
const RATE_LIMIT_MAX    = 5;     // max POST submissions per window
const RATE_LIMIT_WINDOW = 60;    // seconds

function send_json(int $statusCode, array $payload): void {
    http_response_code($statusCode);
    echo json_encode($payload);
    exit;
}

function get_client_ip(): string {
    // Only trust REMOTE_ADDR. Never X-Forwarded-For without a verified trusted proxy.
    return $_SERVER['REMOTE_ADDR'] ?? '0.0.0.0';
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

$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';

if ($method === 'GET') {
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

send_json(405, ['error' => 'Method not allowed.']);
