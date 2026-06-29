import * as React from "react";

/** Black God circular chrome icon control for toolbars and composers. */
export interface IconButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  children?: React.ReactNode;
  /** @default "soft" */
  variant?: "soft" | "chrome" | "bare";
  /** @default "md" */
  size?: "sm" | "md" | "lg";
  /** Circle vs rounded-square. @default true */
  round?: boolean;
  /** Selected/toggled state. @default false */
  active?: boolean;
  disabled?: boolean;
  style?: React.CSSProperties;
}

export function IconButton(props: IconButtonProps): JSX.Element;
