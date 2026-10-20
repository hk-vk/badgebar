import { useEffect, useRef, useState } from 'react';
import StatusItem from './StatusItem';
import { iconFor, type AppId, type BadgeEffect } from './store';

const EFFECTS: { id: BadgeEffect; name: string }[] = [
  { id: 'pulse', name: 'Pulse' },
  { id: 'glow', name: 'Glow' },
  { id: 'shimmer', name: 'Shimmer' },
];

/** Badge effects: plays once when the card comes into view, and again on each pick. */
export function Effects() {
  const [effect, setEffect] = useState<BadgeEffect>('pulse');
  const [play, setPlay] = useState(0);
  const ref = useRef<HTMLDivElement>(null);
  const ids: AppId[] = ['slack', 'whatsapp', 'messages'];
  const counts: Record<string, number> = { slack: 3, whatsapp: 12, messages: 2 };

  useEffect(() => {
    const seen = new IntersectionObserver(
      ([e]) => {
        if (e.isIntersecting) {
          setPlay((n) => n + 1);
          seen.disconnect();
        }
      },
      { threshold: 0.8 },
    );
    if (ref.current) seen.observe(ref.current);
    return () => seen.disconnect();
  }, []);

  return (
    <div ref={ref} className="snippet snippet-stack">
      <div className="snippet-bar" aria-hidden="true">
        {ids.map((id) => (
          <StatusItem key={id} label={id} count={counts[id]} effect={play ? effect : 'off'} play={play} mask={iconFor(id)}>
            <img src={iconFor(id)} alt="" className="size-[17px]" draggable={false} />
          </StatusItem>
        ))}
      </div>
      <div className="mini-seg" role="radiogroup" aria-label="Badge effect">
        {EFFECTS.map((e) => (
          <button
            key={e.id}
            type="button"
            role="radio"
            aria-checked={e.id === effect}
            onClick={() => {
              setEffect(e.id);
              setPlay((n) => n + 1);
            }}
          >
            {e.name}
          </button>
        ))}
      </div>
    </div>
  );
}

const MEMBERS: { id: AppId; count: number }[] = [
  { id: 'slack', count: 3 },
  { id: 'messages', count: 2 },
  { id: 'mail', count: 1 },
];
const TRAY =
  'M2.5 9.5h3l1 1.6h3l1-1.6h3M2.5 9.5l1.5-5a1 1 0 0 1 1-.7h6a1 1 0 0 1 1 .7l1.5 5v3a1 1 0 0 1-1 1h-11a1 1 0 0 1-1-1ZM5.6 5.7h4.8M5.1 7.6h5.8';

/** Groups: three apps fold into one icon with their total, and back out. */
export function Groups() {
  const [grouped, setGrouped] = useState(false);
  const total = MEMBERS.reduce((n, m) => n + m.count, 0);

  return (
    <div className="snippet snippet-stack">
      <div className="snippet-bar" aria-hidden="true">
        <StatusItem label="" count={12}>
          <img src={iconFor('whatsapp')} alt="" className="size-[17px]" draggable={false} />
        </StatusItem>
        {MEMBERS.map((m) => (
          <StatusItem key={m.id} label="" count={m.count} hidden={grouped}>
            <img src={iconFor(m.id)} alt="" className="size-[17px]" draggable={false} />
          </StatusItem>
        ))}
        <StatusItem label="" count={total} hidden={!grouped}>
          <svg viewBox="0 0 16 16" className="size-[16px]" aria-hidden="true">
            <path d={TRAY} fill="none" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
        </StatusItem>
      </div>
      <label className="mini-switch">
        Group apps
        <button type="button" role="switch" aria-checked={grouped} className="switch" onClick={() => setGrouped((g) => !g)}>
          <span />
        </button>
      </label>
    </div>
  );
}
