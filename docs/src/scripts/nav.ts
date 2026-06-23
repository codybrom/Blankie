// Smooth-scroll behaviors for download links and the logo on the index page.
// (The mobile/tablet menu is now the shadcn Sheet in MobileNav.tsx.)
class SiteNavigation {
  private logoLink: HTMLElement | null;
  // Fixed header (80px) plus a little breathing room.
  private readonly SCROLL_OFFSET = 88;

  constructor() {
    this.logoLink = document.getElementById("logo-link");
    this.init();
  }

  private init(): void {
    this.setupDownloadLinks();
    this.setupLogoLink();
    this.handleInitialLoad();
  }

  private isIndexPage(): boolean {
    return (
      window.location.pathname === "/" ||
      window.location.pathname.endsWith("index.html")
    );
  }

  private prefersReducedMotion(): boolean {
    return window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  }

  private setupDownloadLinks(): void {
    // Catch the nav "Download" (/#download) plus any legacy section=download links.
    document
      .querySelectorAll<HTMLAnchorElement>(
        'a[href$="#download"], a[href*="section=download"]',
      )
      .forEach((anchor) => {
        anchor.addEventListener("click", (e: Event) => {
          if (this.isIndexPage()) {
            e.preventDefault();
            this.scrollToDownload(true);
            history.pushState(null, "", "/#download");
          }
        });
      });
  }

  private setupLogoLink(): void {
    this.logoLink?.addEventListener("click", (e: Event) => {
      if (this.isIndexPage()) {
        e.preventDefault();
        this.scrollToTop();
        history.pushState(null, "", "/");
      }
    });
  }

  // Scroll to #download, then re-snap once lazy images above it have settled
  // (otherwise the smooth scroll drifts as the page grows mid-animation).
  private scrollToDownload(smooth: boolean): void {
    const target = document.getElementById("download");
    if (!target) return;

    const go = (behavior: ScrollBehavior) => {
      const top =
        target.getBoundingClientRect().top +
        window.scrollY -
        this.SCROLL_OFFSET;
      window.scrollTo({ top, behavior });
    };

    go(smooth && !this.prefersReducedMotion() ? "smooth" : "auto");
    window.setTimeout(() => go("auto"), 700);
  }

  private scrollToTop(): void {
    window.scrollTo({
      top: 0,
      behavior: this.prefersReducedMotion() ? "auto" : "smooth",
    });
  }

  private handleInitialLoad(): void {
    window.addEventListener("load", () => {
      const params = new URLSearchParams(window.location.search);
      if (
        params.get("section") === "download" ||
        window.location.hash === "#download"
      ) {
        this.scrollToDownload(false);
      }
    });
  }
}

// Initialize when DOM is ready
document.addEventListener("DOMContentLoaded", () => {
  new SiteNavigation();
});
