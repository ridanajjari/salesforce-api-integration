const { defineConfig } = require('eslint/config');
const eslintJs = require('@eslint/js');
const globals = require('globals');

// This repo has no LWC or Aura; ESLint covers the repo's own Node config files.
module.exports = defineConfig([
    {
        ignores: ['node_modules/**', '.sfdx/**', '.sf/**']
    },
    {
        files: ['**/*.js'],
        languageOptions: {
            sourceType: 'commonjs',
            ecmaVersion: 'latest',
            globals: {
                ...globals.node
            }
        },
        plugins: {
            eslintJs
        },
        extends: ['eslintJs/recommended']
    }
]);
