import * as React from "react";

/**
 * Black God machined-metal panel — obsidian fill, hairline edge, top specular.
 *
 * @startingPoint section="Core" subtitle="Obsidian panel, 4 variants" viewport="700x260"
 */
export interface CardProps extends React.HTMLAttributes<HTMLDivElement> {
  children?: React.ReactNode;
  /** @default "raised" */
  variant?: "raised" | "chrome" | "inset" | "flat";
  /** Inner padding in px. @default 16 */
  padding?: number;
  style?: React.CSSProperties;
}

export function Card(props: CardProps): JSX.Element;
