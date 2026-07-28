"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  type ArtifactCompositionMode,
  type ArtifactSetMaster,
  type TargetDraft,
  DATA_ORIGIN_LABELS,
  MAIN_STAT_OPTIONS_BY_SLOT,
  RECOMMENDATION_LEVEL_LABELS,
  REVIEW_STATUS_LABELS,
  SLOT_LABELS,
  STATUS_LABELS,
  TARGET_STAT_OPTIONS,
  UNIT_LABELS,
  VALUE_TYPE_LABELS,
  buildArtifactSetsPayload,
  emptyTarget,
  formatArtifactCompositionPreview,
  inferCompositionMode,
  labelOf,
  payloadToTargetDrafts,
  targetDraftToPayload,
  unitWarnForStat,
} from "@/lib/build-guides/guide-admin-form";

type WeaponMaster = {
  id: string;
  name: string;
  rarity: number;
  iconUrl: string;
  weaponType: string;
};

type CharacterMaster = {
  id: string;
  name: string;
  iconUrl: string;
  weaponType: string;
};

type RecommendationRow = {
  id: string;
  characterId: string;
  status: string;
  origin: string;
  overallConfidence: number;
  updatedAt: string;
  publishedAt: string | null;
  lastVerifiedAt: string | null;
  adminNotes: string;
  context: Record<string, unknown>;
  mainStats: unknown[];
  targets: unknown[];
  substatPriority: unknown[];
  structuredPayload: Record<string, unknown>;
  structuredReviewStatus: string | null;
  hasUnpublishedDraft?: boolean;
  pendingMentions: {
    weapons?: unknown[];
    artifactSets?: unknown[];
  };
  contributions: Array<{
    id: string;
    videoId: string;
    startSeconds: number;
    endSeconds: number;
    exactVisibleText: string;
    videoTitle?: string;
    channelTitle?: string;
    sourceUrl?: string;
    publishedAt?: string;
  }>;
  revisions: Array<{
    id: string;
    action: string;
    actor: string;
    createdAt: string;
    beforePayload: string;
    afterPayload: string;
  }>;
};

type Props = {
  recommendations: RecommendationRow[];
  busy: boolean;
  postAction: (payload: Record<string, unknown>) => Promise<unknown>;
};

type WeaponDraft = {
  weaponId: string;
  displayName: string;
  rank: number;
  recommendationLevel: string;
  reason: string;
  conditionsText: string;
  role: string;
  citationId: string;
  dataOrigin: string;
  adminConfirmed: boolean;
};

type ArtifactDraft = {
  mode: ArtifactCompositionMode;
  setAId: string;
  setBId: string;
  rank: number;
  recommendationLevel: string;
  reason: string;
  conditionsText: string;
  role: string;
  isAlternative: boolean;
  citationId: string;
  dataOrigin: string;
  adminConfirmed: boolean;
};

type MainStatDraft = {
  slot: "sands" | "goblet" | "circlet";
  primary: string[];
  alternative: string[];
  condition: string;
  citationId: string;
};

function asArray(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

function asRecord(value: unknown): Record<string, unknown> {
  if (value && typeof value === "object" && !Array.isArray(value)) {
    return value as Record<string, unknown>;
  }
  return {};
}

function parseList(text: string): string[] {
  return text
    .split(/[,、\n]/)
    .map((s) => s.trim())
    .filter(Boolean);
}

function emptyWeapon(rank: number): WeaponDraft {
  return {
    weaponId: "",
    displayName: "",
    rank,
    recommendationLevel: "recommended",
    reason: "",
    conditionsText: "",
    role: "",
    citationId: "",
    dataOrigin: "manual",
    adminConfirmed: true,
  };
}

function emptyArtifact(rank: number): ArtifactDraft {
  return {
    mode: "four",
    setAId: "",
    setBId: "",
    rank,
    recommendationLevel: "recommended",
    reason: "",
    conditionsText: "",
    role: "",
    isAlternative: false,
    citationId: "",
    dataOrigin: "manual",
    adminConfirmed: true,
  };
}

function ArtifactSetPicker({
  label,
  value,
  sets,
  query,
  onQueryChange,
  onSelect,
  disabled,
}: {
  label: string;
  value: string;
  sets: ArtifactSetMaster[];
  query: string;
  onQueryChange: (q: string) => void;
  onSelect: (setId: string) => void;
  disabled?: boolean;
}) {
  const selected = sets.find((s) => s.setId === value) ?? null;
  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    const list = !q
      ? sets
      : sets.filter(
          (s) =>
            s.name.toLowerCase().includes(q) ||
            s.setId.toLowerCase().includes(q) ||
            s.twoPieceEffect.toLowerCase().includes(q) ||
            s.fourPieceEffect.toLowerCase().includes(q),
        );
    return list.slice(0, 40);
  }, [query, sets]);

  return (
    <div className="space-y-1 text-sm">
      <div className="text-xs text-gray-400">{label}</div>
      <div className="rounded border border-white/10 bg-[#0f1622] p-2">
        {value ? (
          selected ? (
            <div className="mb-2 flex items-start gap-2">
              {selected.iconUrl ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img
                  src={selected.iconUrl}
                  alt=""
                  className="h-10 w-10 rounded object-cover"
                />
              ) : (
                <div className="flex h-10 w-10 items-center justify-center rounded bg-white/10 text-[10px]">
                  no icon
                </div>
              )}
              <div className="min-w-0 flex-1">
                <div className="font-medium">{selected.name}</div>
                <div className="text-xs text-gray-500">setId: {selected.setId}</div>
              </div>
              <button
                type="button"
                className="text-xs underline"
                disabled={disabled}
                onClick={() => onSelect("")}
              >
                クリア
              </button>
            </div>
          ) : (
            <div className="mb-2 rounded border border-amber-500/40 bg-amber-500/10 p-2 text-xs text-amber-100">
              不明な聖遺物セット
              <div>setId: {value}</div>
              <button
                type="button"
                className="mt-1 underline"
                disabled={disabled}
                onClick={() => onSelect("")}
              >
                クリアして選び直す
              </button>
            </div>
          )
        ) : (
          <div className="mb-2 text-xs text-gray-500">未選択</div>
        )}
        <input
          className="mb-2 w-full rounded border border-white/10 bg-[#151d2a] px-2 py-1 text-xs"
          placeholder="名前 / setId で検索"
          value={query}
          disabled={disabled}
          onChange={(e) => onQueryChange(e.target.value)}
        />
        <div className="max-h-36 space-y-1 overflow-auto">
          {filtered.map((s) => (
            <button
              key={s.setId}
              type="button"
              disabled={disabled}
              className="flex w-full items-start gap-2 rounded border border-white/5 px-2 py-1 text-left hover:bg-white/5"
              onClick={() => {
                onSelect(s.setId);
                onQueryChange("");
              }}
            >
              {s.iconUrl ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img src={s.iconUrl} alt="" className="h-8 w-8 rounded" />
              ) : (
                <div className="h-8 w-8 rounded bg-white/10" />
              )}
              <div className="min-w-0 flex-1 text-xs">
                <div className="font-medium">{s.name}</div>
                <div className="text-gray-500">{s.setId}</div>
                {s.twoPieceEffect ? (
                  <div className="truncate text-gray-400">2: {s.twoPieceEffect}</div>
                ) : null}
                {s.fourPieceEffect ? (
                  <div className="truncate text-gray-400">4: {s.fourPieceEffect}</div>
                ) : null}
              </div>
            </button>
          ))}
          {filtered.length === 0 ? (
            <div className="text-xs text-gray-500">該当なし</div>
          ) : null}
        </div>
      </div>
    </div>
  );
}

function MultiStatSelect({
  label,
  slot,
  values,
  onChange,
}: {
  label: string;
  slot: "sands" | "goblet" | "circlet";
  values: string[];
  onChange: (next: string[]) => void;
}) {
  const options = MAIN_STAT_OPTIONS_BY_SLOT[slot];
  return (
    <div className="text-xs">
      <div className="mb-1 text-gray-400">{label}</div>
      <div className="flex flex-wrap gap-1">
        {options.map((opt) => {
          const on = values.includes(opt);
          return (
            <button
              key={opt}
              type="button"
              className={`rounded border px-2 py-1 ${
                on
                  ? "border-accent bg-accent/20 text-accent"
                  : "border-white/15 text-gray-300"
              }`}
              onClick={() =>
                onChange(
                  on ? values.filter((v) => v !== opt) : [...values, opt].slice(0, 4),
                )
              }
            >
              {opt}
            </button>
          );
        })}
      </div>
    </div>
  );
}

function CitationSelect({
  value,
  options,
  onChange,
}: {
  value: string;
  options: Array<{ id: string; label: string }>;
  onChange: (v: string) => void;
}) {
  const unresolved = Boolean(value && !options.some((o) => o.id === value));
  return (
    <div>
      <select
        className="mt-1 w-full rounded border border-white/10 bg-[#0f1622] px-2 py-1 text-sm"
        value={value}
        onChange={(e) => onChange(e.target.value)}
      >
        <option value="">出典なし</option>
        {options.map((c) => (
          <option key={c.id} value={c.id}>
            {c.label}
          </option>
        ))}
        {unresolved ? (
          <option value={value}>（解決不能）{value}</option>
        ) : null}
      </select>
      {unresolved ? (
        <p className="mt-1 text-xs text-amber-300">
          解決不能な出典 ID です。値は保持しています。別の出典へ変更するか「出典なし」を選んでください。
        </p>
      ) : null}
    </div>
  );
}

export default function StructuredRecommendationEditor({
  recommendations,
  busy,
  postAction,
}: Props) {
  const [selectedId, setSelectedId] = useState("");
  const [masters, setMasters] = useState<{
    characters: CharacterMaster[];
    weapons: WeaponMaster[];
    artifactSets: ArtifactSetMaster[];
  } | null>(null);
  const [mastersError, setMastersError] = useState<string | null>(null);
  const [mastersLoading, setMastersLoading] = useState(false);
  const [weaponQuery, setWeaponQuery] = useState("");
  const [setQueryA, setSetQueryA] = useState<Record<number, string>>({});
  const [setQueryB, setSetQueryB] = useState<Record<number, string>>({});
  const [investmentPriority, setInvestmentPriority] = useState("");
  const [gameVersion, setGameVersion] = useState("");
  const [adminNotes, setAdminNotes] = useState("");
  const [weapons, setWeapons] = useState<WeaponDraft[]>([]);
  const [artifacts, setArtifacts] = useState<ArtifactDraft[]>([]);
  const [mainStats, setMainStats] = useState<MainStatDraft[]>([
    { slot: "sands", primary: [], alternative: [], condition: "", citationId: "" },
    { slot: "goblet", primary: [], alternative: [], condition: "", citationId: "" },
    { slot: "circlet", primary: [], alternative: [], condition: "", citationId: "" },
  ]);
  const [targets, setTargets] = useState<TargetDraft[]>([]);
  const [pendingWeapons, setPendingWeapons] = useState<unknown[]>([]);
  const [pendingArtifacts, setPendingArtifacts] = useState<unknown[]>([]);
  const [keepPublished, setKeepPublished] = useState(false);
  const [previewJson, setPreviewJson] = useState("");
  const [validationJson, setValidationJson] = useState("");
  const [showDebugJson, setShowDebugJson] = useState(false);
  const [localError, setLocalError] = useState<string | null>(null);
  const [localOk, setLocalOk] = useState<string | null>(null);
  const [focusPath, setFocusPath] = useState<string | null>(null);
  const [dirty, setDirty] = useState(false);
  const sectionRefs = useRef<Record<string, HTMLElement | null>>({});
  const isHydrating = useRef(false);

  const selected = useMemo(
    () => recommendations.find((r) => r.id === selectedId) ?? null,
    [recommendations, selectedId],
  );

  const loadMasters = useCallback(async () => {
    setMastersLoading(true);
    setMastersError(null);
    try {
      const result = (await postAction({ action: "listGuideMasterOptions" })) as {
        characters?: CharacterMaster[];
        weapons?: WeaponMaster[];
        artifactSets?: ArtifactSetMaster[];
        mastersError?: string | null;
        error?: string;
      };
      if (result?.error) {
        setMastersError(result.error);
        return;
      }
      if (result?.characters && result?.weapons) {
        setMasters({
          characters: result.characters,
          weapons: result.weapons,
          artifactSets: result.artifactSets ?? [],
        });
      }
      if (result?.mastersError) setMastersError(result.mastersError);
    } finally {
      setMastersLoading(false);
    }
  }, [postAction]);

  const hydrateRecommendation = useCallback((nextSelected: RecommendationRow) => {
    isHydrating.current = true;
    const structured = nextSelected.structuredPayload ?? {};
    setInvestmentPriority(
      typeof structured.investmentPriority === "string"
        ? structured.investmentPriority
        : "",
    );
    setGameVersion(
      typeof structured.gameVersion === "string" ? structured.gameVersion : "",
    );
    setAdminNotes(nextSelected.adminNotes ?? "");

    setWeapons(
      asArray(structured.weapons).map((item, index) => {
        const map = asRecord(item);
        return {
          weaponId: String(map.weaponId ?? ""),
          displayName: String(map.displayName ?? ""),
          rank: typeof map.rank === "number" ? map.rank : index + 1,
          recommendationLevel: String(map.recommendationLevel ?? ""),
          reason: String(map.reason ?? ""),
          conditionsText: asArray(map.conditions)
            .map((c) => String(c))
            .join("、"),
          role: String(map.role ?? ""),
          citationId: String(map.citationId ?? ""),
          dataOrigin: String(map.dataOrigin ?? "manual"),
          adminConfirmed: map.adminConfirmed !== false,
        } satisfies WeaponDraft;
      }),
    );

    setArtifacts(
      asArray(structured.artifactRecommendations).map((item, index) => {
        const map = asRecord(item);
        const sets = asArray(map.sets).map((s) => asRecord(s));
        const modeFromField =
          map.compositionMode === "four" ||
          map.compositionMode === "two_two" ||
          map.compositionMode === "two" ||
          map.compositionMode === "undetermined"
            ? (map.compositionMode as ArtifactCompositionMode)
            : null;
        const inferred = inferCompositionMode(
          sets.map((s) => ({
            setId: String(s.setId ?? ""),
            pieces: typeof s.pieces === "number" ? s.pieces : null,
          })),
        );
        return {
          mode: modeFromField ?? inferred,
          setAId: String(sets[0]?.setId ?? ""),
          setBId: String(sets[1]?.setId ?? ""),
          rank: typeof map.rank === "number" ? map.rank : index + 1,
          recommendationLevel: String(map.recommendationLevel ?? ""),
          reason: String(map.reason ?? ""),
          conditionsText: asArray(map.conditions)
            .map((c) => String(c))
            .join("、"),
          role: String(map.role ?? ""),
          isAlternative: map.isAlternative === true,
          citationId: String(map.citationId ?? ""),
          dataOrigin: String(map.dataOrigin ?? "manual"),
          adminConfirmed: map.adminConfirmed !== false,
        } satisfies ArtifactDraft;
      }),
    );

    setMainStats(
      (["sands", "goblet", "circlet"] as const).map((slot) => {
        const found = asArray(nextSelected.mainStats).find(
          (m) => asRecord(m).slot === slot,
        );
        const map = asRecord(found);
        const primary = asArray(map.primaryStats).length
          ? asArray(map.primaryStats).map(String)
          : asArray(map.stats).slice(0, 1).map(String);
        const alt = asArray(map.alternativeStats).length
          ? asArray(map.alternativeStats).map(String)
          : asArray(map.stats).slice(1).map(String);
        return {
          slot,
          primary,
          alternative: alt,
          condition: String(map.condition ?? ""),
          citationId: String(map.citationId ?? ""),
        };
      }),
    );

    const fromRecommended = asArray(structured.recommendedStats);
    setTargets(
      payloadToTargetDrafts(
        fromRecommended.length > 0 ? fromRecommended : nextSelected.targets,
      ),
    );
    setPendingWeapons(asArray(nextSelected.pendingMentions?.weapons));
    setPendingArtifacts(asArray(nextSelected.pendingMentions?.artifactSets));
    setKeepPublished(nextSelected.status === "published");
    setWeaponQuery("");
    setSetQueryA({});
    setSetQueryB({});
    setPreviewJson("");
    setValidationJson("");
    setLocalError(null);
    setLocalOk(null);
    setDirty(false);
    window.setTimeout(() => {
      isHydrating.current = false;
    }, 0);
  }, []);

  const handleRecommendationChange = (nextId: string) => {
    if (nextId === selectedId) return;
    if (
      dirty &&
      !window.confirm("未保存の変更があります。破棄して別の推奨レコードへ移動しますか？")
    ) {
      return;
    }
    setSelectedId(nextId);
    const nextSelected = recommendations.find((row) => row.id === nextId);
    if (!nextSelected) {
      setDirty(false);
      return;
    }
    hydrateRecommendation(nextSelected);
    if (!masters && !mastersLoading) {
      void loadMasters();
    }
  };

  useEffect(() => {
    if (!focusPath) return;
    const key = focusPath.split("[")[0] ?? focusPath;
    const el = sectionRefs.current[key] ?? sectionRefs.current[focusPath];
    el?.scrollIntoView({ behavior: "smooth", block: "start" });
    el?.setAttribute("tabindex", "-1");
    el?.focus?.();
  }, [focusPath]);

  useEffect(() => {
    if (!dirty) return;
    const onBeforeUnload = (event: BeforeUnloadEvent) => {
      event.preventDefault();
      event.returnValue = "";
    };
    window.addEventListener("beforeunload", onBeforeUnload);
    return () => window.removeEventListener("beforeunload", onBeforeUnload);
  }, [dirty]);

  useEffect(() => {
    if (isHydrating.current || !selectedId) return;
    setDirty(true);
  }, [
    selectedId,
    weapons,
    artifacts,
    targets,
    mainStats,
    investmentPriority,
    gameVersion,
    adminNotes,
    pendingWeapons,
    pendingArtifacts,
    keepPublished,
  ]);

  const characterLabel = useMemo(() => {
    if (!selected || !masters) return selected?.characterId ?? "";
    const hit = masters.characters.find((c) => c.id === selected.characterId);
    return hit ? `${hit.name} (${hit.id})` : selected.characterId;
  }, [masters, selected]);

  const citationOptions = useMemo(() => {
    if (!selected) return [];
    const seen = new Set<string>();
    const options: Array<{ id: string; label: string }> = [];
    for (const c of selected.contributions) {
      const id = `source-${c.videoId}`;
      if (seen.has(id)) continue;
      seen.add(id);
      options.push({
        id,
        label: [
          c.videoTitle ?? c.videoId,
          c.channelTitle ?? "",
          c.videoId,
          c.publishedAt ? String(c.publishedAt).slice(0, 10) : "",
        ]
          .filter(Boolean)
          .join(" · "),
      });
    }
    return options;
  }, [selected]);

  const filteredWeapons = useMemo(() => {
    if (!masters) return [];
    const q = weaponQuery.trim().toLowerCase();
    if (!q) return masters.weapons.slice(0, 30);
    return masters.weapons
      .filter(
        (w) =>
          w.name.toLowerCase().includes(q) || w.id.toLowerCase().includes(q),
      )
      .slice(0, 30);
  }, [masters, weaponQuery]);

  const setNameOf = useCallback(
    (id: string) => {
      const hit = masters?.artifactSets.find((s) => s.setId === id);
      return hit?.name ?? (id ? `不明セット(${id})` : "未選択");
    },
    [masters],
  );

  const buildTargetsPayload = () => {
    const recommendedStats: unknown[] = [];
    const targetRows: unknown[] = [];
    for (const row of targets) {
      const { recommended, target } = targetDraftToPayload(row);
      if (recommended) recommendedStats.push(recommended);
      if (target) targetRows.push(target);
    }
    return { recommendedStats, targets: targetRows };
  };

  const buildStructuredPayload = () => {
    const { recommendedStats } = buildTargetsPayload();
    const hasUnconfirmed =
      pendingWeapons.length > 0 ||
      pendingArtifacts.length > 0 ||
      weapons.some((w) => !w.adminConfirmed || w.dataOrigin === "evidence_mention") ||
      artifacts.some(
        (a) =>
          !a.adminConfirmed ||
          a.dataOrigin === "evidence_mention" ||
          a.mode === "undetermined",
      );
    return {
      investmentPriority: investmentPriority || undefined,
      gameVersion: gameVersion || undefined,
      structuredReviewStatus: hasUnconfirmed
        ? "review_required"
        : selected?.structuredReviewStatus === "admin_confirmed"
          ? "admin_confirmed"
          : "draft",
      pendingMentions: {
        weapons: pendingWeapons,
        artifactSets: pendingArtifacts,
      },
      sources: citationOptions.map((c) => ({
        id: c.id,
        videoId: c.id.replace(/^source-/, ""),
      })),
      recommendedStats,
      weapons: weapons.map((w) => ({
        weaponId: w.weaponId || null,
        displayName: w.displayName || null,
        rank: w.rank,
        recommendationLevel: w.recommendationLevel || null,
        reason: w.reason || null,
        conditions: parseList(w.conditionsText),
        role: w.role || null,
        citationId: w.citationId || null,
        dataOrigin: w.dataOrigin || "manual",
        adminConfirmed: w.adminConfirmed,
      })),
      artifactRecommendations: artifacts.map((a) => ({
        compositionMode: a.mode,
        sets: buildArtifactSetsPayload(a.mode, a.setAId, a.setBId),
        rank: a.rank,
        recommendationLevel: a.recommendationLevel || null,
        reason: a.reason || null,
        conditions: parseList(a.conditionsText),
        role: a.role || null,
        isAlternative: a.isAlternative,
        citationId: a.citationId || null,
        dataOrigin: a.dataOrigin || "manual",
        adminConfirmed: a.mode === "undetermined" ? false : a.adminConfirmed,
      })),
    };
  };

  const buildMainStatsPayload = () =>
    mainStats
      .map((m) => {
        if (m.primary.length === 0) return null;
        return {
          slot: m.slot,
          primaryStats: m.primary,
          alternativeStats: m.alternative,
          stats: [...m.primary, ...m.alternative],
          condition: m.condition || null,
          citationId: m.citationId || null,
        };
      })
      .filter(Boolean);

  const saveDraft = async () => {
    if (!selected) return;
    setLocalError(null);
    setLocalOk(null);
    const { targets: targetRows } = buildTargetsPayload();
    const result = (await postAction({
      action: "overrideRecommendation",
      recommendationId: selected.id,
      targetsPayload: targetRows,
      mainStatsPayload: buildMainStatsPayload(),
      priorityPayload: selected.substatPriority,
      contextPayload: selected.context,
      structuredPayload: buildStructuredPayload(),
      adminNotes,
      expectedUpdatedAt: selected.updatedAt,
      keepPublished,
    })) as { error?: string; detail?: string; keepPublished?: boolean };
    if (result?.error) {
      setLocalError(
        result.error === "conflictUpdatedAt"
          ? "他の編集と衝突しました。再読み込みしてください。"
          : `${result.error}${result.detail ? `: ${result.detail}` : ""}`,
      );
      return;
    }
      setDirty(false);
      setLocalOk(
      result.keepPublished || keepPublished
        ? "作業下書きを保存しました（公開中の API レスポンスは変更していません）"
        : "下書きを保存しました",
    );
  };

  const runValidate = async () => {
    if (!selected) return;
    setLocalError(null);
    const { targets: targetRows } = buildTargetsPayload();
    const result = (await postAction({
      action: "validateStructuredRecommendation",
      recommendationId: selected.id,
      targetsPayload: targetRows,
      mainStatsPayload: buildMainStatsPayload(),
      structuredPayload: buildStructuredPayload(),
    })) as {
      error?: string;
      canPublish?: boolean;
      publishIssues?: Array<{ path: string; message: string; level: string }>;
    };
    if (result?.error) {
      setLocalError(result.error);
      return;
    }
    setValidationJson(JSON.stringify(result, null, 2));
    const firstError = result.publishIssues?.find((i) => i.level === "error");
    if (firstError) setFocusPath(firstError.path);
    setLocalOk(
      result.canPublish
        ? "公開要件を満たしています"
        : "公開ブロックまたは警告があります",
    );
  };

  const runPreview = async () => {
    if (!selected) return;
    const result = (await postAction({
      action: "previewRecommendationPublic",
      recommendationId: selected.id,
    })) as { data?: unknown; warnings?: string[]; error?: string; parseError?: string };
    if (result?.error) {
      setLocalError(result.error);
      return;
    }
    setPreviewJson(JSON.stringify(result, null, 2));
  };

  const debugPayload = useMemo(
    () => ({
      structured: buildStructuredPayload(),
      mainStats: buildMainStatsPayload(),
      ...buildTargetsPayload(),
    }),
    // eslint-disable-next-line react-hooks/exhaustive-deps -- デバッグ表示は明示トグル時の現在値で十分
    [weapons, artifacts, mainStats, targets, investmentPriority, gameVersion, pendingWeapons, pendingArtifacts],
  );

  return (
    <section className="space-y-4 rounded-xl border border-white/10 bg-[#1e2a3a] p-5">
      <h2 className="font-bold">構造化育成情報エディタ</h2>
      <p className="text-sm text-gray-400">
        マスターから選択して編集します。通常操作で JSON / 内部 ID の手入力は不要です。自動抽出言及は確認なしでは公開されません。
      </p>

      <label className="block text-sm">
        推奨レコード
        <select
          className="mt-1 w-full rounded-lg border border-white/10 bg-[#151d2a] px-3 py-2"
          value={selectedId}
          onChange={(e) => handleRecommendationChange(e.target.value)}
        >
          <option value="">選択してください</option>
          {recommendations.map((r) => (
            <option key={r.id} value={r.id}>
              {r.characterId} · {labelOf(STATUS_LABELS, r.status)} ·{" "}
              {r.hasUnpublishedDraft ? "作業下書きあり · " : ""}
              {r.id.slice(0, 8)}
            </option>
          ))}
        </select>
      </label>

      <div className="flex flex-wrap items-center gap-2 text-xs text-gray-400">
        {mastersLoading ? <span>マスター読み込み中…</span> : null}
        {mastersError ? (
          <span className="text-amber-300">
            マスター警告: {mastersError}
            <button type="button" className="ml-2 underline" onClick={() => void loadMasters()}>
              再試行
            </button>
          </span>
        ) : null}
        {masters ? (
          <span>
            武器 {masters.weapons.length} / 聖遺物セット {masters.artifactSets.length}
          </span>
        ) : null}
      </div>

      {!selected ? (
        <p className="text-sm text-gray-500">キャラクターの推奨レコードを選択してください。</p>
      ) : (
        <>
          <div
            ref={(el) => {
              sectionRefs.current.basic = el;
            }}
            className="rounded-lg bg-[#151d2a] p-3 text-sm"
          >
            <div className="font-medium">{characterLabel}</div>
            <div className="mt-1 text-xs text-gray-400">
              状態: {labelOf(STATUS_LABELS, selected.status)} · schemaVersion 1 · 構造化:{" "}
              {labelOf(REVIEW_STATUS_LABELS, selected.structuredReviewStatus)} · updatedAt:{" "}
              {selected.updatedAt}
              {selected.publishedAt ? ` · publishedAt: ${selected.publishedAt}` : ""}
              {selected.hasUnpublishedDraft
                ? " · 公開中データとは別の作業下書きあり"
                : ""}
            </div>
          </div>

          <div
            ref={(el) => {
              sectionRefs.current.pendingMentions = el;
            }}
            className="space-y-2 rounded-lg border border-amber-500/30 p-3"
          >
            <h3 className="text-sm font-bold text-amber-200">要確認（自動抽出言及）</h3>
            {pendingWeapons.map((raw, index) => {
              const m = asRecord(raw);
              return (
                <div key={`pw-${index}`} className="flex flex-wrap gap-2 text-xs">
                  <span>
                    武器言及: {String(m.displayName ?? "")} ({String(m.weaponId ?? "IDなし")})
                  </span>
                  <button
                    type="button"
                    className="rounded border border-white/20 px-2 py-1"
                    disabled={busy}
                    onClick={() => {
                      setWeapons((prev) => [
                        ...prev,
                        {
                          ...emptyWeapon(prev.length + 1),
                          weaponId: String(m.weaponId ?? ""),
                          displayName: String(m.displayName ?? ""),
                          adminConfirmed: false,
                          recommendationLevel: "",
                          citationId: m.videoId ? `source-${String(m.videoId)}` : "",
                        },
                      ]);
                      setPendingWeapons((prev) => prev.filter((_, i) => i !== index));
                    }}
                  >
                    正式候補へ昇格
                  </button>
                  <button
                    type="button"
                    className="rounded border border-white/20 px-2 py-1"
                    onClick={() =>
                      setPendingWeapons((prev) => prev.filter((_, i) => i !== index))
                    }
                  >
                    破棄
                  </button>
                </div>
              );
            })}
            {pendingArtifacts.map((raw, index) => {
              const m = asRecord(raw);
              return (
                <div key={`pa-${index}`} className="flex flex-wrap gap-2 text-xs">
                  <span>
                    聖遺物言及: {String(m.displayName ?? "")} ({String(m.setId ?? "IDなし")}) ·
                    部位数未確定
                  </span>
                  <button
                    type="button"
                    className="rounded border border-white/20 px-2 py-1"
                    disabled={busy}
                    onClick={() => {
                      setArtifacts((prev) => [
                        ...prev,
                        {
                          ...emptyArtifact(prev.length + 1),
                          mode: "undetermined",
                          setAId: String(m.setId ?? ""),
                          adminConfirmed: false,
                          recommendationLevel: "",
                          reason: "必要セット数を確認してください",
                          citationId: m.videoId ? `source-${String(m.videoId)}` : "",
                        },
                      ]);
                      setPendingArtifacts((prev) => prev.filter((_, i) => i !== index));
                    }}
                  >
                    正式候補へ昇格（未確定）
                  </button>
                  <button
                    type="button"
                    className="rounded border border-white/20 px-2 py-1"
                    onClick={() =>
                      setPendingArtifacts((prev) => prev.filter((_, i) => i !== index))
                    }
                  >
                    破棄
                  </button>
                </div>
              );
            })}
            {pendingWeapons.length === 0 && pendingArtifacts.length === 0 ? (
              <div className="text-xs text-gray-500">未確認の言及はありません</div>
            ) : null}
          </div>

          <div className="grid gap-3 md:grid-cols-2">
            <label className="block text-sm">
              育成優先度
              <select
                className="mt-1 w-full rounded-lg border border-white/10 bg-[#151d2a] px-3 py-2"
                value={investmentPriority}
                onChange={(e) => setInvestmentPriority(e.target.value)}
              >
                <option value="">未設定</option>
                <option value="high">高</option>
                <option value="medium">中</option>
                <option value="low">低</option>
              </select>
            </label>
            <label className="block text-sm">
              対象ゲームバージョン
              <input
                className="mt-1 w-full rounded-lg border border-white/10 bg-[#151d2a] px-3 py-2"
                value={gameVersion}
                onChange={(e) => setGameVersion(e.target.value)}
                placeholder="例: 5.8"
              />
            </label>
          </div>

          <div
            ref={(el) => {
              sectionRefs.current.weapons = el;
            }}
            className="space-y-2"
          >
            <div className="flex items-center justify-between">
              <h3 className="text-sm font-bold">おすすめ武器</h3>
              <button
                type="button"
                className="rounded border border-white/20 px-2 py-1 text-xs"
                onClick={() => setWeapons((prev) => [...prev, emptyWeapon(prev.length + 1)])}
              >
                追加
              </button>
            </div>
            <input
              className="w-full rounded border border-white/10 bg-[#151d2a] px-2 py-1 text-xs"
              value={weaponQuery}
              onChange={(e) => setWeaponQuery(e.target.value)}
              placeholder="武器マスター検索（名前 / ID）"
            />
            {filteredWeapons.length > 0 ? (
              <div className="max-h-28 overflow-auto rounded border border-white/10 p-2 text-xs">
                {filteredWeapons.map((w) => (
                  <button
                    key={w.id}
                    type="button"
                    className="mb-1 mr-2 inline-flex items-center gap-1 rounded border border-white/10 px-2 py-1"
                    onClick={() =>
                      setWeapons((prev) => {
                        if (prev.length === 0) {
                          return [
                            {
                              ...emptyWeapon(1),
                              weaponId: w.id,
                              displayName: w.name,
                            },
                          ];
                        }
                        const last = prev.length - 1;
                        return prev.map((row, i) =>
                          i === last
                            ? { ...row, weaponId: w.id, displayName: w.name }
                            : row,
                        );
                      })
                    }
                  >
                    {w.iconUrl ? (
                      // eslint-disable-next-line @next/next/no-img-element
                      <img src={w.iconUrl} alt="" className="h-5 w-5" />
                    ) : null}
                    {w.rarity}★ {w.name}
                  </button>
                ))}
              </div>
            ) : null}
            {weapons.map((w, index) => {
              const unknownWeapon =
                Boolean(w.weaponId) &&
                Boolean(masters) &&
                !masters!.weapons.some((m) => m.id === w.weaponId);
              return (
                <div key={index} className="space-y-2 rounded-lg bg-[#151d2a] p-3 text-sm">
                  <div className="text-xs text-gray-400">
                    由来: {labelOf(DATA_ORIGIN_LABELS, w.dataOrigin)} ·{" "}
                    {w.adminConfirmed ? "管理者確認済み" : "未確認"}
                    {unknownWeapon ? (
                      <span className="ml-2 text-amber-300">不明な武器ID: {w.weaponId}</span>
                    ) : null}
                  </div>
                  <div className="font-medium">
                    {w.displayName || "武器未選択"}{" "}
                    <span className="text-xs text-gray-500">{w.weaponId}</span>
                  </div>
                  <div className="grid gap-2 md:grid-cols-2">
                    <label className="text-xs">
                      順位
                      <input
                        type="number"
                        className="mt-1 w-full rounded border border-white/10 bg-[#0f1622] px-2 py-1"
                        value={w.rank}
                        onChange={(e) =>
                          setWeapons((prev) =>
                            prev.map((row, i) =>
                              i === index
                                ? { ...row, rank: Number(e.target.value) || 1 }
                                : row,
                            ),
                          )
                        }
                      />
                    </label>
                    <label className="text-xs">
                      推奨レベル
                      <select
                        className="mt-1 w-full rounded border border-white/10 bg-[#0f1622] px-2 py-1"
                        value={w.recommendationLevel}
                        onChange={(e) =>
                          setWeapons((prev) =>
                            prev.map((row, i) =>
                              i === index
                                ? { ...row, recommendationLevel: e.target.value }
                                : row,
                            ),
                          )
                        }
                      >
                        <option value="">未設定</option>
                        {Object.entries(RECOMMENDATION_LEVEL_LABELS).map(([k, v]) => (
                          <option key={k} value={k}>
                            {v}
                          </option>
                        ))}
                      </select>
                    </label>
                  </div>
                  <label className="block text-xs">
                    理由
                    <textarea
                      className="mt-1 w-full rounded border border-white/10 bg-[#0f1622] px-2 py-1"
                      rows={2}
                      value={w.reason}
                      onChange={(e) =>
                        setWeapons((prev) =>
                          prev.map((row, i) =>
                            i === index ? { ...row, reason: e.target.value } : row,
                          ),
                        )
                      }
                    />
                  </label>
                  <label className="block text-xs">
                    条件
                    <input
                      className="mt-1 w-full rounded border border-white/10 bg-[#0f1622] px-2 py-1"
                      value={w.conditionsText}
                      onChange={(e) =>
                        setWeapons((prev) =>
                          prev.map((row, i) =>
                            i === index
                              ? { ...row, conditionsText: e.target.value }
                              : row,
                          ),
                        )
                      }
                    />
                  </label>
                  <label className="block text-xs">
                    出典
                    <CitationSelect
                      value={w.citationId}
                      options={citationOptions}
                      onChange={(v) =>
                        setWeapons((prev) =>
                          prev.map((row, i) =>
                            i === index ? { ...row, citationId: v } : row,
                          ),
                        )
                      }
                    />
                  </label>
                  <label className="flex items-center gap-2 text-xs">
                    <input
                      type="checkbox"
                      checked={w.adminConfirmed}
                      onChange={(e) =>
                        setWeapons((prev) =>
                          prev.map((row, i) =>
                            i === index
                              ? { ...row, adminConfirmed: e.target.checked }
                              : row,
                          ),
                        )
                      }
                    />
                    管理者確認済み
                  </label>
                  <div className="flex gap-2">
                    <button
                      type="button"
                      className="rounded border border-white/20 px-2 py-1 text-xs"
                      onClick={() =>
                        setWeapons((prev) => prev.filter((_, i) => i !== index))
                      }
                    >
                      削除
                    </button>
                    <button
                      type="button"
                      className="rounded border border-white/20 px-2 py-1 text-xs"
                      disabled={index === 0}
                      onClick={() =>
                        setWeapons((prev) => {
                          if (index === 0) return prev;
                          const next = [...prev];
                          [next[index - 1], next[index]] = [next[index]!, next[index - 1]!];
                          return next.map((row, i) => ({ ...row, rank: i + 1 }));
                        })
                      }
                    >
                      上へ
                    </button>
                    <button
                      type="button"
                      className="rounded border border-white/20 px-2 py-1 text-xs"
                      disabled={index >= weapons.length - 1}
                      onClick={() =>
                        setWeapons((prev) => {
                          if (index >= prev.length - 1) return prev;
                          const next = [...prev];
                          [next[index], next[index + 1]] = [next[index + 1]!, next[index]!];
                          return next.map((row, i) => ({ ...row, rank: i + 1 }));
                        })
                      }
                    >
                      下へ
                    </button>
                  </div>
                </div>
              );
            })}
          </div>

          <div
            ref={(el) => {
              sectionRefs.current.artifactRecommendations = el;
            }}
            className="space-y-2"
          >
            <div className="flex items-center justify-between">
              <h3 className="text-sm font-bold">おすすめ聖遺物</h3>
              <button
                type="button"
                className="rounded border border-white/20 px-2 py-1 text-xs"
                onClick={() =>
                  setArtifacts((prev) => [...prev, emptyArtifact(prev.length + 1)])
                }
              >
                追加
              </button>
            </div>
            {artifacts.map((a, index) => {
              const sameSetWarn =
                a.mode === "two_two" && a.setAId && a.setBId && a.setAId === a.setBId;
              return (
                <div key={index} className="space-y-2 rounded-lg bg-[#151d2a] p-3 text-sm">
                  <label className="block text-xs">
                    構成形式
                    <select
                      className="mt-1 w-full rounded border border-white/10 bg-[#0f1622] px-2 py-1"
                      value={a.mode}
                      onChange={(e) =>
                        setArtifacts((prev) =>
                          prev.map((row, i) =>
                            i === index
                              ? {
                                  ...row,
                                  mode: e.target.value as ArtifactCompositionMode,
                                  setBId:
                                    e.target.value === "two_two" ? row.setBId : "",
                                  adminConfirmed:
                                    e.target.value === "undetermined"
                                      ? false
                                      : row.adminConfirmed,
                                }
                              : row,
                          ),
                        )
                      }
                    >
                      <option value="four">4セット</option>
                      <option value="two_two">2セット＋2セット</option>
                      <option value="two">2セット</option>
                      <option value="undetermined">未確定</option>
                    </select>
                  </label>
                  <div className="rounded border border-white/10 bg-[#101826] px-2 py-1 text-xs whitespace-pre-wrap">
                    {formatArtifactCompositionPreview(
                      a.mode,
                      a.setAId,
                      a.setBId,
                      setNameOf,
                    )}
                  </div>
                  <ArtifactSetPicker
                    label={a.mode === "two_two" ? "セットA" : "聖遺物セット"}
                    value={a.setAId}
                    sets={masters?.artifactSets ?? []}
                    query={setQueryA[index] ?? ""}
                    onQueryChange={(q) =>
                      setSetQueryA((prev) => ({ ...prev, [index]: q }))
                    }
                    onSelect={(setId) =>
                      setArtifacts((prev) =>
                        prev.map((row, i) =>
                          i === index ? { ...row, setAId: setId } : row,
                        ),
                      )
                    }
                    disabled={!masters?.artifactSets.length}
                  />
                  {a.mode === "two_two" ? (
                    <ArtifactSetPicker
                      label="セットB"
                      value={a.setBId}
                      sets={masters?.artifactSets ?? []}
                      query={setQueryB[index] ?? ""}
                      onQueryChange={(q) =>
                        setSetQueryB((prev) => ({ ...prev, [index]: q }))
                      }
                      onSelect={(setId) =>
                        setArtifacts((prev) =>
                          prev.map((row, i) =>
                            i === index ? { ...row, setBId: setId } : row,
                          ),
                        )
                      }
                      disabled={!masters?.artifactSets.length}
                    />
                  ) : null}
                  {sameSetWarn ? (
                    <p className="text-xs text-amber-300">
                      同一セットの 2+2 です。意図を確認してください。
                    </p>
                  ) : null}
                  {a.mode === "undetermined" ? (
                    <p className="text-xs text-amber-300">
                      未確定構成は下書き保存できますが、承認・公開できません。
                    </p>
                  ) : null}
                  <label className="block text-xs">
                    理由
                    <textarea
                      className="mt-1 w-full rounded border border-white/10 bg-[#0f1622] px-2 py-1"
                      rows={2}
                      value={a.reason}
                      onChange={(e) =>
                        setArtifacts((prev) =>
                          prev.map((row, i) =>
                            i === index ? { ...row, reason: e.target.value } : row,
                          ),
                        )
                      }
                    />
                  </label>
                  <label className="block text-xs">
                    出典
                    <CitationSelect
                      value={a.citationId}
                      options={citationOptions}
                      onChange={(v) =>
                        setArtifacts((prev) =>
                          prev.map((row, i) =>
                            i === index ? { ...row, citationId: v } : row,
                          ),
                        )
                      }
                    />
                  </label>
                  <label className="flex items-center gap-2 text-xs">
                    <input
                      type="checkbox"
                      checked={a.adminConfirmed}
                      disabled={a.mode === "undetermined"}
                      onChange={(e) =>
                        setArtifacts((prev) =>
                          prev.map((row, i) =>
                            i === index
                              ? { ...row, adminConfirmed: e.target.checked }
                              : row,
                          ),
                        )
                      }
                    />
                    管理者確認済み
                  </label>
                  <button
                    type="button"
                    className="rounded border border-white/20 px-2 py-1 text-xs"
                    onClick={() =>
                      setArtifacts((prev) => prev.filter((_, i) => i !== index))
                    }
                  >
                    削除
                  </button>
                </div>
              );
            })}
          </div>

          <div
            ref={(el) => {
              sectionRefs.current.mainStats = el;
            }}
            className="space-y-2"
          >
            <h3 className="text-sm font-bold">メインステータス</h3>
            {mainStats.map((m, index) => {
              const overlap = m.primary.filter((p) => m.alternative.includes(p));
              return (
                <div key={m.slot} className="space-y-2 rounded-lg bg-[#151d2a] p-3">
                  <div className="text-sm font-medium">
                    {SLOT_LABELS[m.slot]}（{m.slot}）
                  </div>
                  <MultiStatSelect
                    label="第一候補"
                    slot={m.slot}
                    values={m.primary}
                    onChange={(primary) =>
                      setMainStats((prev) =>
                        prev.map((row, i) => (i === index ? { ...row, primary } : row)),
                      )
                    }
                  />
                  <MultiStatSelect
                    label="代替"
                    slot={m.slot}
                    values={m.alternative}
                    onChange={(alternative) =>
                      setMainStats((prev) =>
                        prev.map((row, i) =>
                          i === index ? { ...row, alternative } : row,
                        ),
                      )
                    }
                  />
                  {overlap.length > 0 ? (
                    <p className="text-xs text-amber-300">
                      primary と alternative の重複: {overlap.join("、")}
                    </p>
                  ) : null}
                  <label className="block text-xs">
                    条件
                    <input
                      className="mt-1 w-full rounded border border-white/10 bg-[#0f1622] px-2 py-1"
                      value={m.condition}
                      onChange={(e) =>
                        setMainStats((prev) =>
                          prev.map((row, i) =>
                            i === index ? { ...row, condition: e.target.value } : row,
                          ),
                        )
                      }
                    />
                  </label>
                  <label className="block text-xs">
                    出典
                    <CitationSelect
                      value={m.citationId}
                      options={citationOptions}
                      onChange={(v) =>
                        setMainStats((prev) =>
                          prev.map((row, i) =>
                            i === index ? { ...row, citationId: v } : row,
                          ),
                        )
                      }
                    />
                  </label>
                </div>
              );
            })}
          </div>

          <div
            ref={(el) => {
              sectionRefs.current.targets = el;
            }}
            className="space-y-2"
          >
            <div className="flex items-center justify-between">
              <h3 className="text-sm font-bold">目標ステータス</h3>
              <button
                type="button"
                className="rounded border border-white/20 px-2 py-1 text-xs"
                onClick={() =>
                  setTargets((prev) => [
                    ...prev,
                    emptyTarget(`t-${Date.now()}-${prev.length}`),
                  ])
                }
              >
                行を追加
              </button>
            </div>
            {targets.map((t, index) => {
              const unitWarn = unitWarnForStat(t.stat, t.unit);
              const { warnings } = targetDraftToPayload(t);
              return (
                <div key={t.id} className="space-y-2 rounded-lg bg-[#151d2a] p-3 text-sm">
                  <div className="grid gap-2 md:grid-cols-2">
                    <label className="text-xs">
                      ステータス
                      <select
                        className="mt-1 w-full rounded border border-white/10 bg-[#0f1622] px-2 py-1"
                        value={`${t.stat}|${t.unit || ""}`}
                        onChange={(e) => {
                          const [stat, unit] = e.target.value.split("|");
                          setTargets((prev) =>
                            prev.map((row, i) =>
                              i === index
                                ? {
                                    ...row,
                                    stat: stat ?? row.stat,
                                    unit: (unit as "flat" | "percent" | "") || "",
                                  }
                                : row,
                            ),
                          );
                        }}
                      >
                        {TARGET_STAT_OPTIONS.map((opt) => (
                          <option
                            key={`${opt.id}-${opt.defaultUnit}-${opt.label}`}
                            value={`${opt.id}|${opt.defaultUnit}`}
                          >
                            {opt.label}
                          </option>
                        ))}
                      </select>
                    </label>
                    <label className="text-xs">
                      値の形式
                      <select
                        className="mt-1 w-full rounded border border-white/10 bg-[#0f1622] px-2 py-1"
                        value={t.valueType}
                        onChange={(e) =>
                          setTargets((prev) =>
                            prev.map((row, i) =>
                              i === index
                                ? {
                                    ...row,
                                    valueType: e.target
                                      .value as TargetDraft["valueType"],
                                    minimum: "",
                                    maximum: "",
                                    target: "",
                                  }
                                : row,
                            ),
                          )
                        }
                      >
                        {(Object.keys(VALUE_TYPE_LABELS) as Array<TargetDraft["valueType"]>).map(
                          (k) => (
                            <option key={k} value={k}>
                              {VALUE_TYPE_LABELS[k]}
                            </option>
                          ),
                        )}
                      </select>
                    </label>
                  </div>
                  {t.valueType === "minimum" || t.valueType === "range" ? (
                    <label className="block text-xs">
                      最小値
                      <input
                        className="mt-1 w-full rounded border border-white/10 bg-[#0f1622] px-2 py-1"
                        value={t.minimum}
                        onChange={(e) =>
                          setTargets((prev) =>
                            prev.map((row, i) =>
                              i === index ? { ...row, minimum: e.target.value } : row,
                            ),
                          )
                        }
                      />
                    </label>
                  ) : null}
                  {t.valueType === "maximum" || t.valueType === "range" ? (
                    <label className="block text-xs">
                      最大値
                      <input
                        className="mt-1 w-full rounded border border-white/10 bg-[#0f1622] px-2 py-1"
                        value={t.maximum}
                        onChange={(e) =>
                          setTargets((prev) =>
                            prev.map((row, i) =>
                              i === index ? { ...row, maximum: e.target.value } : row,
                            ),
                          )
                        }
                      />
                    </label>
                  ) : null}
                  {t.valueType === "target" ? (
                    <label className="block text-xs">
                      目標値
                      <input
                        className="mt-1 w-full rounded border border-white/10 bg-[#0f1622] px-2 py-1"
                        value={t.target}
                        onChange={(e) =>
                          setTargets((prev) =>
                            prev.map((row, i) =>
                              i === index ? { ...row, target: e.target.value } : row,
                            ),
                          )
                        }
                      />
                    </label>
                  ) : null}
                  {t.valueType === "ratio" ? (
                    <p className="rounded border border-amber-500/40 bg-amber-500/10 px-2 py-1 text-xs text-amber-100">
                      注意: ratio（比率）は現在のモバイル版では表示されない可能性があります。API
                      には含まれますが互換 targets には載りません。他の目標値は欠落しません。
                    </p>
                  ) : null}
                  {t.valueType === "ratio" ? (
                    <div className="grid gap-2 md:grid-cols-2">
                      <label className="text-xs">
                        左ステータス
                        <select
                          className="mt-1 w-full rounded border border-white/10 bg-[#0f1622] px-2 py-1"
                          value={t.leftStat}
                          onChange={(e) =>
                            setTargets((prev) =>
                              prev.map((row, i) =>
                                i === index ? { ...row, leftStat: e.target.value } : row,
                              ),
                            )
                          }
                        >
                          {TARGET_STAT_OPTIONS.filter(
                            (o, i, arr) =>
                              arr.findIndex((x) => x.id === o.id) === i,
                          ).map((o) => (
                            <option key={o.id} value={o.id}>
                              {o.label.replace("%", "")}
                            </option>
                          ))}
                        </select>
                      </label>
                      <label className="text-xs">
                        左の値
                        <input
                          className="mt-1 w-full rounded border border-white/10 bg-[#0f1622] px-2 py-1"
                          value={t.leftValue}
                          onChange={(e) =>
                            setTargets((prev) =>
                              prev.map((row, i) =>
                                i === index ? { ...row, leftValue: e.target.value } : row,
                              ),
                            )
                          }
                        />
                      </label>
                      <label className="text-xs">
                        右ステータス
                        <select
                          className="mt-1 w-full rounded border border-white/10 bg-[#0f1622] px-2 py-1"
                          value={t.rightStat}
                          onChange={(e) =>
                            setTargets((prev) =>
                              prev.map((row, i) =>
                                i === index ? { ...row, rightStat: e.target.value } : row,
                              ),
                            )
                          }
                        >
                          {TARGET_STAT_OPTIONS.filter(
                            (o, i, arr) =>
                              arr.findIndex((x) => x.id === o.id) === i,
                          ).map((o) => (
                            <option key={o.id} value={o.id}>
                              {o.label.replace("%", "")}
                            </option>
                          ))}
                        </select>
                      </label>
                      <label className="text-xs">
                        右の値
                        <input
                          className="mt-1 w-full rounded border border-white/10 bg-[#0f1622] px-2 py-1"
                          value={t.rightValue}
                          onChange={(e) =>
                            setTargets((prev) =>
                              prev.map((row, i) =>
                                i === index
                                  ? { ...row, rightValue: e.target.value }
                                  : row,
                              ),
                            )
                          }
                        />
                      </label>
                    </div>
                  ) : null}
                  <label className="block text-xs">
                    単位
                    <select
                      className="mt-1 w-full rounded border border-white/10 bg-[#0f1622] px-2 py-1"
                      value={t.unit}
                      onChange={(e) =>
                        setTargets((prev) =>
                          prev.map((row, i) =>
                            i === index
                              ? {
                                  ...row,
                                  unit: e.target.value as TargetDraft["unit"],
                                }
                              : row,
                          ),
                        )
                      }
                    >
                      <option value="">未設定</option>
                      <option value="percent">{UNIT_LABELS.percent}</option>
                      <option value="flat">{UNIT_LABELS.flat}</option>
                    </select>
                  </label>
                  {unitWarn ? (
                    <p className="text-xs text-amber-300">{unitWarn}</p>
                  ) : null}
                  {warnings.map((w) => (
                    <p key={w} className="text-xs text-amber-300">
                      {w}
                    </p>
                  ))}
                  <label className="block text-xs">
                    条件
                    <input
                      className="mt-1 w-full rounded border border-white/10 bg-[#0f1622] px-2 py-1"
                      value={t.condition}
                      onChange={(e) =>
                        setTargets((prev) =>
                          prev.map((row, i) =>
                            i === index ? { ...row, condition: e.target.value } : row,
                          ),
                        )
                      }
                    />
                  </label>
                  <label className="block text-xs">
                    出典
                    <CitationSelect
                      value={t.citationId}
                      options={citationOptions}
                      onChange={(v) =>
                        setTargets((prev) =>
                          prev.map((row, i) =>
                            i === index ? { ...row, citationId: v } : row,
                          ),
                        )
                      }
                    />
                  </label>
                  <div className="flex gap-2">
                    <button
                      type="button"
                      className="rounded border border-white/20 px-2 py-1 text-xs"
                      onClick={() =>
                        setTargets((prev) => prev.filter((_, i) => i !== index))
                      }
                    >
                      削除
                    </button>
                    <button
                      type="button"
                      className="rounded border border-white/20 px-2 py-1 text-xs"
                      disabled={index === 0}
                      onClick={() =>
                        setTargets((prev) => {
                          if (index === 0) return prev;
                          const next = [...prev];
                          [next[index - 1], next[index]] = [next[index]!, next[index - 1]!];
                          return next;
                        })
                      }
                    >
                      上へ
                    </button>
                    <button
                      type="button"
                      className="rounded border border-white/20 px-2 py-1 text-xs"
                      disabled={index >= targets.length - 1}
                      onClick={() =>
                        setTargets((prev) => {
                          if (index >= prev.length - 1) return prev;
                          const next = [...prev];
                          [next[index], next[index + 1]] = [next[index + 1]!, next[index]!];
                          return next;
                        })
                      }
                    >
                      下へ
                    </button>
                  </div>
                </div>
              );
            })}
            {targets.length === 0 ? (
              <p className="text-xs text-gray-500">目標ステータスは未設定です</p>
            ) : null}
          </div>

          <label className="block text-sm">
            管理者メモ
            <textarea
              className="mt-1 w-full rounded-lg border border-white/10 bg-[#151d2a] px-3 py-2"
              rows={2}
              value={adminNotes}
              onChange={(e) => setAdminNotes(e.target.value)}
            />
          </label>

          <label className="flex items-center gap-2 text-sm">
            <input
              type="checkbox"
              checked={keepPublished}
              onChange={(e) => setKeepPublished(e.target.checked)}
              disabled={selected.status !== "published"}
            />
            公開を維持したまま作業下書きを保存（公開 API は旧データを返します）
          </label>

          <div className="flex flex-wrap gap-2">
            <button
              type="button"
              disabled={busy}
              aria-busy={busy}
              aria-label={busy ? "保存処理中" : "下書きを保存"}
              title={busy ? "別の処理の完了を待っています" : undefined}
              className="rounded-lg bg-accent px-3 py-2 text-sm text-black disabled:opacity-40"
              onClick={() => void saveDraft()}
            >
              {busy ? "処理中…" : "下書き保存"}
            </button>
            <button
              type="button"
              disabled={busy}
              className="rounded border border-white/20 px-3 py-2 text-sm"
              onClick={() => void runValidate()}
            >
              検証
            </button>
            <button
              type="button"
              disabled={busy}
              className="rounded border border-white/20 px-3 py-2 text-sm"
              onClick={() => void runPreview()}
            >
              公開APIプレビュー
            </button>
            <button
              type="button"
              disabled={busy}
              className="rounded border border-white/20 px-3 py-2 text-sm"
              onClick={() =>
                void postAction({
                  action: "approveRecommendation",
                  recommendationId: selected.id,
                })
              }
            >
              承認
            </button>
            <button
              type="button"
              disabled={busy}
              className="rounded border border-accent/40 px-3 py-2 text-sm"
              onClick={() => {
                if (
                  !window.confirm(
                    "公開しますか？未確定構成や重大エラーがある場合は拒否されます。",
                  )
                ) {
                  return;
                }
                void postAction({
                  action: "publishRecommendation",
                  recommendationId: selected.id,
                }).then((result) => {
                  const r = result as {
                    error?: string;
                    detail?: string;
                    publishIssues?: Array<{ path: string }>;
                  };
                  if (r?.error) {
                    setLocalError(
                      `${r.error}${r.detail ? `: ${r.detail}` : ""}`,
                    );
                    if (r.detail) {
                      const path = r.detail.split(":")[0];
                      if (path) setFocusPath(path);
                    }
                  }
                });
              }}
            >
              公開
            </button>
            <button
              type="button"
              disabled={busy}
              className="rounded border border-white/20 px-3 py-2 text-sm"
              onClick={() => {
                if (!window.confirm("公開を取り消しますか？")) return;
                void postAction({
                  action: "unpublishRecommendation",
                  recommendationId: selected.id,
                });
              }}
            >
              公開取り消し
            </button>
            <button
              type="button"
              disabled={busy}
              className="rounded border border-white/20 px-3 py-2 text-sm"
              onClick={() => {
                if (!window.confirm("未保存の変更を破棄しますか？")) return;
                const id = selected.id;
                setSelectedId("");
                setTimeout(() => setSelectedId(id), 0);
              }}
            >
              変更破棄
            </button>
          </div>

          {localError ? <p className="text-sm text-red-300">{localError}</p> : null}
          {localOk ? <p className="text-sm text-emerald-300">{localOk}</p> : null}

          {validationJson ? (
            <div className="rounded-lg border border-white/10 bg-[#151d2a] p-3">
              <h3 className="text-sm font-bold">検証結果</h3>
              <pre className="mt-2 max-h-60 overflow-auto whitespace-pre-wrap text-xs text-gray-400">
                {validationJson}
              </pre>
            </div>
          ) : null}

          {previewJson ? (
            <div className="rounded-lg border border-white/10 bg-[#151d2a] p-3">
              <h3 className="text-sm font-bold">正規化後プレビュー</h3>
              <pre className="mt-2 max-h-80 overflow-auto whitespace-pre-wrap text-xs text-gray-400">
                {previewJson}
              </pre>
            </div>
          ) : null}

          <div className="rounded-lg border border-white/10 p-3">
            <h3 className="text-sm font-bold">変更履歴</h3>
            <ul className="mt-2 max-h-40 space-y-1 overflow-auto text-xs text-gray-400">
              {selected.revisions.map((rev) => (
                <li key={rev.id} className="flex flex-wrap items-center gap-2">
                  <span>
                    {rev.createdAt} · {rev.action} · {rev.actor}
                  </span>
                  {rev.action === "override" || rev.action === "override_draft" ? (
                    <button
                      type="button"
                      className="rounded border border-white/20 px-2 py-0.5"
                      disabled={busy}
                      onClick={() => {
                        if (
                          !window.confirm(
                            "この履歴の変更前スナップショットへ戻しますか？",
                          )
                        ) {
                          return;
                        }
                        void postAction({
                          action: "restoreRecommendationRevision",
                          recommendationId: selected.id,
                          revisionId: rev.id,
                          expectedUpdatedAt: selected.updatedAt,
                        });
                      }}
                    >
                      変更前へ復元
                    </button>
                  ) : null}
                </li>
              ))}
            </ul>
          </div>

          <div className="rounded-lg border border-dashed border-white/20 p-3">
            <button
              type="button"
              className="text-xs underline text-gray-400"
              onClick={() => setShowDebugJson((v) => !v)}
            >
              {showDebugJson ? "詳細JSONを隠す" : "詳細JSON（読み取り専用・開発用）"}
            </button>
            {showDebugJson ? (
              <>
                <p className="mt-2 text-xs text-amber-300">
                  通常操作では編集しないでください。保存の正は専用フォームです。
                </p>
                <pre className="mt-2 max-h-60 overflow-auto whitespace-pre-wrap text-xs text-gray-500">
                  {JSON.stringify(debugPayload, null, 2)}
                </pre>
              </>
            ) : null}
          </div>
        </>
      )}
    </section>
  );
}
