import * as React from "react";

/**
 * Black God primary action button — brushed-chrome plate on obsidian.
 *
 * @startingPoint section="Core" subtitle="Chrome action button, 4 variants" viewport="700x200"
 */
export interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  children?: React.ReactNode;
  /** Visual treatment. @default "primary" */
  variant?: "primary" | "secondary" | "ghost" | "danger";
  /** @default "md" */
  size?: "sm" | "md" | "lg";
  /** Full-width. @default false */
  block?: boolean;
  disabled?: boolean;
  /** Leading icon (emoji or node). */
  icon?: React.ReactNode;
  /** Trailing icon. */
  iconRight?: React.ReactNode;
  style?: React.CSSProperties;
}

export function Button(props: ButtonProps): JSX.Element;
