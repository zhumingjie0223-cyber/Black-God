import * as React from "react";

/** Black God avatar — metallic 神 mark (assistant) or chrome initial plate (user). */
export interface AvatarProps {
  /** Image URL — use assets/logo-god.png for the assistant. */
  src?: string;
  /** Fallback label; first char becomes the initial. */
  label?: string;
  /** Pixel diameter. @default 36 */
  size?: number;
  /** @default "user" */
  kind?: "user" | "god";
  style?: React.CSSProperties;
}

export function Avatar(props: AvatarProps): JSX.Element;
