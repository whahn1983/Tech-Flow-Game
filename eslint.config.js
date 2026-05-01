const globals = require('globals');

module.exports = [
  {
    ignores: ['node_modules/**', 'extras/**', 'icons/**', 'screenshots/**', '**/*.min.js'],
  },
  {
    files: ['js/**/*.js', 'sw.js', 'server.js', 'tests/**/*.js'],
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: 'script',
      globals: {
        ...globals.browser,
        ...globals.node,
        ...globals.serviceworker,
        self: 'readonly',
        caches: 'readonly',
        clients: 'readonly',
      },
    },
    rules: {
      'no-unused-vars': [
        'warn',
        { argsIgnorePattern: '^_', varsIgnorePattern: '^_' },
      ],
      'no-undef': 'error',
      'no-var': 'warn',
      'prefer-const': 'warn',
      eqeqeq: ['warn', 'smart'],
      'no-constant-condition': ['warn', { checkLoops: false }],
    },
  },
];
