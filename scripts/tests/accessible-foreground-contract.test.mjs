import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const appRoot = fileURLToPath(new URL("../../OpenLARP", import.meta.url));
const stylePath = join(appRoot, "Style", "OpenLARPStyle.swift");
const decorativeForegroundPattern = /\.foregroundStyle\(.*(?:Color\.|\.)(openLARPBlue|openLARPGreen|openLARPCoral|openLARPPurple)\b/;

function swiftFiles(directory) {
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) return swiftFiles(path);
    return entry.isFile() && entry.name.endsWith(".swift") ? [path] : [];
  });
}

function contrastAgainstWhite([red, green, blue]) {
  const linearize = (value) => value <= 0.04045
    ? value / 12.92
    : ((value + 0.055) / 1.055) ** 2.4;
  const luminance = 0.2126 * linearize(red) +
    0.7152 * linearize(green) +
    0.0722 * linearize(blue);
  return 1.05 / (luminance + 0.05);
}

function sourceBetween(source, start, end) {
  const startIndex = source.indexOf(start);
  const endIndex = source.indexOf(end, startIndex + start.length);
  expect(startIndex).toBeGreaterThanOrEqual(0);
  expect(endIndex).toBeGreaterThan(startIndex);
  return source.slice(startIndex, endIndex);
}

describe("accessible foreground contract", () => {
  it("keeps decorative accent tokens out of foreground styling", () => {
    const offenders = swiftFiles(appRoot).flatMap((path) =>
      readFileSync(path, "utf8")
        .split("\n")
        .map((line, index) => ({ line, lineNumber: index + 1 }))
        .filter(({ line }) => decorativeForegroundPattern.test(line))
        .map(({ lineNumber }) => `${path}:${lineNumber}`)
    );

    expect(offenders).toEqual([]);
  });

  it.each([
    ["openLARPSuccessText", [0.04, 0.40, 0.22]],
    ["openLARPAttentionText", [0.65, 0.08, 0.20]],
    ["openLARPPurpleText", [0.25, 0.20, 0.62]],
    ["openLARPOrangeText", [0.58, 0.25, 0.05]],
  ])("defines %s with at least 4.5:1 contrast on white", (token, rgb) => {
    const styleSource = readFileSync(stylePath, "utf8");
    expect(styleSource).toContain(`static let ${token} = Color`);
    expect(contrastAgainstWhite(rgb)).toBeGreaterThanOrEqual(4.5);
  });

  it("keeps shared light-surface components on accessible foregrounds", () => {
    const styleSource = readFileSync(stylePath, "utf8");
    const pill = sourceBetween(styleSource, "struct Pill: View", "struct PrimaryButtonStyle");
    const hero = sourceBetween(styleSource, "struct OpenLARPHeroCard: View", "struct SectionHeader: View");
    const sectionHeader = sourceBetween(styleSource, "struct SectionHeader: View", "struct SummaryTile: View");
    const summaryTile = sourceBetween(styleSource, "struct SummaryTile: View", "struct SprintStrip: View");

    expect(pill).toContain(".foregroundStyle(Color.openLARPInk)");
    expect(pill).not.toContain(".foregroundStyle(color)");
    expect(hero).toContain(".foregroundStyle(Color.openLARPInk)");
    expect(hero).toContain(".background(.white)");
    expect(sectionHeader).toContain(".foregroundStyle(feature.textAccent)");
    expect(summaryTile).toContain(".foregroundStyle(Color.openLARPInk)");
    expect(summaryTile).not.toContain(".foregroundStyle(color)");
  });
});
