import { describe, expect, it } from "vitest";
import { ldGraph, organizationLd, softwareAppLd, websiteLd } from "./schema";
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
  });

  it("wraps nodes in a schema.org graph", () => {
    const graph = ldGraph(websiteLd(), organizationLd());
    expect(graph["@context"]).toBe("https://schema.org");
    expect(graph["@graph"]).toHaveLength(2);
  });
});
