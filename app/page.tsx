export default function Home() {
  return (
    <main
      style={{
        minHeight: "100vh",
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
        padding: "2rem",
        gap: "1.5rem",
        textAlign: "center",
      }}
    >
      <h1>Welcome to your fresh Next.js project</h1>
      <p>
        Start building by editing <code>app/page.tsx</code> or adding routes under the <code>app</code> directory.
      </p>
    </main>
  );
}
