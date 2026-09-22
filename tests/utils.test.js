import { describe, it, expect } from "vitest";
import utilsModule from "../utils.js";

const {
  dealClass,
  extractDealPct,
  dealRatingLabel,
  formatPriceShort,
  jsonStatValue,
  computeYoyTrendPct,
  computeHistoryChangePct,
  sparklineSvg,
} = utilsModule;

describe("dealClass", () => {
  it("classifies a below-market Czech rating as good", () => {
    expect(dealClass("Pod tržní cenou (-8 %)")).toBe("deal-good");
  });

  it("classifies a 'great deal' rating as good", () => {
    expect(dealClass("Skvělá nabídka (-15 %)")).toBe("deal-good");
  });

  it("classifies an above-market rating as bad", () => {
    expect(dealClass("Nadprůměrná cena (+6 %)")).toBe("deal-bad");
  });

  it("classifies a plain market-price rating as neutral", () => {
    expect(dealClass("Tržní cena")).toBe("deal-neutral");
  });
});

describe("extractDealPct", () => {
  it("reads a negative percentage", () => {
    expect(extractDealPct("Pod tržní cenou (-8 %)")).toBe(-8);
  });

  it("reads a positive percentage", () => {
    expect(extractDealPct("Nadprůměrná cena (+6 %)")).toBe(6);
  });

  it("returns null when there's no percentage", () => {
    expect(extractDealPct("Tržní cena")).toBeNull();
  });
});

describe("dealRatingLabel", () => {
  const labels = {
    marketPrice: "Market price",
    belowMarket: "Below market price",
    greatDeal: "Great deal",
    aboveMarket: "Above-average price",
  };

  it("returns the Czech string verbatim in cs locale", () => {
    expect(dealRatingLabel(null, "cs", "Pod tržní cenou (-8 %)", labels)).toBe("Pod tržní cenou (-8 %)");
  });

  it("translates a below-market rating to English", () => {
    expect(dealRatingLabel(null, "en", "Pod tržní cenou (-8 %)", labels)).toBe("Below market price (-8%)");
  });

  it("uses 'great deal' at exactly -12%, the documented boundary", () => {
    expect(dealRatingLabel(null, "en", "Skvělá nabídka (-12 %)", labels)).toBe("Great deal (-12%)");
  });

  it("uses 'below market' just short of the -12% boundary", () => {
    expect(dealRatingLabel(null, "en", "Pod tržní cenou (-11 %)", labels)).toBe("Below market price (-11%)");
  });

  it("translates an above-market rating to English with an explicit +", () => {
    expect(dealRatingLabel(null, "en", "Nadprůměrná cena (+6 %)", labels)).toBe("Above-average price (+6%)");
  });

  it("translates a plain market-price rating to English", () => {
    expect(dealRatingLabel(null, "en", "Tržní cena", labels)).toBe("Market price");
  });
});

describe("formatPriceShort", () => {
  it("formats millions with up to two decimals and the given currency", () => {
    expect(formatPriceShort(9260000, "Kč")).toBe("9.26M Kč");
  });

  it("drops a trailing zero decimal", () => {
    expect(formatPriceShort(15800000, "Kč")).toBe("15.8M Kč");
  });

  it("drops both decimals for a round number of millions", () => {
    expect(formatPriceShort(6000000, "CZK")).toBe("6M CZK");
  });
});

describe("jsonStatValue", () => {
  // A minimal two-dimension JSON-stat fixture: District x Year.
  const dataset = {
    id: ["District", "Year"],
    size: [2, 3],
    dimension: {
      District: { category: { index: { PRAHA: 0, BRNO: 1 } } },
      Year: { category: { index: { "2023": 0, "2024": 1, "2025": 2 } } },
    },
    // flat = district * 3 + year
    value: [100, 110, 120, 200, 210, 220],
  };

  it("resolves the correct value for the first district/year", () => {
    expect(jsonStatValue(dataset, { District: "PRAHA", Year: "2023" })).toBe(100);
  });

  it("resolves a value from the middle of the flattened array", () => {
    expect(jsonStatValue(dataset, { District: "PRAHA", Year: "2025" })).toBe(120);
  });

  it("resolves a value from the second district", () => {
    expect(jsonStatValue(dataset, { District: "BRNO", Year: "2024" })).toBe(210);
  });
});

describe("computeYoyTrendPct", () => {
  it("computes a positive year-on-year change", () => {
    expect(computeYoyTrendPct(131520, 115889)).toBeCloseTo(13.487, 2);
  });

  it("computes a negative year-on-year change", () => {
    expect(computeYoyTrendPct(90, 100)).toBeCloseTo(-10, 5);
  });

  it("returns null when there is no prior value", () => {
    expect(computeYoyTrendPct(100, null)).toBeNull();
  });

  it("returns null rather than dividing by zero", () => {
    expect(computeYoyTrendPct(100, 0)).toBeNull();
  });
});

describe("computeHistoryChangePct", () => {
  it("computes overall change across a price history series", () => {
    expect(computeHistoryChangePct([9500000, 9400000, 9300000, 9260000])).toBeCloseTo(-2.526, 2);
  });

  it("returns null for fewer than two points", () => {
    expect(computeHistoryChangePct([9260000])).toBeNull();
    expect(computeHistoryChangePct([])).toBeNull();
  });
});

describe("sparklineSvg", () => {
  it("returns an empty string for fewer than two points", () => {
    expect(sparklineSvg([1])).toBe("");
    expect(sparklineSvg([])).toBe("");
    expect(sparklineSvg(null)).toBe("");
  });

  it("renders an SVG with one point per price", () => {
    const svg = sparklineSvg([100, 90, 95, 80]);
    expect(svg).toContain("<svg");
    expect(svg).toContain("<polyline");
    const pointsMatch = svg.match(/points="([^"]+)"/);
    expect(pointsMatch[1].trim().split(" ")).toHaveLength(4);
  });

  it("colors a falling price series with the down color", () => {
    const svg = sparklineSvg([100, 90, 80], { downColor: "#00ff00", upColor: "#ff0000" });
    expect(svg).toContain("#00ff00");
    expect(svg).not.toContain("#ff0000");
  });

  it("colors a rising price series with the up color", () => {
    const svg = sparklineSvg([80, 90, 100], { downColor: "#00ff00", upColor: "#ff0000" });
    expect(svg).toContain("#ff0000");
    expect(svg).not.toContain("#00ff00");
  });
});
