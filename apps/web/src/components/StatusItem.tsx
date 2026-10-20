import type { CSSProperties, ReactNode } from 'react';
import type { BadgeEffect, BadgeStyle } from './store';

type Props = {
  label: string;
  count: number;
  style?: BadgeStyle;
  expanded?: boolean;
  onClick?: () => void;
  /** The attention effect, played when `play` changes. */
  effect?: BadgeEffect;
  play?: number;
  /** The icon's image, so a shimmer lands on the icon and not the menu bar around it. */
  mask?: string;
  hidden?: boolean;
  children: ReactNode;
};

/** One BadgeBar item: an app's icon with its count, drawn the way the app draws it. */
export default function StatusItem({
  label,
  count,
  style = 'circle',
  expanded,
  onClick,
  effect = 'off',
  play = 0,
  mask,
  hidden,
  children,
}: Props) {
  const Tag = onClick ? 'button' : 'span';
  const fx = count > 0 && effect !== 'off' ? `fx fx-${effect}` : '';
  const badgeKey = `${count}-${play}-${effect}`;
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
      data-hidden={hidden || undefined}
      aria-hidden={hidden || undefined}
      tabIndex={hidden ? -1 : undefined}
    >
      <span className="relative inline-flex size-[18px] items-center justify-center">
        {children}
        {fx && effect === 'shimmer' && mask && (
          <span key={`icon-${badgeKey}`} className={`${fx} shimmer-icon`} style={{ '--mask': `url(${mask})` } as CSSProperties} />
        )}
        {count > 0 && style === 'circle' && (
          <span
            key={badgeKey}
            className={`badge-pop ${fx} absolute -top-[5px] -right-[7px] flex h-[13px] min-w-[13px] items-center justify-center overflow-hidden rounded-full bg-badge px-[3px] text-[9px] leading-none font-semibold text-white tabular-nums`}
          >
            {count > 99 ? '99+' : count}
          </span>
        )}
        {count > 0 && style === 'dot' && (
          <span key={badgeKey} className={`badge-pop ${fx} absolute -top-[1px] -right-[2px] size-[7px] overflow-hidden rounded-full bg-badge`} />
        )}
      </span>
      {count > 0 && style === 'text' && (
        <span key={badgeKey} className={`badge-pop ${fx} ml-[3px] text-[12px] font-semibold tabular-nums`}>
          {count}
        </span>
      )}
    </Tag>
  );
}
