// Smooth-scroll behaviors for download links and the logo on the index page.
// (The mobile/tablet menu is now the shadcn Sheet in MobileNav.tsx.)
class SiteNavigation {
  private logoLink: HTMLElement | null;
  private readonly HEADER_HEIGHT = 80;
  private readonly ADDITIONAL_OFFSET = 200;

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

  private setupDownloadLinks(): void {
    document
      .querySelectorAll('a[href*="section=download"]')
      .forEach((anchor) => {
        anchor.addEventListener("click", (e: Event) => {
          const link = e.currentTarget as HTMLAnchorElement;
          const href = link.getAttribute("href");

          if (this.isIndexPage() && href) {
            e.preventDefault();
            this.scrollToDownload();
            history.pushState(null, "", href);
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

  private scrollToElement(element: Element, offset = 0): void {
    requestAnimationFrame(() => {
      const elementPosition = element.getBoundingClientRect().top;
      const offsetPosition = elementPosition + window.scrollY - offset;

      window.scrollTo({
        top: offsetPosition,
        behavior: "smooth",
      });
    });
  }

  private scrollToDownload(): void {
    const target = document.querySelector("#download");
    if (target) {
      const totalOffset = this.HEADER_HEIGHT + this.ADDITIONAL_OFFSET;
      this.scrollToElement(target, totalOffset);
    }
  }

  private scrollToTop(): void {
    window.scrollTo({
      top: 0,
      behavior: "smooth",
    });
  }

  private handleInitialLoad(): void {
    window.addEventListener("load", () => {
      const params = new URLSearchParams(window.location.search);
      if (params.get("section") === "download") {
        this.scrollToDownload();
      }
    });
  }
}

// Initialize when DOM is ready
document.addEventListener("DOMContentLoaded", () => {
  new SiteNavigation();
});
