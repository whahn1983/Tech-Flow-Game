<?php
header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');

const LEADERBOARD_FILE = __DIR__ . '/leaderboard.txt';
const MAX_ENTRIES = 25;

function send_json(int $statusCode, array $payload): void {
    http_response_code($statusCode);
    echo json_encode($payload);
    exit;
}

function ensure_leaderboard_file_exists(): void {
    if (file_exists(LEADERBOARD_FILE)) {
        return;
    }

    $handle = @fopen(LEADERBOARD_FILE, 'c+');
    if ($handle === false) {
        send_json(500, ['error' => 'Unable to initialize leaderboard storage. Check write permissions.']);
    }

    fclose($handle);
    @chmod(LEADERBOARD_FILE, 0666);
}

function clean_player_name($rawName): string {
    $name = preg_replace('/[\r\n|]+/', ' ', (string)$rawName);
    $name = trim($name ?? '');

    if (function_exists('mb_substr')) {
        return mb_substr($name, 0, 24);
    }

    return substr($name, 0, 24);
}

function read_leaderboard(): array {
    ensure_leaderboard_file_exists();
    $rawContents = @file_get_contents(LEADERBOARD_FILE);
    if ($rawContents === false) {
        send_json(500, ['error' => 'Unable to read leaderboard storage.']);
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

        $name = trim($parts[0]);
        $score = (int)$parts[1];
        $savedAt = $parts[2];

        if ($name === '' || $score < 0) {
            continue;
        }

        $entries[] = [
            'name' => $name,
            'score' => $score,
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

    $handle = @fopen(LEADERBOARD_FILE, 'c+');
    if ($handle === false) {
        send_json(500, ['error' => 'Unable to open leaderboard storage for writing. Check file permissions.']);
    }

    if (!@flock($handle, LOCK_EX)) {
        fclose($handle);
        send_json(500, ['error' => 'Unable to lock leaderboard storage for writing.']);
    }

    $rawContents = stream_get_contents($handle);
    if ($rawContents === false) {
        flock($handle, LOCK_UN);
        fclose($handle);
        send_json(500, ['error' => 'Unable to read leaderboard storage while locked.']);
    }

    $entries = [];
    $raw = trim($rawContents);
    if ($raw !== '') {
        foreach (explode("\n", $raw) as $line) {
            $parts = explode('|', $line);
            if (count($parts) < 3) {
                continue;
            }

            $entryName = trim($parts[0]);
            $entryScore = (int)$parts[1];
            $entrySavedAt = $parts[2];

            if ($entryName === '' || $entryScore < 0) {
                continue;
            }

            $entries[] = [
                'name' => $entryName,
                'score' => $entryScore,
                'savedAt' => $entrySavedAt
            ];
        }
    }

    $entries[] = [
        'name' => $name,
        'score' => $score,
        'savedAt' => $savedAt
    ];
    $entries = sort_leaderboard($entries);

    $payload = encode_leaderboard_rows($entries);

    rewind($handle);
    if (!@ftruncate($handle, 0) || ($payload !== '' && @fwrite($handle, $payload) === false)) {
        flock($handle, LOCK_UN);
        fclose($handle);
        send_json(500, ['error' => 'Unable to save leaderboard entry.']);
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
    $rawBody = file_get_contents('php://input');
    $payload = json_decode($rawBody, true);

    if (!is_array($payload)) {
        send_json(400, ['error' => 'Invalid JSON payload']);
    }

    $name = clean_player_name($payload['name'] ?? '');
    $score = (int)($payload['score'] ?? -1);

    if ($name === '') {
        send_json(400, ['error' => 'Player name is required.']);
    }

    if ($score < 0) {
        send_json(400, ['error' => 'Score must be a valid non-negative number.']);
    }

    $savedAt = gmdate('c');
    $entries = append_score_with_lock($name, $score, $savedAt);
    send_json(201, [
        'entries' => $entries,
        'saved' => [
            'name' => $name,
            'score' => $score,
            'savedAt' => $savedAt
        ]
    ]);
}

send_json(405, ['error' => 'Method not allowed']);
