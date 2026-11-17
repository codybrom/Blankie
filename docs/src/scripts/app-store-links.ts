// App Store badges link to the iPhone listing. On an iPad, point them at the iPad
// listing instead. iPadOS Safari reports a Mac user agent, so it's spotted by touch.
const isIPad =
  /iPad/.test(navigator.userAgent) ||
  (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1);

if (isIPad) {
  for (const link of document.querySelectorAll<HTMLAnchorElement>(
    "a[data-app-store]",
  )) {
    const url = new URL(link.href);
    url.searchParams.set("platform", "ipad");
    link.href = url.href;
  }
}
