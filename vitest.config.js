import { defineConfig } from 'vitest/config'
import coffee from 'vite-plugin-coffee'

export default defineConfig({
  plugins: [
    coffee({
      jsx: false,
      transpile: {
        presets: ['@babel/preset-env']
      }
    })
  ],
  test: {
    globals: true,
    environment: 'node',
    include: ['t/**/*.coffee'],
    coverage: {
      provider: 'v8',
      reporter: ['text', 'json', 'html'],
      exclude: [
        'node_modules/',
        'test/',
        'public/',
        'bin/',
        '**/*.config.js'
      ]
    },
    // Mock timers for testing delays
    fakeTimers: {
      toFake: ['setTimeout', 'clearTimeout', 'setInterval', 'clearInterval']
    }
  },
  resolve: {
    extensions: ['.js', '.coffee']
  }
})
