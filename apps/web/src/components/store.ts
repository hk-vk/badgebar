import { useSyncExternalStore } from 'react';

// The unread counts in the hero's menu bar, shared by its icons and their dropdowns.

export const APPS = [
  { id: 'slack', name: 'Slack' },
  { id: 'whatsapp', name: 'WhatsApp' },
  { id: 'messages', name: 'Messages' },
  { id: 'mail', name: 'Mail' },
] as const;

export type AppId = (typeof APPS)[number]['id'];
export type BadgeStyle = 'circle' | 'text' | 'dot';

/** Made-up recent messages for the dropdowns, newest first. */
export const MESSAGES: Record<AppId, { from: string; text: string }[]> = {
  slack: [
    { from: 'Priya in #design', text: 'Pushed the new icons, can you take a look?' },
    { from: 'Marco', text: 'Standup moved to 10:30 today' },
    { from: 'Ana in #releases', text: 'Version 1.4 is out 🎉' },
  ],
  whatsapp: [
    { from: 'Mom', text: "Call me when you're free" },
    { from: 'Weekend trip', text: 'Sam: I booked the cabin!' },
    { from: 'Leo', text: 'Running 5 minutes late' },
  ],
  messages: [
    { from: 'Jordan', text: 'Dinner at 8?' },
    { from: 'Alex', text: 'Sent you the photos from Saturday' },
    { from: 'Dad', text: 'Landed safely' },
  ],
  mail: [
    { from: 'Studio Ferro', text: 'Invoice for October' },
    { from: 'Nadia Kim', text: 'Re: Draft for Thursday' },
    { from: 'Book club', text: 'Next pick and date' },
  ],
};

export const STARTING_COUNTS: Record<AppId, number> = { slack: 3, whatsapp: 12, messages: 2, mail: 0 };

let counts: Record<AppId, number> = { slack: 0, whatsapp: 0, messages: 0, mail: 0 };
const listeners = new Set<() => void>();

export function setCounts(next: Partial<Record<AppId, number>>) {
  counts = { ...counts, ...next };
  listeners.forEach((l) => l());
}

export const read = (id: AppId) => setCounts({ [id]: 0 });

const subscribe = (l: () => void) => {
  listeners.add(l);
  return () => listeners.delete(l);
};

export const useCounts = () => useSyncExternalStore(subscribe, () => counts, () => counts);

export const asset = (path: string) => `${import.meta.env.BASE_URL.replace(/\/$/, '')}/${path}`;
export const iconFor = (id: AppId) => asset(`apps/${id}.png`);
