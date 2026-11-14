// @ts-check
import { defineConfig } from 'astro/config';
import node from '@astrojs/node';
import preact from '@astrojs/preact';
import tailwindcss from '@tailwindcss/vite';

// Server output: pages read the local SQLite on every request, so new runs show up without a rebuild.
export default defineConfig({
  output: 'server',
  // The data is personal: only listen on this machine.
  server: { host: '127.0.0.1', port: 4321 },
  adapter: node({ mode: 'standalone' }),
  integrations: [preact()],
  vite: {
    plugins: [tailwindcss()],
  },
});
