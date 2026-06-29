import * as React from "react";

/** Black God recessed field with chrome focus ring. Pill (single) or rounded (multiline). */
export interface InputProps {
  value?: string;
  onChange?: (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) => void;
  placeholder?: string;
  /** Leading icon/glyph. */
  icon?: React.ReactNode;
  /** Trailing slot (e.g. a send IconButton). */
  trailing?: React.ReactNode;
  type?: string;
  /** Render a growable textarea (rounded-rect) instead of a pill. @default false */
  multiline?: boolean;
  disabled?: boolean;
  style?: React.CSSProperties;
}

export function Input(props: InputProps): JSX.Element;
