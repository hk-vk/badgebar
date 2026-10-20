import { useEffect, useState } from 'react';
import StatusItem from './StatusItem';
import { APPS, MESSAGES, STARTING_COUNTS, iconFor, read, setCounts, useCounts, type AppId } from './store';

/** A Mac screen with the Dock hidden and BadgeBar in the menu bar. The icons work. */
export default function Screen() {
  const counts = useCounts();
  const [open, setOpen] = useState<AppId | null>(null);

  // The first messages arrive one after another, then one of them opens.
  useEffect(() => {
    if (matchMedia('(prefers-reduced-motion: reduce)').matches) {
      setCounts(STARTING_COUNTS);
      setOpen('whatsapp');
      return;
    }
    const ids = Object.keys(STARTING_COUNTS) as AppId[];
    const timers = ids.map((id, i) => setTimeout(() => setCounts({ [id]: STARTING_COUNTS[id] }), 500 + i * 220));
    timers.push(setTimeout(() => setOpen((o) => o ?? 'whatsapp'), 1700));
    return () => timers.forEach(clearTimeout);
  }, []);

  useEffect(() => {
    if (!open) return;
    const close = (e: Event) => {
      if (e instanceof KeyboardEvent ? e.key === 'Escape' : !(e.target as Element).closest('[data-menu]')) setOpen(null);
    };
    document.addEventListener('pointerdown', close);
    document.addEventListener('keydown', close);
    return () => {
      document.removeEventListener('pointerdown', close);
      document.removeEventListener('keydown', close);
    };
  }, [open]);

  return (
    <div className="screen">
      <div className="screen-bar">
        <div className="flex min-w-0 items-center gap-4 overflow-hidden">
          <span className="font-semibold">Notes</span>
          <span className="hidden gap-4 opacity-80 sm:flex">
            <span>File</span>
            <span>Edit</span>
            <span>Format</span>
            <span>View</span>
            <span>Window</span>
          </span>
        </div>
        <div className="relative flex items-center gap-[6px]">
          {APPS.map((app) => (
            <div key={app.id} className="sm:relative" data-menu>
              <StatusItem
                label={app.name}
                count={counts[app.id]}
                expanded={open === app.id}
                onClick={() => setOpen((o) => (o === app.id ? null : app.id))}
              >
                <img src={iconFor(app.id)} alt="" className="size-[17px]" draggable={false} />
              </StatusItem>
              {open === app.id && <Dropdown id={app.id} count={counts[app.id]} onClose={() => setOpen(null)} />}
            </div>
          ))}
          <span className="ml-2 hidden tabular-nums sm:inline">Tue 9:41</span>
        </div>
      </div>

      <div className="screen-window" aria-hidden="true">
        <div className="flex gap-[7px] p-4">
          <span className="size-3 rounded-full bg-[#ff5f57]" />
          <span className="size-3 rounded-full bg-[#febc2e]" />
          <span className="size-3 rounded-full bg-[#28c840]" />
        </div>
        <div className="space-y-3 px-[8%] pt-[4%]">
          <div className="h-5 w-2/5 rounded-full bg-ink/12" />
          <div className="h-3 w-11/12 rounded-full bg-ink/7" />
          <div className="h-3 w-4/5 rounded-full bg-ink/7" />
          <div className="h-3 w-5/6 rounded-full bg-ink/7" />
          <div className="h-3 w-3/5 rounded-full bg-ink/7" />
        </div>
      </div>
    </div>
  );
}

function Dropdown({ id, count, onClose }: { id: AppId; count: number; onClose: () => void }) {
  const name = APPS.find((a) => a.id === id)!.name;
  const rows = MESSAGES[id].slice(0, Math.min(count, 3));
  const done = () => {
    read(id);
    onClose();
  };

  return (
    <div role="dialog" aria-label={name} className="dropdown">
      <div className="flex items-baseline justify-between px-3 pt-2.5 pb-1">
        <span className="font-semibold">{name}</span>
        <span className="text-[12px] text-muted">{count ? `${count} unread` : 'Nothing new'}</span>
      </div>
      {rows.length > 0 ? (
        <ul className="px-1.5">
          {rows.map((m) => (
            <li key={m.from} className="flex gap-2.5 rounded-lg px-1.5 py-1.5">
              <img src={iconFor(id)} alt="" className="mt-0.5 size-7 flex-none" />
              <div className="min-w-0">
                <div className="truncate text-[12.5px] font-semibold">{m.from}</div>
                <div className="truncate text-[12.5px] text-muted">{m.text}</div>
              </div>
            </li>
          ))}
        </ul>
      ) : (
        <p className="px-3 pb-2 text-[12.5px] text-muted">You're all caught up.</p>
      )}
      <div className="mt-1 border-t border-line p-1.5">
        <button type="button" className="dropdown-action" onClick={done}>
          Open {name}
        </button>
        <button type="button" className="dropdown-action" disabled={!count} onClick={done}>
          Mark as Read
        </button>
      </div>
    </div>
  );
}
