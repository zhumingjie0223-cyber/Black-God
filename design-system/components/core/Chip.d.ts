import * as React from "react";

/** Black God capability/filter pill — chrome-outline token. */
export interface ChipProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  children?: React.ReactNode;
  /** Selected/on state (brighter chrome + inset). @default false */
  selected?: boolean;
  /** Leading icon/glyph. */
  icon?: React.ReactNode;
  /** @default "md" */
  size?: "sm" | "md";
  style?: React.CSSProperties;
}

export function Chip(props: ChipProps): JSX.Element;
