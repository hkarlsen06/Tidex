// server component
export default function AuthLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="min-h-screen bg-slate-950 text-slate-100 antialiased">
      <div className="app-container">
        <main className="px-4 pb-24 pt-6">{children}</main>
      </div>
    </div>
  );
}
