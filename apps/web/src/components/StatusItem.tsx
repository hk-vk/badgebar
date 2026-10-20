import type { ReactNode } from 'react';
import type { BadgeStyle } from './store';

type Props = {
  label: string;
  count: number;
  style?: BadgeStyle;
  expanded?: boolean;
  onClick?: () => void;
  children: ReactNode;
};

/** One BadgeBar item: an app's icon with its count, drawn the way the app draws it. */
export default function StatusItem({ label, count, style = 'circle', expanded, onClick, children }: Props) {
  const Tag = onClick ? 'button' : 'span';
  return (
    <Tag
      {...(onClick && {
        type: 'button' as const,
        onClick,
        'aria-label': count ? `${label}, ${count} unread` : `${label}, nothing new`,
        'aria-expanded': expanded,
        'aria-haspopup': 'dialog' as const,
      })}
      className="status-item"
      data-dim={count === 0 || undefined}
      data-open={expanded || undefined}
    >
      <span className="relative inline-flex size-[18px] items-center justify-center">
        {children}
        {count > 0 && style === 'circle' && (
          <span key={count} className="badge-pop absolute -top-[5px] -right-[7px] flex h-[13px] min-w-[13px] items-center justify-center rounded-full bg-badge px-[3px] text-[9px] leading-none font-semibold text-white tabular-nums">
            {count > 99 ? '99+' : count}
          </span>
        )}
        {count > 0 && style === 'dot' && (
          <span key={count} className="badge-pop absolute -top-[1px] -right-[2px] size-[7px] rounded-full bg-badge" />
        )}
      </span>
      {count > 0 && style === 'text' && (
        <span key={count} className="badge-pop ml-[3px] text-[12px] font-semibold tabular-nums">
          {count}
        </span>
      )}
    </Tag>
  );
}
