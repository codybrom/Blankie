import { describe, expect, it } from "vitest";
import {
  itemListLd,
  ldGraph,
  organizationLd,
  softwareAppLd,
  videoLd,
  websiteLd,
} from "./schema";
import { SOCIAL_LINKS } from "./socials";

describe("homepage JSON-LD", () => {
  it("describes the SoftwareApplication", () => {
    const app = softwareAppLd({ withRating: true });
    expect(app["@type"]).toBe("SoftwareApplication");
    expect(app.description.length).toBeGreaterThan(50);
    expect(app.aggregateRating).toBeDefined();
  });

  it("names the WebSite at the root URL", () => {
    const site = websiteLd();
    expect(site["@type"]).toBe("WebSite");
    expect(site.name).toBe("Blankie");
    expect(site.url).toBe("https://blankie.rest/");
    expect(site.publisher["@id"]).toBe(organizationLd()["@id"]);
  });

  it("lists every footer profile as sameAs on the Organization", () => {
    const org = organizationLd();
    expect(org["@type"]).toBe("Organization");
    expect(org.sameAs).toEqual(SOCIAL_LINKS.map((s) => s.href));
    expect(org.founder.name).toBe("Cody Bromley");
    expect(org.contactPoint.url).toBe("https://blankie.rest/contact/");
    expect(org.address).toEqual({
      "@type": "PostalAddress",
      addressCountry: "US",
    });
  });

  it("adds the screenshot only when given one", () => {
    expect(softwareAppLd()).not.toHaveProperty("screenshot");
    const app = softwareAppLd({
      screenshot: { path: "/_astro/hero.png", caption: "Blankie" },
    });
    expect(app.screenshot).toEqual({
      "@type": "ImageObject",
      url: "https://blankie.rest/_astro/hero.png",
      caption: "Blankie",
    });
  });

  it("describes a product video with absolute URLs", () => {
    const video = videoLd({
      name: "Lock Screen",
      description: "Blankie on the Lock Screen.",
      path: "/_astro/lock.mp4",
      thumbnailPath: "/_astro/lock.jpg",
      uploadDate: "2026-10-28",
    });
    expect(video["@type"]).toBe("VideoObject");
    expect(video.contentUrl).toBe("https://blankie.rest/_astro/lock.mp4");
    expect(video.thumbnailUrl).toBe("https://blankie.rest/_astro/lock.jpg");
    expect(video.uploadDate).toBe("2026-10-28");
  });

  it("numbers list items from one", () => {
    const list = itemListLd("Features", [
      { name: "Offline", description: "Works without a connection." },
      { name: "Private", description: "Collects nothing." },
    ]);
    expect(list["@type"]).toBe("ItemList");
    expect(list.itemListElement.map((i) => i.position)).toEqual([1, 2]);
    expect(list.itemListElement[1]).toMatchObject({
      "@type": "ListItem",
      name: "Private",
    });
  });

  it("wraps nodes in a schema.org graph", () => {
    const graph = ldGraph(websiteLd(), organizationLd());
    expect(graph["@context"]).toBe("https://schema.org");
    expect(graph["@graph"]).toHaveLength(2);
  });
});
