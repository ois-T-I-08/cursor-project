/**
 * Deterministic OCR cleanup for number grounding.
 * Does not invent values — only normalizes digit-like glyphs.
 */

const FULLWIDTH_DIGIT_MAP: Record<string, string> = {
  "０": "0",
  "１": "1",
  "２": "2",
  "３": "3",
  "４": "4",
  "５": "5",
  "６": "6",
  "７": "7",
  "８": "8",
  "９": "9",
  "．": ".",
  "，": ",",
  "％": "%",
};

/** Normalize fullwidth digits/punctuation and common OCR digit confusions near numbers. */
export function normalizeOcrVisibleText(text: string): string {
  let out = "";
  for (const ch of text.normalize("NFC")) {
    if (FULLWIDTH_DIGIT_MAP[ch]) {
      out += FULLWIDTH_DIGIT_MAP[ch];
      continue;
    }
    // Fullwidth Latin lookalikes often appear in OCR number runs.
    if (ch === "Ｏ" || ch === "ｏ") {
      out += "O";
      continue;
    }
    if (ch === "Ｉ" || ch === "ｌ" || ch === "｜") {
      out += "I";
      continue;
    }
    out += ch;
  }
  // O/o between digits → 0 (e.g. 15O% → 150%)
  out = out.replace(/(?<=\d)[Oo](?=\d)/g, "0");
  out = out.replace(/(?<=\d)[Oo](?=%)/g, "0");
  // l/I between digits or before % → 1
  out = out.replace(/(?<=\d)[Il](?=\d)/g, "1");
  out = out.replace(/(?<=\d)[Il](?=%)/g, "1");
  return out.replace(/,/g, "");
}

export function numberInNormalizedVisibleText(
  text: string,
  values: Array<number | null | undefined>,
): boolean {
  const normalized = normalizeOcrVisibleText(text);
  return values.some((value) => {
    if (value == null || !Number.isFinite(value)) return false;
    const asInt = String(Math.round(value));
    const asOne = value.toFixed(1).replace(/\.0$/, "");
    return normalized.includes(asInt) || normalized.includes(asOne);
  });
}
