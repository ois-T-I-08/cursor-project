"use client";

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";
import {
  aggregateBookmarkEntries,
  loadBookmarkEntries,
  removeBookmarkEntry,
  removeBookmarksByMaterialId,
  saveBookmarkEntries,
  toggleSingleBookmark,
  upsertBookmarkBatch,
  isMaterialBookmarked,
} from "@/lib/bookmark-storage";
import type {
  AggregatedMaterialBookmark,
  MaterialBookmarkEntry,
} from "@/types/bookmark";

interface MaterialBookmarkContextValue {
  entries: MaterialBookmarkEntry[];
  aggregated: AggregatedMaterialBookmark[];
  addBatch: (batch: MaterialBookmarkEntry[]) => void;
  toggleEntry: (entry: MaterialBookmarkEntry) => void;
  removeByMaterialId: (materialId: string) => void;
  removeEntry: (id: string) => void;
  isBookmarked: (sourceKey: string, materialId: string) => boolean;
  clearAll: () => void;
}

const MaterialBookmarkContext =
  createContext<MaterialBookmarkContextValue | null>(null);

export function MaterialBookmarkProvider({ children }: { children: ReactNode }) {
  const [entries, setEntries] = useState<MaterialBookmarkEntry[]>([]);
  const [hydrated, setHydrated] = useState(false);

  useEffect(() => {
    setEntries(loadBookmarkEntries());
    setHydrated(true);
  }, []);

  useEffect(() => {
    if (!hydrated) return;
    saveBookmarkEntries(entries);
  }, [entries, hydrated]);

  const aggregated = useMemo(
    () => aggregateBookmarkEntries(entries),
    [entries],
  );

  const addBatch = useCallback((batch: MaterialBookmarkEntry[]) => {
    setEntries((prev) => upsertBookmarkBatch(prev, batch));
  }, []);

  const toggleEntry = useCallback((entry: MaterialBookmarkEntry) => {
    setEntries((prev) => toggleSingleBookmark(prev, entry));
  }, []);

  const removeByMaterialId = useCallback((materialId: string) => {
    setEntries((prev) => removeBookmarksByMaterialId(prev, materialId));
  }, []);

  const removeEntry = useCallback((id: string) => {
    setEntries((prev) => removeBookmarkEntry(prev, id));
  }, []);

  const isBookmarked = useCallback(
    (sourceKey: string, materialId: string) =>
      isMaterialBookmarked(entries, sourceKey, materialId),
    [entries],
  );

  const clearAll = useCallback(() => setEntries([]), []);

  const value = useMemo(
    () => ({
      entries,
      aggregated,
      addBatch,
      toggleEntry,
      removeByMaterialId,
      removeEntry,
      isBookmarked,
      clearAll,
    }),
    [
      entries,
      aggregated,
      addBatch,
      toggleEntry,
      removeByMaterialId,
      removeEntry,
      isBookmarked,
      clearAll,
    ],
  );

  return (
    <MaterialBookmarkContext.Provider value={value}>
      {children}
    </MaterialBookmarkContext.Provider>
  );
}

export function useMaterialBookmarks(): MaterialBookmarkContextValue {
  const ctx = useContext(MaterialBookmarkContext);
  if (!ctx) {
    throw new Error(
      "useMaterialBookmarks must be used within MaterialBookmarkProvider",
    );
  }
  return ctx;
}
