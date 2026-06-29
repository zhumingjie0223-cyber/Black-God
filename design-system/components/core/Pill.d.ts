import * as React from "react";

/** Status pill (top-bar model selector). Live dot + label. */
export interface PillProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  children?: React.ReactNode;
  /** Status dot color. @default "ok" */
  status?: "ok" | "run" | "warn" | "err" | "idle";
  style?: React.CSSProperties;
}

export function Pill(props: PillProps): JSX.Element;
