export default function AdminLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <div className="legacy-dark-surface min-h-screen bg-[#0f1419] text-[#e8e6e3]">
      <main className="mx-auto w-full max-w-6xl px-4 py-6 sm:px-6">
        {children}
      </main>
    </div>
  );
}
