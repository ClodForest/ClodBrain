import { defineConfig } from 'vitest/config'
import coffee from 'vite-plugin-coffee3'

export default defineConfig({
  plugins: [
    coffee()
  ],
  test: {
    globals: true,
    environment: 'node',
    include: ['t/**/*.test.coffee'],
    exclude: ['t/setup.coffee'],
    coverage: {
      provider: 'v8',
      reporter: ['text', 'json', 'html'],
      exclude: [
        'node_modules/',
        't/',
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