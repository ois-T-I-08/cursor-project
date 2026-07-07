/**
 * 共通フッター（Server Component）
 */
export default function Footer() {
  return (
    <footer className="border-t border-white/10 bg-[#151d2a]">
      <div className="mx-auto flex max-w-6xl flex-col items-center gap-1 px-4 py-6 text-center text-xs text-gray-500 sm:px-6">
        <p>Genshin Builder — 原神キャラクター育成管理</p>
        <p>
          本アプリは非公式のファンメイドツールです。原神は HoYoverse
          の登録商標です。
        </p>
      </div>
    </footer>
  );
}
