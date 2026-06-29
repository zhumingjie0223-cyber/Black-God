import * as React from "react";

/** Black God metric tile — chrome value, muted uppercase label, optional delta. */
export interface StatTileProps {
  label: string;
  value: string | number;
  unit?: string;
  /** Delta string e.g. "↓ 62%". */
  delta?: string | null;
  /** @default "ok" */
  deltaTone?: "ok" | "err" | "run" | "neutral";
  icon?: React.ReactNode;
  style?: React.CSSProperties;
}

export function StatTile(props: StatTileProps): JSX.Element;
