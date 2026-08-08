/**
 * Sanitized minimal shape reproducing QPjYaNXMNd0 post-process failure.
 * No prompts, no full provider response, no secrets.
 *
 * Root cause: Gemini returned statPriority as objects; String(object) →
 * "[object Object]" which failed guideStatKeySchema during merge.
 */
export const qpjObjectStatPriorityShape = {
  videoId: "QPjYaNXMNd0",
  evidence: {
    evidenceType: "recommendation_table" as const,
    startSeconds: 120,
    endSeconds: 150,
    targetCharacterIds: ["mavuika"],
    visibleTexts: [{ text: "推奨ステータス", confidence: 0.9 }],
    // Problematic provider shape (objects, not strings).
    statPriorityRaw: [
      { statKey: "critRate", label: "会心率" },
      { key: "critDmg" },
      { stat: "er" },
      { nested: true },
    ],
    // What the old stringArray path produced (must not reach merge).
    legacyBrokenPriority: [
      "[object Object]",
      "[object Object]",
      "[object Object]",
    ],
  },
};
