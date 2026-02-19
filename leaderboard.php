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

function ensure_leaderboard_file(): void {
    if (!file_exists(LEADERBOARD_FILE)) {
        file_put_contents(LEADERBOARD_FILE, '');
    }
}

function clean_player_name($rawName): string {
    $name = preg_replace('/[\r\n|]+/', ' ', (string)$rawName);
    $name = trim($name ?? '');
    return mb_substr($name, 0, 24);
}

function read_leaderboard(): array {
    ensure_leaderboard_file();
    $raw = trim(file_get_contents(LEADERBOARD_FILE));
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

function write_leaderboard(array $entries): void {
    $rows = array_map(function ($entry) {
        return sprintf('%s|%d|%s', $entry['name'], (int)$entry['score'], $entry['savedAt']);
    }, $entries);

    file_put_contents(LEADERBOARD_FILE, implode("\n", $rows));
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
    $entries = sort_leaderboard(array_merge(read_leaderboard(), [[
        'name' => $name,
        'score' => $score,
        'savedAt' => $savedAt
    ]]));

    write_leaderboard($entries);
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
