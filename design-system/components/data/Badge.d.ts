import * as React from "react";

/** Black God state token. Semantic color is reserved for status only. */
export interface BadgeProps extends React.HTMLAttributes<HTMLSpanElement> {
  children?: React.ReactNode;
  /** @default "neutral" */
  tone?: "ok" | "run" | "warn" | "err" | "chrome" | "neutral";
  /** Show a leading glowing dot. @default false */
  dot?: boolean;
  style?: React.CSSProperties;
}

export function Badge(props: BadgeProps): JSX.Element;
