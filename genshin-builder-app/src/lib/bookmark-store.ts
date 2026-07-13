"use client";

/**
 * ブックマーク localStorage のクライアントストア
 *
 * useSyncExternalStore で SSR 安全に読み込み、
 * effect 内 setState による lint 違反を避ける。
 *
 * getServerSnapshot は毎回同じ frozen 配列を返すことで
 * React の「infinite loop」警告を防止する。
 * getSnapshot は localStorage 文字列のキャッシュ＋比較で
 * 不要な再レンダリングを抑える。
 */

import { useCallback, useSyncExternalStore } from "react";
import { saveBookmarkEntries } from "@/lib/bookmark-storage";
import type { MaterialBookmarkEntry } from "@/types/bookmark";
import { BOOKMARK_STORAGE_KEY } from "@/types/bookmark";

type Listener = () => void;
const listeners = new Set<Listener>();

/** 空状態の共有配列 — モジュールスコープで1度だけ生成、毎回同じ参照 */
const EMPTY_BOOKMARK_ENTRIES: MaterialBookmarkEntry[] = [];

let cachedRaw: string | undefined;
let cachedParsed: MaterialBookmarkEntry[] | undefined;

function getClientSnapshot(): MaterialBookmarkEntry[] {
  if (typeof window === "undefined") return EMPTY_BOOKMARK_ENTRIES;
  try {
    const raw = localStorage.getItem(BOOKMARK_STORAGE_KEY);
    // 前回と同じ文字列ならキャッシュを返す（新しい参照を作らない）
    if (raw === cachedRaw && cachedParsed !== undefined) {
      return cachedParsed;
    }
    cachedRaw = raw ?? undefined;
    if (!raw) {
      cachedParsed = EMPTY_BOOKMARK_ENTRIES;
      return cachedParsed;
    }
    const parsed = JSON.parse(raw) as unknown;
    cachedParsed = Array.isArray(parsed) ? parsed : EMPTY_BOOKMARK_ENTRIES;
    return cachedParsed;
  } catch {
    // JSON 不正 → 空の frozen 配列
    cachedRaw = undefined;
    cachedParsed = EMPTY_BOOKMARK_ENTRIES;
    return cachedParsed;
  }
}

function getServerSnapshot(): MaterialBookmarkEntry[] {
  // 毎回同じ frozen 参照を返す → infinite loop 警告を防止
  return EMPTY_BOOKMARK_ENTRIES;
}

let storageListenerAttached = false;

function subscribe(listener: Listener): () => void {
  listeners.add(listener);

  // 別タブからの storage イベントを1回だけ購読
  if (!storageListenerAttached && typeof window !== "undefined") {
    storageListenerAttached = true;
    window.addEventListener("storage", (e: StorageEvent) => {
      if (e.key === BOOKMARK_STORAGE_KEY) {
        // キャッシュを無効化し、全リスナーに通知
        cachedRaw = undefined;
        cachedParsed = undefined;
        listeners.forEach((fn) => fn());
      }
    });
  }

  return () => {
    listeners.delete(listener);
  };
}

function emit(): void {
  listeners.forEach((listener) => listener());
}

export function getBookmarkEntriesSnapshot(): MaterialBookmarkEntry[] {
  if (typeof window === "undefined") return EMPTY_BOOKMARK_ENTRIES;
  return getClientSnapshot();
}

export function setBookmarkEntriesSnapshot(
  entries: MaterialBookmarkEntry[],
): void {
  // キャッシュを更新してから localStorage に書き込む
  cachedRaw = JSON.stringify(entries);
  cachedParsed = entries;
  saveBookmarkEntries(entries);
  emit();
}

export function useBookmarkEntriesSnapshot(): MaterialBookmarkEntry[] {
  return useSyncExternalStore(
    subscribe,
    getClientSnapshot,
    getServerSnapshot,
  );
}

export function useBookmarkEntriesMutation() {
  return useCallback(
    (
      updater: (prev: MaterialBookmarkEntry[]) => MaterialBookmarkEntry[],
    ) => {
      setBookmarkEntriesSnapshot(updater(getBookmarkEntriesSnapshot()));
    },
    [],
  );
}
