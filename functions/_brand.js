// Branding shared by the Cloudflare Pages Functions.
//
// Set these in Cloudflare → Pages → (project) → Settings → Variables:
//   APP_NAME        e.g. "Bellamia Lashes Studio"
//   APP_SHORT_NAME  e.g. "Bellamia"   (home-screen label, keep it short)
//   THEME_COLOR     e.g. "#8F5E78"
//
// Files whose name starts with "_" are not routes.

export function brand(env) {
  const name = (env && env.APP_NAME) || "Mi tarjeta";
  const shortName = (env && env.APP_SHORT_NAME) || name;
  const color = /^#[0-9a-fA-F]{6}$/.test((env && env.THEME_COLOR) || "")
    ? env.THEME_COLOR
    : "#8F5E78";
  return { name, shortName, color };
}

export function escapeHtml(value) {
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}
