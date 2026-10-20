import { defineConfig } from 'astro/config';
import react from '@astrojs/react';
import tailwindcss from '@tailwindcss/vite';

// On GitHub Pages the site lives under /<repo>/; the deploy workflow passes that in.
export default defineConfig({
  site: process.env.SITE_URL,
  base: process.env.SITE_BASE ?? '/',
  integrations: [react()],
  devToolbar: { enabled: false },
  vite: { plugins: [tailwindcss()] },
});
