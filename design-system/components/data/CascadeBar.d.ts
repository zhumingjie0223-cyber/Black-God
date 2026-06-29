import * as React from "react";

/**
 * Black God signature viz — the L0–L6 cost cascade. The level a request
 * resolved at lights up in chrome; cheaper levels read as saved.
 *
 * @startingPoint section="Black God" subtitle="L0–L6 cost cascade bar" viewport="700x130"
 */
export interface CascadeBarProps {
  /** Index 0–6 of the level the request resolved at. @default 2 */
  resolvedAt?: number;
  /** Show the cheap→expensive caption row. @default true */
  labels?: boolean;
  /** Thin 8px bar with no level labels. @default false */
  compact?: boolean;
  style?: React.CSSProperties;
}

export function CascadeBar(props: CascadeBarProps): JSX.Element;
