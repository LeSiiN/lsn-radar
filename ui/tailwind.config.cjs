module.exports = {
  darkmode: true,
  content: ["./index.html", "./src/**/*.{svelte,js,ts}"],
  theme: {
    extend: {
      // Same palette as ps-dispatch / ps-mdt (variables.css).
      colors: {
        primary: "#0e0f0f",
        secondary: "#171717",
        tertiary: "#1d1d1d",
        accent: "#3b82f6",
        accent_green: "#299e6d",
        accent_red: "#ef4444",
        border_primary: "rgba(255, 255, 255, 0.08)",
      },
    },
  },
  plugins: [],
};
