import { defineConfig } from 'astro/config';
import react from '@astrojs/react';
import sitemap from '@astrojs/sitemap';
import tailwindcss from '@tailwindcss/vite';

// The deploy workflow passes in the site's URL and path; locally it serves from the root.
// The sitemap and canonical links need a site URL, so fall back to the production one.
export default defineConfig({
  site: process.env.SITE_URL ?? 'https://badgebar.hari.works',
  base: process.env.SITE_BASE ?? '/',
  integrations: [react(), sitemap()],
  devToolbar: { enabled: false },
  vite: { plugins: [tailwindcss()] },
});
