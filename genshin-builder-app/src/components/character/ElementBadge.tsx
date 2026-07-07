import type { Element } from "@/types/character";
import { ELEMENT_INFO } from "@/lib/constants";

/** 元素名を色付きバッジで表示する */
export default function ElementBadge({ element }: { element: Element }) {
  const info = ELEMENT_INFO[element];
  return (
    <span
      className={`inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium ${info.bgClass} ${info.textClass}`}
    >
      {info.label}
    </span>
  );
}
