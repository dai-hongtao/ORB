const FONT_STACKS = {
  sans: "Source Han Sans CN Medium, Noto Sans CJK SC, sans-serif"
};
const BUILT_IN_FONT_OPTIONS = [
  { value: FONT_STACKS.sans, label: "思源黑体 CN" }
];
const DEFAULT_FONT_FAMILY = FONT_STACKS.sans;
const SAFE_FONT_FAMILIES = new Set(Object.values(FONT_STACKS));
const FONT_ENTRY_ALIAS = {
  "source han sans cn": "sourceHanSansCn",
  "source han sans cn medium": "sourceHanSansCn",
  "noto sans cjk sc": "sourceHanSansCn",
  "noto sans sc": "sourceHanSansCn",
  "microsoft yahei": "sourceHanSansCn",
  "simhei": "sourceHanSansCn",
  "arial": "sourceHanSansCn",
  "helvetica neue": "sourceHanSansCn",
  "helvetica": "sourceHanSansCn",
  "din alternate": "sourceHanSansCn",
  "avenir next": "sourceHanSansCn",
  "sans-serif": "sourceHanSansCn",
  "lxgw wenkai tc": "sourceHanSansCn",
  "lxgw wenkai": "sourceHanSansCn",
  "times new roman": "sourceHanSansCn",
  "georgia": "sourceHanSansCn",
  "serif": "sourceHanSansCn",
  "source code pro": "sourceHanSansCn",
  "courier new": "sourceHanSansCn",
  "menlo": "sourceHanSansCn",
  "monospace": "sourceHanSansCn"
};
const OUTLINE_FALLBACK_KEYS = ["sourceHanSansCn"];
const OUTER_FRAME_STROKE_MM = 0.1;
const HAIRLINE_STROKE_MM = 0.01;
const HISTORY_LIMIT = 120;
const CUSTOM_FONT_DIR = "./Font/";
const parsedFontCache = new Map();
const customFontOptions = [];
const customFontStacks = new Set();
const customFontStyleUrls = new Set();

function createMajorTick(overrides = {}) {
  return {
    id: crypto.randomUUID(),
    valueText: "",
    showValue: true,
    unitText: "M",
    showUnit: true,
    percent: 100,
    subdivisions: 10,
    dxMm: 0,
    dyMm: 0,
    fontSizeMm: 2.5,
    fontFamily: DEFAULT_FONT_FAMILY,
    ...overrides
  };
}

function createFreeText(overrides = {}) {
  return {
    id: crypto.randomUUID(),
    text: "新文字",
    xMm: 26,
    yMm: 10,
    fontSizeMm: 2.5,
    fontFamily: DEFAULT_FONT_FAMILY,
    ...overrides
  };
}

function normalizeFontFamily(raw) {
  const value = String(raw || "").trim();
  if (!value) {
    return DEFAULT_FONT_FAMILY;
  }
  if (SAFE_FONT_FAMILIES.has(value) || customFontStacks.has(value)) {
    return value;
  }
  return DEFAULT_FONT_FAMILY;
}

function normalizeMajorTick(raw = {}) {
  return createMajorTick({
    id: typeof raw.id === "string" && raw.id ? raw.id : crypto.randomUUID(),
    valueText: String(raw.valueText ?? ""),
    showValue: raw.showValue == null ? true : Boolean(raw.showValue),
    unitText: ["K", "M", "G"].includes(String(raw.unitText ?? "").toUpperCase()) ? String(raw.unitText).toUpperCase() : "M",
    showUnit: raw.showUnit == null ? true : Boolean(raw.showUnit),
    percent: clamp(Math.round(Number(raw.percent) || 0), 0, 100),
    subdivisions: Math.max(1, Math.round(Number(raw.subdivisions) || 1)),
    dxMm: Number.isFinite(Number(raw.dxMm)) ? Number(raw.dxMm) : 0,
    dyMm: Number.isFinite(Number(raw.dyMm)) ? Number(raw.dyMm) : 0,
    fontSizeMm: Math.max(0.1, Number(raw.fontSizeMm) || 2.5),
    fontFamily: normalizeFontFamily(raw.fontFamily)
  });
}

function normalizeFreeText(raw = {}) {
  return createFreeText({
    id: typeof raw.id === "string" && raw.id ? raw.id : crypto.randomUUID(),
    text: String(raw.text ?? "新文字"),
    xMm: Number.isFinite(Number(raw.xMm)) ? Number(raw.xMm) : 26,
    yMm: Number.isFinite(Number(raw.yMm)) ? Number(raw.yMm) : 10,
    fontSizeMm: Math.max(0.1, Number(raw.fontSizeMm) || 2.5),
    fontFamily: normalizeFontFamily(raw.fontFamily)
  });
}

function createDefaultState() {
  return {
    widthMm: 52,
    heightMm: 20,
    centerX: 26,
    centerY: 34,
    arcStartDeg: -45,
    arcEndDeg: 45,
    arcRadiusMm: 27,
    arcStrokeWidthMm: 0.4,
    majorTickLengthMm: 2.4,
    minorTickLengthMm: 1.2,
    majorTickWidthMm: 0.4,
    minorTickWidthMm: 0.2,
    needleLengthMm: 31.5,
    needleWidthMm: 0.4,
    showNeedle: true,
    previewPercent: 35,
    snapEnabled: true,
    majorTicks: [
      createMajorTick({ valueText: "500", unitText: "K", showUnit: true, percent: 20, subdivisions: 5 }),
      createMajorTick({ valueText: "1", unitText: "M", showUnit: true, percent: 40, subdivisions: 5 }),
      createMajorTick({ valueText: "5", unitText: "M", showUnit: true, percent: 55, subdivisions: 5 }),
      createMajorTick({ valueText: "10", unitText: "M", showUnit: true, percent: 70, subdivisions: 5 }),
      createMajorTick({ valueText: "50", unitText: "M", showUnit: true, percent: 83, subdivisions: 5 }),
      createMajorTick({ valueText: "100", unitText: "M", showUnit: true, percent: 96, subdivisions: 5 }),
      createMajorTick({ valueText: "130", unitText: "M", showUnit: true, percent: 100, subdivisions: 2 })
    ],
    freeTexts: [
      createFreeText({
        text: "网速 下行",
        xMm: 26,
        yMm: 15,
        fontSizeMm: 2.5
      })
    ]
  };
}

function normalizeState(rawState = {}) {
  const defaults = createDefaultState();
  const nextState = {
    widthMm: Math.max(1, Number(rawState.widthMm) || defaults.widthMm),
    heightMm: Math.max(1, Number(rawState.heightMm) || defaults.heightMm),
    centerX: Number.isFinite(Number(rawState.centerX)) ? Number(rawState.centerX) : defaults.centerX,
    centerY: Number.isFinite(Number(rawState.centerY)) ? Number(rawState.centerY) : defaults.centerY,
    arcStartDeg: Number.isFinite(Number(rawState.arcStartDeg)) ? Number(rawState.arcStartDeg) : defaults.arcStartDeg,
    arcEndDeg: Number.isFinite(Number(rawState.arcEndDeg)) ? Number(rawState.arcEndDeg) : defaults.arcEndDeg,
    arcRadiusMm: Math.max(0.1, Number(rawState.arcRadiusMm) || defaults.arcRadiusMm),
    arcStrokeWidthMm: Math.max(0, Number(rawState.arcStrokeWidthMm) || defaults.arcStrokeWidthMm),
    majorTickLengthMm: Math.max(0, Number(rawState.majorTickLengthMm) || defaults.majorTickLengthMm),
    minorTickLengthMm: Math.max(0, Number(rawState.minorTickLengthMm) || defaults.minorTickLengthMm),
    majorTickWidthMm: Math.max(0, Number(rawState.majorTickWidthMm) || defaults.majorTickWidthMm),
    minorTickWidthMm: Math.max(0, Number(rawState.minorTickWidthMm) || defaults.minorTickWidthMm),
    needleLengthMm: Math.max(0.1, Number(rawState.needleLengthMm) || defaults.needleLengthMm),
    needleWidthMm: Math.max(0, Number(rawState.needleWidthMm) || defaults.needleWidthMm),
    showNeedle: rawState.showNeedle == null ? defaults.showNeedle : Boolean(rawState.showNeedle),
    previewPercent: clamp(Number(rawState.previewPercent) || defaults.previewPercent, 0, 100),
    snapEnabled: rawState.snapEnabled == null ? defaults.snapEnabled : Boolean(rawState.snapEnabled),
    majorTicks: Array.isArray(rawState.majorTicks) && rawState.majorTicks.length
      ? rawState.majorTicks.map((tick) => normalizeMajorTick(tick))
      : defaults.majorTicks.map((tick) => normalizeMajorTick(tick)),
    freeTexts: Array.isArray(rawState.freeTexts)
      ? rawState.freeTexts.map((item) => normalizeFreeText(item))
      : defaults.freeTexts.map((item) => normalizeFreeText(item))
  };
  nextState.majorTicks.sort((a, b) => a.percent - b.percent);
  return nextState;
}

let state = createDefaultState();
let selection = state.majorTicks[0] ? { type: "majorTick", id: state.majorTicks[0].id } : null;
let editorOpen = false;
let dragState = null;

const historyState = {
  entries: [],
  index: -1,
  isApplying: false
};

const fields = {
  widthMm: document.getElementById("widthMm"),
  heightMm: document.getElementById("heightMm"),
  centerX: document.getElementById("centerX"),
  centerY: document.getElementById("centerY"),
  arcStartDeg: document.getElementById("arcStartDeg"),
  arcEndDeg: document.getElementById("arcEndDeg"),
  arcRadiusMm: document.getElementById("arcRadiusMm"),
  arcStrokeWidthMm: document.getElementById("arcStrokeWidthMm"),
  majorTickLengthMm: document.getElementById("majorTickLengthMm"),
  minorTickLengthMm: document.getElementById("minorTickLengthMm"),
  majorTickWidthMm: document.getElementById("majorTickWidthMm"),
  minorTickWidthMm: document.getElementById("minorTickWidthMm"),
  needleLengthMm: document.getElementById("needleLengthMm"),
  needleWidthMm: document.getElementById("needleWidthMm"),
  showNeedle: document.getElementById("showNeedle")
};

const previewSvg = document.getElementById("preview-svg");
const snapToggleButton = document.getElementById("snap-toggle");
const addMenuToggleButton = document.getElementById("add-menu-toggle");
const addMenu = document.getElementById("add-menu");
const addMajorTickButton = document.getElementById("add-major-tick");
const addFreeTextButton = document.getElementById("add-free-text");
const importSettingsButton = document.getElementById("import-settings");
const importSettingsFileInput = document.getElementById("import-settings-file");
const exportSettingsButton = document.getElementById("export-settings");
const downloadPngButton = document.getElementById("download-png");
const undoButton = document.getElementById("undo-action");
const redoButton = document.getElementById("redo-action");
const speedMetric = document.getElementById("speed-metric");
const inlineEditor = document.getElementById("inline-editor");
const inlineEditorTitle = document.getElementById("inline-editor-title");
const tickEditorFields = document.getElementById("tick-editor-fields");
const freeTextEditorFields = document.getElementById("free-text-editor-fields");
const deleteInlineItemButton = document.getElementById("inline-delete-item");

const tickFields = {
  valueText: document.getElementById("tickValueText"),
  showValue: document.getElementById("tickShowValue"),
  unitText: document.getElementById("tickUnitText"),
  showUnit: document.getElementById("tickShowUnit"),
  percent: document.getElementById("tickPercent"),
  subdivisions: document.getElementById("tickSubdivisions"),
  fontSizeMm: document.getElementById("tickFontSizeMm"),
  fontFamily: document.getElementById("tickFontFamily"),
  syncFontSize: document.getElementById("tickSyncFontSize"),
  syncFontFamily: document.getElementById("tickSyncFontFamily")
};

const freeTextFields = {
  text: document.getElementById("freeTextContent"),
  fontSizeMm: document.getElementById("freeTextFontSizeMm"),
  fontFamily: document.getElementById("freeTextFontFamily")
};

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function getAvailableFontOptions() {
  return [...BUILT_IN_FONT_OPTIONS, ...customFontOptions];
}

function rebuildFontSelectOptions() {
  const options = getAvailableFontOptions();
  [tickFields.fontFamily, freeTextFields.fontFamily].forEach((select) => {
    if (!select) {
      return;
    }
    const currentValue = select.value;
    select.innerHTML = options
      .map((option) => `<option value="${escapeHtml(option.value)}">${escapeHtml(option.label)}</option>`)
      .join("");
    if (currentValue && options.some((option) => option.value === currentValue)) {
      select.value = currentValue;
    }
  });
}

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}

function round(value, digits = 2) {
  return Number(value.toFixed(digits));
}

function escapeXml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&apos;");
}

function getFontStackFamilies(fontStack) {
  return String(fontStack || "")
    .split(",")
    .map((item) => item.trim().replace(/^['"]|['"]$/g, ""))
    .filter(Boolean);
}

function getEmbeddedFontEntriesForStack(fontStack) {
  const entries = window.EMBEDDED_FONT_DATA || {};
  const keys = [];
  const seen = new Set();
  const pushKey = (key) => {
    if (!key || seen.has(key) || !entries[key]) {
      return;
    }
    seen.add(key);
    keys.push(key);
  };

  getFontStackFamilies(fontStack).forEach((family) => {
    pushKey(FONT_ENTRY_ALIAS[family.toLowerCase()]);
  });

  OUTLINE_FALLBACK_KEYS.forEach(pushKey);
  return keys.map((key) => entries[key]);
}

function decodeBase64ToArrayBuffer(base64) {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes.buffer;
}

function encodeArrayBufferToBase64(arrayBuffer) {
  const bytes = new Uint8Array(arrayBuffer);
  let binary = "";
  const chunkSize = 0x8000;
  for (let index = 0; index < bytes.length; index += chunkSize) {
    const chunk = bytes.subarray(index, index + chunkSize);
    binary += String.fromCharCode(...chunk);
  }
  return btoa(binary);
}

function getFontMimeType(extension) {
  switch (extension) {
    case "otf":
      return "font/otf";
    case "woff":
      return "font/woff";
    case "woff2":
      return "font/woff2";
    default:
      return "font/ttf";
  }
}

function getFontFormat(extension) {
  switch (extension) {
    case "otf":
      return "opentype";
    case "woff":
      return "woff";
    case "woff2":
      return "woff2";
    default:
      return "truetype";
  }
}

function sanitizeFontKey(value) {
  return value.replace(/[^a-z0-9]+/gi, "-").replace(/^-+|-+$/g, "").toLowerCase();
}

function inferCustomFontStack(fontFamily) {
  return `${fontFamily}, ${FONT_STACKS.sans}`;
}

function injectCustomFontFace(fontFamily, url, format) {
  const cacheKey = `${fontFamily}::${url}`;
  if (customFontStyleUrls.has(cacheKey)) {
    return;
  }
  customFontStyleUrls.add(cacheKey);
  const style = document.createElement("style");
  style.textContent = `@font-face{font-family:"${fontFamily.replace(/"/g, '\\"')}";src:url("${url}") format("${format}");font-display:block;}`;
  document.head.appendChild(style);
}

function buildEmbeddedFontBlobUrl(data, mime) {
  const arrayBuffer = decodeBase64ToArrayBuffer(data);
  const blob = new Blob([arrayBuffer], { type: mime || "font/ttf" });
  return URL.createObjectURL(blob);
}

function registerCustomFont({ family, label, url, arrayBuffer, extension }) {
  if (!family || !arrayBuffer) {
    return;
  }
  const key = `custom-${sanitizeFontKey(family)}`;
  window.EMBEDDED_FONT_DATA = window.EMBEDDED_FONT_DATA || {};
  window.EMBEDDED_FONT_DATA[key] = {
    family,
    mime: getFontMimeType(extension),
    format: getFontFormat(extension),
    data: encodeArrayBufferToBase64(arrayBuffer)
  };
  parsedFontCache.delete(family);
  FONT_ENTRY_ALIAS[family.toLowerCase()] = key;
  const stack = inferCustomFontStack(family);
  if (!customFontStacks.has(stack)) {
    customFontStacks.add(stack);
    customFontOptions.push({ value: stack, label: label || family });
  }
  injectCustomFontFace(family, url, getFontFormat(extension));
}

function getCustomFontFileCandidatesFromHtml(htmlText) {
  const baseUrl = new URL(CUSTOM_FONT_DIR, window.location.href);
  const matches = [...htmlText.matchAll(/href\s*=\s*["']([^"']+)["']/gi)];
  const files = matches
    .map((match) => match[1])
    .filter(Boolean)
    .map((href) => href.split("?")[0].split("#")[0])
    .map((href) => decodeURIComponent(href))
    .filter((href) => /\.(ttf|otf|woff2?|TTF|OTF|WOFF2?)$/.test(href));
  return [...new Set(files.map((href) => href.startsWith("http") ? href : new URL(href, baseUrl).href))];
}

async function discoverCustomFontUrls() {
  const urls = new Map();
  const baseUrl = new URL(CUSTOM_FONT_DIR, window.location.href);
  try {
    const response = await fetch(CUSTOM_FONT_DIR, { cache: "no-store" });
    if (response.ok) {
      getCustomFontFileCandidatesFromHtml(await response.text()).forEach((url) => {
        if (!urls.has(url)) {
          urls.set(url, { url, label: "" });
        }
      });
    }
  } catch (error) {
    console.debug("Font directory listing unavailable", error);
  }

  return [...urls.values()];
}

async function loadCustomFontsFromFolder() {
  if (!window.opentype) {
    return;
  }
  const entries = await discoverCustomFontUrls();
  if (!entries.length) {
    return;
  }
  for (const entry of entries) {
    const url = entry.url;
    try {
      let arrayBuffer;
      let sourceUrl = url;
      let extension = entry.extension || (url.split(".").pop() || "ttf").toLowerCase();
      if (entry.data) {
        arrayBuffer = decodeBase64ToArrayBuffer(entry.data);
        sourceUrl = url || buildEmbeddedFontBlobUrl(entry.data, entry.mime);
      } else {
        const response = await fetch(url, { cache: "no-store" });
        if (!response.ok) {
          continue;
        }
        arrayBuffer = await response.arrayBuffer();
      }
      const parsed = window.opentype.parse(arrayBuffer);
      const family = entry.family || parsed.names.preferredFamily?.en || parsed.names.fontFamily?.en || parsed.names.fullName?.en;
      registerCustomFont({ family, label: entry.label, url: sourceUrl, arrayBuffer, extension });
    } catch (error) {
      console.warn("Custom font load failed", url, error);
    }
  }
  rebuildFontSelectOptions();
}

function getParsedFont(entry) {
  if (!entry || !window.opentype) {
    return null;
  }
  if (!parsedFontCache.has(entry.family)) {
    parsedFontCache.set(entry.family, window.opentype.parse(decodeBase64ToArrayBuffer(entry.data)));
  }
  return parsedFontCache.get(entry.family);
}

function getParsedFontsForStack(fontStack) {
  return getEmbeddedFontEntriesForStack(fontStack)
    .map((entry) => getParsedFont(entry))
    .filter(Boolean);
}

function getFontMetricsMm(font, fontSizeMm) {
  return {
    ascent: (font.ascender / font.unitsPerEm) * fontSizeMm,
    descent: (Math.abs(font.descender) / font.unitsPerEm) * fontSizeMm
  };
}

function getBaselineY(y, primaryFont, fontSizeMm, dominantBaseline) {
  const { ascent, descent } = getFontMetricsMm(primaryFont, fontSizeMm);
  switch ((dominantBaseline || "alphabetic").toLowerCase()) {
    case "middle":
    case "central":
      return y + (ascent - descent) / 2;
    case "text-after-edge":
    case "ideographic":
      return y - descent;
    case "hanging":
      return y + ascent;
    default:
      return y;
  }
}

function getGlyphAdvanceMm(glyph, font, fontSizeMm) {
  return ((glyph.advanceWidth || font.unitsPerEm) / font.unitsPerEm) * fontSizeMm;
}

function findSupportingFont(char, fonts) {
  if (!fonts.length) {
    return null;
  }
  if (!char.trim()) {
    return fonts[0];
  }
  return fonts.find((font) => font.charToGlyphIndex(char) !== 0) || fonts[0];
}

function getTextOutlineLayout({ text, x, y, fontSizeMm, fontFamily, textAnchor, dominantBaseline }) {
  if (!text) {
    return null;
  }

  const fonts = getParsedFontsForStack(fontFamily);
  const primaryFont = fonts[0];
  if (!primaryFont) {
    return null;
  }

  const glyphs = Array.from(text).map((char) => {
    const font = findSupportingFont(char, fonts);
    const glyph = font.charToGlyph(char);
    return { char, font, glyph };
  });

  let totalWidth = 0;
  glyphs.forEach((item, index) => {
    totalWidth += getGlyphAdvanceMm(item.glyph, item.font, fontSizeMm);
    const next = glyphs[index + 1];
    if (next && next.font === item.font) {
      totalWidth += (item.font.getKerningValue(item.glyph, next.glyph) / item.font.unitsPerEm) * fontSizeMm;
    }
  });

  let currentX = x;
  if (textAnchor === "middle") {
    currentX -= totalWidth / 2;
  } else if (textAnchor === "end") {
    currentX -= totalWidth;
  }

  const startX = currentX;
  const baselineY = getBaselineY(y, primaryFont, fontSizeMm, dominantBaseline);
  const { ascent, descent } = getFontMetricsMm(primaryFont, fontSizeMm);
  const pathData = [];

  glyphs.forEach((item, index) => {
    const glyphPath = item.font.getPath(item.char, currentX, baselineY, fontSizeMm, { kerning: false, hinting: false });
    pathData.push(glyphPath.toPathData(4));
    currentX += getGlyphAdvanceMm(item.glyph, item.font, fontSizeMm);
    const next = glyphs[index + 1];
    if (next && next.font === item.font) {
      currentX += (item.font.getKerningValue(item.glyph, next.glyph) / item.font.unitsPerEm) * fontSizeMm;
    }
  });

  return {
    pathData: pathData.join(" "),
    startX,
    baselineY,
    totalWidth,
    ascent,
    descent
  };
}

function findMajorTick(id) {
  return state.majorTicks.find((tick) => tick.id === id) ?? null;
}

function findFreeText(id) {
  return state.freeTexts.find((item) => item.id === id) ?? null;
}

function sortMajorTicks() {
  state.majorTicks.sort((a, b) => a.percent - b.percent);
}

function getSelectedItem() {
  if (!selection) {
    return null;
  }
  return selection.type === "majorTick" ? findMajorTick(selection.id) : findFreeText(selection.id);
}

function resolveSelection(nextSelection) {
  if (!nextSelection) {
    return null;
  }
  if (nextSelection.type === "majorTick" && findMajorTick(nextSelection.id)) {
    return nextSelection;
  }
  if (nextSelection.type === "freeText" && findFreeText(nextSelection.id)) {
    return nextSelection;
  }
  if (state.majorTicks[0]) {
    return { type: "majorTick", id: state.majorTicks[0].id };
  }
  if (state.freeTexts[0]) {
    return { type: "freeText", id: state.freeTexts[0].id };
  }
  return null;
}

function buildHistorySnapshot() {
  return {
    state: structuredClone(state),
    selection: selection ? { ...selection } : null,
    editorOpen
  };
}

function getSnapshotKey(snapshot) {
  return JSON.stringify(snapshot);
}

function syncHistoryButtons() {
  undoButton.disabled = historyState.index <= 0;
  redoButton.disabled = historyState.index >= historyState.entries.length - 1;
}

function restoreSnapshot(snapshot) {
  historyState.isApplying = true;
  state = structuredClone(snapshot.state);
  selection = resolveSelection(snapshot.selection);
  editorOpen = Boolean(snapshot.editorOpen && selection);
  dragState = null;
  renderAll();
  historyState.isApplying = false;
  syncHistoryButtons();
}

function commitHistory() {
  if (historyState.isApplying) {
    return;
  }
  const snapshot = buildHistorySnapshot();
  const key = getSnapshotKey(snapshot);
  const current = historyState.entries[historyState.index];
  if (current?.key === key) {
    syncHistoryButtons();
    return;
  }
  historyState.entries = historyState.entries.slice(0, historyState.index + 1);
  historyState.entries.push({ key, snapshot });
  if (historyState.entries.length > HISTORY_LIMIT) {
    historyState.entries.shift();
  }
  historyState.index = historyState.entries.length - 1;
  syncHistoryButtons();
}

function renderSnapToggle() {
  snapToggleButton.classList.toggle("active", state.snapEnabled);
  snapToggleButton.setAttribute("aria-pressed", String(state.snapEnabled));
  snapToggleButton.title = state.snapEnabled ? "磁铁吸附已开启" : "磁铁吸附已关闭";
}

function getMajorTickText(tick) {
  const valuePart = tick.showValue ? tick.valueText : "";
  const unitPart = tick.showUnit && tick.unitText ? tick.unitText : "";
  return `${valuePart}${unitPart}`;
}

function getPreferredFontFamily() {
  const selected = getSelectedItem();
  if (selection?.type === "majorTick" && selected?.fontFamily) {
    return selected.fontFamily;
  }
  if (selection?.type === "freeText" && selected?.fontFamily) {
    return selected.fontFamily;
  }
  return state.majorTicks.at(-1)?.fontFamily || DEFAULT_FONT_FAMILY;
}

function lerp(a, b, t) {
  return a + (b - a) * t;
}

function angleAtPercent(percent) {
  return lerp(state.arcStartDeg, state.arcEndDeg, clamp(percent, 0, 100) / 100);
}

function pointOnArc(radiusMm, angleDeg) {
  const radians = (angleDeg - 90) * Math.PI / 180;
  return {
    x: state.centerX + Math.cos(radians) * radiusMm,
    y: state.centerY + Math.sin(radians) * radiusMm
  };
}

function lineForTick(percent, lengthMm) {
  const angle = angleAtPercent(percent);
  const inner = pointOnArc(state.arcRadiusMm, angle);
  const outer = pointOnArc(state.arcRadiusMm + lengthMm, angle);
  return { inner, outer, angle };
}

function polygonForTick(tick, widthMm) {
  const dx = tick.outer.x - tick.inner.x;
  const dy = tick.outer.y - tick.inner.y;
  const length = Math.hypot(dx, dy) || 1;
  const nx = -dy / length;
  const ny = dx / length;
  const half = widthMm / 2;
  const p1 = { x: tick.inner.x + nx * half, y: tick.inner.y + ny * half };
  const p2 = { x: tick.outer.x + nx * half, y: tick.outer.y + ny * half };
  const p3 = { x: tick.outer.x - nx * half, y: tick.outer.y - ny * half };
  const p4 = { x: tick.inner.x - nx * half, y: tick.inner.y - ny * half };
  return `${round(p1.x, 3)},${round(p1.y, 3)} ${round(p2.x, 3)},${round(p2.y, 3)} ${round(p3.x, 3)},${round(p3.y, 3)} ${round(p4.x, 3)},${round(p4.y, 3)}`;
}

function renderTickOrLine(tickLine, widthMm, color = "#111111", extraAttributes = "") {
  if (widthMm <= 0) {
    return `<line x1="${round(tickLine.inner.x, 3)}" y1="${round(tickLine.inner.y, 3)}" x2="${round(tickLine.outer.x, 3)}" y2="${round(tickLine.outer.y, 3)}" stroke="${color}" stroke-width="${HAIRLINE_STROKE_MM}" stroke-linecap="round"${extraAttributes} />`;
  }
  return `<polygon points="${polygonForTick(tickLine, widthMm)}" fill="${color}"${extraAttributes} />`;
}

function describeArc(radiusMm) {
  const start = pointOnArc(radiusMm, state.arcStartDeg);
  const end = pointOnArc(radiusMm, state.arcEndDeg);
  const delta = state.arcEndDeg - state.arcStartDeg;
  const largeArc = Math.abs(delta) > 180 ? 1 : 0;
  const sweep = delta >= 0 ? 1 : 0;
  return `M ${round(start.x, 3)} ${round(start.y, 3)} A ${round(radiusMm, 3)} ${round(radiusMm, 3)} 0 ${largeArc} ${sweep} ${round(end.x, 3)} ${round(end.y, 3)}`;
}

function parseTickMagnitude(tick) {
  const valueText = String(tick.valueText ?? "").replaceAll(",", "").trim();
  const match = valueText.match(/[-+]?\d*\.?\d+/);
  const numeric = match ? Number(match[0]) : Number.NaN;
  const unit = String(tick.unitText || "").trim().toUpperCase();
  const factors = { K: 1, M: 1000, G: 1000 * 1000 };
  if (!Number.isFinite(numeric) || !factors[unit]) {
    return null;
  }
  return numeric * factors[unit];
}

function getOrderedScaleStops() {
  return state.majorTicks
    .map((tick) => ({ percent: tick.percent, magnitude: parseTickMagnitude(tick) }))
    .filter((item) => item.magnitude != null)
    .sort((a, b) => a.percent - b.percent);
}

function speedFromPercent(percent) {
  const safePercent = clamp(percent, 0, 100);
  const stops = getOrderedScaleStops();
  if (!stops.length) {
    return 0;
  }
  const first = stops[0];
  if (safePercent <= first.percent) {
    return lerp(0, first.magnitude, safePercent / (first.percent || 1));
  }
  for (let index = 1; index < stops.length; index += 1) {
    const previous = stops[index - 1];
    const current = stops[index];
    if (safePercent <= current.percent) {
      const t = (safePercent - previous.percent) / (current.percent - previous.percent || 1);
      return lerp(previous.magnitude, current.magnitude, t);
    }
  }
  return stops.at(-1).magnitude;
}

function formatSpeed(speedInKUnits) {
  const safe = Math.max(0, speedInKUnits);
  if (safe >= 1000 * 1000) {
    const value = safe / (1000 * 1000);
    return `${round(value, value >= 100 ? 0 : value >= 10 ? 1 : 2)}G`;
  }
  if (safe >= 1000) {
    const value = safe / 1000;
    return `${round(value, value >= 100 ? 0 : value >= 10 ? 1 : 2)}M`;
  }
  return `${round(safe, safe >= 100 ? 0 : safe >= 10 ? 1 : 2)}K`;
}

function validateTickValueOrder() {
  const sortedTicks = [...state.majorTicks].sort((a, b) => a.percent - b.percent);
  let previousValue = -Infinity;
  for (let index = 0; index < sortedTicks.length; index += 1) {
    const tick = sortedTicks[index];
    const magnitude = parseTickMagnitude(tick);
    if (magnitude == null) {
      return {
        ok: false,
        reason: "parse",
        tick,
        index,
        message: "设置有误，请检查刻度数值与单位。存在无法识别的刻度内容。"
      };
    }
    if (magnitude <= previousValue) {
      return {
        ok: false,
        reason: "order",
        tick,
        index,
        message: "设置有误，请检查刻度数值与单位。存在从左到右未递增的刻度。"
      };
    }
    previousValue = magnitude;
  }
  return { ok: true };
}

function angleFromPoint(x, y) {
  let deg = Math.atan2(y - state.centerY, x - state.centerX) * 180 / Math.PI + 90;
  if (deg > 180) {
    deg -= 360;
  }
  if (deg <= -180) {
    deg += 360;
  }
  return deg;
}

function getMajorTickLabelAnchor(tick) {
  const radius = state.arcRadiusMm + state.majorTickLengthMm + Math.max(tick.fontSizeMm * 0.6, 0.8);
  return pointOnArc(radius, angleAtPercent(tick.percent));
}

function getMajorTickLabelPosition(tick) {
  const anchor = getMajorTickLabelAnchor(tick);
  return {
    x: anchor.x + tick.dxMm,
    y: anchor.y + tick.dyMm
  };
}

function getFreeTextPosition(item) {
  return { x: item.xMm, y: item.yMm };
}

function getMinorTickPercentsForIndex(index) {
  const tick = state.majorTicks[index];
  if (!tick) {
    return [];
  }
  const divisions = Math.max(1, Math.round(tick.subdivisions));
  const startPercent = index === 0 ? 0 : state.majorTicks[index - 1].percent;
  const endPercent = tick.percent;
  const percents = [];
  for (let step = 1; step < divisions; step += 1) {
    percents.push(lerp(startPercent, endPercent, step / divisions));
  }
  return percents;
}

function buildTextShape({ text, x, y, fontSizeMm, fontFamily, previewMode, dataAttr, cursor }) {
  if (window.opentype) {
    const layout = getTextOutlineLayout({
      text,
      x,
      y,
      fontSizeMm,
      fontFamily,
      textAnchor: "middle",
      dominantBaseline: "middle"
    });
    if (layout?.pathData) {
      const hitPadding = 0.45;
      const hitRect = previewMode
        ? `<rect x="${round(layout.startX - hitPadding, 3)}" y="${round(layout.baselineY - layout.ascent - hitPadding, 3)}" width="${round(layout.totalWidth + hitPadding * 2, 3)}" height="${round(layout.ascent + layout.descent + hitPadding * 2, 3)}" fill="#ffffff" fill-opacity="0.001" ${dataAttr} style="cursor: ${cursor};" />`
        : "";
      const pathExtra = previewMode ? ` ${dataAttr} style="cursor: ${cursor};"` : "";
      return `${hitRect}<path d="${layout.pathData}" fill="#111111" fill-rule="nonzero"${pathExtra} />`;
    }
  }
  const extra = previewMode ? ` ${dataAttr} style="cursor: ${cursor};"` : "";
  return `<text x="${round(x, 3)}" y="${round(y, 3)}" font-size="${round(fontSizeMm, 3)}mm" font-family="${escapeXml(fontFamily)}" font-weight="400" text-anchor="middle" dominant-baseline="middle" fill="#111111"${extra}>${escapeXml(text)}</text>`;
}

function buildGaugeMarkup({ includeNeedle, previewMode, outlineText = false }) {
  const highlightedTickId = previewMode && dragState?.type === "tickLabel" ? dragState.id : null;
  const outerFrame = `<rect x="${round(OUTER_FRAME_STROKE_MM / 2, 3)}" y="${round(OUTER_FRAME_STROKE_MM / 2, 3)}" width="${round(state.widthMm - OUTER_FRAME_STROKE_MM, 3)}" height="${round(state.heightMm - OUTER_FRAME_STROKE_MM, 3)}" fill="none" stroke="#111111" stroke-width="${round(OUTER_FRAME_STROKE_MM, 3)}" />`;

  const guideArc = `<path d="${describeArc(state.arcRadiusMm)}" fill="none" stroke="#111111" stroke-width="${state.arcStrokeWidthMm > 0 ? round(state.arcStrokeWidthMm, 3) : HAIRLINE_STROKE_MM}" stroke-linecap="square" />`;

  const minorTicks = state.majorTicks.map((_, index) => {
    return getMinorTickPercentsForIndex(index).map((percent) => {
      const tick = lineForTick(percent, state.minorTickLengthMm);
      return renderTickOrLine(tick, state.minorTickWidthMm);
    }).join("");
  }).join("");

  const endpointTicks = [0, 100].map((percent) => {
    const tickLine = lineForTick(percent, state.majorTickLengthMm);
    return renderTickOrLine(tickLine, state.majorTickWidthMm);
  }).join("");

  const majorTicks = state.majorTicks.map((tick) => {
    const tickLine = lineForTick(tick.percent, state.majorTickLengthMm);
    const fill = highlightedTickId === tick.id ? "#c62020" : "#111111";
    const visible = renderTickOrLine(tickLine, state.majorTickWidthMm, fill);
    const hit = previewMode
      ? `<line x1="${round(tickLine.inner.x, 3)}" y1="${round(tickLine.inner.y, 3)}" x2="${round(tickLine.outer.x, 3)}" y2="${round(tickLine.outer.y, 3)}" stroke="transparent" stroke-width="${round(Math.max(state.majorTickWidthMm * 6, 2.2), 3)}" stroke-linecap="round" data-major-tick-id="${tick.id}" style="cursor: pointer;" />`
      : "";
    return `${visible}${hit}`;
  }).join("");

  const majorTickLabels = state.majorTicks.map((tick) => {
    const pos = getMajorTickLabelPosition(tick);
    const labelText = getMajorTickText(tick);
    const dataAttr = `data-major-tick-label-id="${tick.id}"`;
    return buildTextShape({
      text: labelText,
      x: pos.x,
      y: pos.y,
      fontSizeMm: tick.fontSizeMm,
      fontFamily: tick.fontFamily || DEFAULT_FONT_FAMILY,
      previewMode: previewMode && outlineText,
      dataAttr,
      cursor: "grab"
    });
  }).join("");

  const freeTexts = state.freeTexts.map((item) => {
    const pos = getFreeTextPosition(item);
    const dataAttr = `data-free-text-id="${item.id}"`;
    return buildTextShape({
      text: item.text,
      x: pos.x,
      y: pos.y,
      fontSizeMm: item.fontSizeMm,
      fontFamily: item.fontFamily || DEFAULT_FONT_FAMILY,
      previewMode: previewMode && outlineText,
      dataAttr,
      cursor: "grab"
    });
  }).join("");

  const previewNeedle = includeNeedle && state.showNeedle ? (() => {
    const angle = angleAtPercent(state.previewPercent);
    const redStart = pointOnArc(state.needleLengthMm * (2 / 3), angle);
    const end = pointOnArc(state.needleLengthMm, angle);
    return `
      <line x1="${round(state.centerX, 3)}" y1="${round(state.centerY, 3)}" x2="${round(redStart.x, 3)}" y2="${round(redStart.y, 3)}" stroke="#111111" stroke-width="${state.needleWidthMm > 0 ? round(state.needleWidthMm, 3) : HAIRLINE_STROKE_MM}" stroke-linecap="round" />
      <line x1="${round(redStart.x, 3)}" y1="${round(redStart.y, 3)}" x2="${round(end.x, 3)}" y2="${round(end.y, 3)}" stroke="#c62020" stroke-width="${state.needleWidthMm > 0 ? round(state.needleWidthMm, 3) : HAIRLINE_STROKE_MM}" stroke-linecap="round" />
      <line x1="${round(state.centerX, 3)}" y1="${round(state.centerY, 3)}" x2="${round(end.x, 3)}" y2="${round(end.y, 3)}" stroke="transparent" stroke-width="${round(Math.max(state.needleWidthMm * 7, 2.4), 3)}" stroke-linecap="round" data-role="needle-hit" />
      <circle cx="${round(state.centerX, 3)}" cy="${round(state.centerY, 3)}" r="0.85" fill="#111111" />
    `;
  })() : "";

  const snapGuides = previewMode && dragState ? `
    ${dragState.guideX != null ? `<line x1="${round(dragState.guideX, 3)}" y1="0" x2="${round(dragState.guideX, 3)}" y2="${round(state.heightMm, 3)}" stroke="#c62020" stroke-width="0.12" stroke-dasharray="0.5 0.35" opacity="0.6" />` : ""}
    ${dragState.guideY != null ? `<line x1="0" y1="${round(dragState.guideY, 3)}" x2="${round(state.widthMm, 3)}" y2="${round(dragState.guideY, 3)}" stroke="#c62020" stroke-width="0.12" stroke-dasharray="0.5 0.35" opacity="0.6" />` : ""}
  ` : "";

  return `
    ${outerFrame}
    ${guideArc}
    ${minorTicks}
    ${endpointTicks}
    ${majorTicks}
    ${snapGuides}
    ${majorTickLabels}
    ${freeTexts}
    ${previewNeedle}
  `;
}

function buildSvgString(includeNeedle = false) {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${round(state.widthMm, 3)}mm" height="${round(state.heightMm, 3)}mm" viewBox="0 0 ${round(state.widthMm, 3)} ${round(state.heightMm, 3)}">${buildGaugeMarkup({ includeNeedle, previewMode: false, outlineText: false })}</svg>`;
}

function buildOutlinedSvgString(includeNeedle = false) {
  if (!window.opentype) {
    return buildSvgString(includeNeedle);
  }
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${round(state.widthMm, 3)}mm" height="${round(state.heightMm, 3)}mm" viewBox="0 0 ${round(state.widthMm, 3)} ${round(state.heightMm, 3)}">${buildGaugeMarkup({ includeNeedle, previewMode: false, outlineText: true })}</svg>`;
}

function syncFields() {
  const activeElement = document.activeElement;
  Object.entries(fields).forEach(([key, element]) => {
    if (!element || element === activeElement) {
      return;
    }
    if (element.type === "checkbox") {
      element.checked = Boolean(state[key]);
      return;
    }
    element.value = round(state[key], 2);
  });
}

function syncInlineEditor() {
  const item = getSelectedItem();
  inlineEditor.classList.toggle("hidden", !editorOpen || !item);
  if (!editorOpen || !item || !selection) {
    return;
  }

  const activeElement = document.activeElement;
  const isMajorTick = selection.type === "majorTick";
  inlineEditorTitle.textContent = isMajorTick ? "刻度属性" : "文字属性";
  tickEditorFields.classList.toggle("hidden", !isMajorTick);
  freeTextEditorFields.classList.toggle("hidden", isMajorTick);

  if (isMajorTick) {
    if (tickFields.valueText !== activeElement) {
      tickFields.valueText.value = item.valueText;
    }
    if (tickFields.showValue !== activeElement) {
      tickFields.showValue.checked = Boolean(item.showValue);
    }
    if (tickFields.unitText !== activeElement) {
      tickFields.unitText.value = item.unitText;
    }
    if (tickFields.showUnit !== activeElement) {
      tickFields.showUnit.checked = Boolean(item.showUnit);
    }
    if (tickFields.percent !== activeElement) {
      tickFields.percent.value = round(item.percent, 0);
    }
    if (tickFields.subdivisions !== activeElement) {
      tickFields.subdivisions.value = round(item.subdivisions, 0);
    }
    if (tickFields.fontSizeMm !== activeElement) {
      tickFields.fontSizeMm.value = round(item.fontSizeMm, 2);
    }
    if (tickFields.fontFamily !== activeElement) {
      tickFields.fontFamily.value = item.fontFamily || DEFAULT_FONT_FAMILY;
    }
    deleteInlineItemButton.textContent = "删除刻度";
  } else {
    if (freeTextFields.text !== activeElement) {
      freeTextFields.text.value = item.text;
    }
    if (freeTextFields.fontSizeMm !== activeElement) {
      freeTextFields.fontSizeMm.value = round(item.fontSizeMm, 2);
    }
    if (freeTextFields.fontFamily !== activeElement) {
      freeTextFields.fontFamily.value = item.fontFamily || DEFAULT_FONT_FAMILY;
    }
    deleteInlineItemButton.textContent = "删除文字";
  }
}

function renderPreview() {
  previewSvg.setAttribute("viewBox", `0 0 ${round(state.widthMm, 3)} ${round(state.heightMm, 3)}`);
  previewSvg.setAttribute("width", `${round(state.widthMm, 3)}mm`);
  previewSvg.setAttribute("height", `${round(state.heightMm, 3)}mm`);
  previewSvg.innerHTML = buildGaugeMarkup({ includeNeedle: true, previewMode: true, outlineText: true });
}

function renderMetrics() {
  speedMetric.textContent = formatSpeed(speedFromPercent(state.previewPercent));
}

function renderAll(options = {}) {
  const { skipFields = false } = options;
  if (!skipFields) {
    syncFields();
  }
  renderSnapToggle();
  syncInlineEditor();
  renderPreview();
  renderMetrics();
  syncHistoryButtons();
}

function updateNumericField(key, value) {
  const numericValue = Number(value);
  if (!Number.isFinite(numericValue)) {
    return;
  }
  if (key === "widthMm" || key === "heightMm") {
    state[key] = Math.max(1, numericValue);
    return;
  }
  if (key === "arcRadiusMm" || key === "needleLengthMm") {
    state[key] = Math.max(0.1, numericValue);
    return;
  }
  if (
    key === "arcStrokeWidthMm" ||
    key === "majorTickLengthMm" ||
    key === "minorTickLengthMm" ||
    key === "majorTickWidthMm" ||
    key === "minorTickWidthMm" ||
    key === "needleWidthMm"
  ) {
    state[key] = Math.max(0, numericValue);
    return;
  }
  state[key] = numericValue;
}

function openInlineEditor(nextSelection) {
  selection = resolveSelection(nextSelection);
  editorOpen = Boolean(selection);
  syncInlineEditor();
}

function closeInlineEditor() {
  editorOpen = false;
  syncInlineEditor();
}

function closeAddMenu() {
  addMenu.classList.add("hidden");
}

function toggleAddMenu() {
  addMenu.classList.toggle("hidden");
}

function clientPointToSvg(event) {
  const point = previewSvg.createSVGPoint();
  point.x = event.clientX;
  point.y = event.clientY;
  return point.matrixTransform(previewSvg.getScreenCTM().inverse());
}

function getSnapTargets(active) {
  const x = [state.centerX];
  const y = [state.centerY];

  state.majorTicks.forEach((tick) => {
    const tickLine = lineForTick(tick.percent, state.majorTickLengthMm);
    x.push(tickLine.inner.x, tickLine.outer.x);
    y.push(tickLine.inner.y, tickLine.outer.y);

    if (!(active?.type === "majorTick" && active.id === tick.id)) {
      const anchor = getMajorTickLabelAnchor(tick);
      const pos = getMajorTickLabelPosition(tick);
      x.push(anchor.x, pos.x);
      y.push(anchor.y, pos.y);
    }
  });

  state.freeTexts.forEach((item) => {
    if (active?.type === "freeText" && active.id === item.id) {
      return;
    }
    const pos = getFreeTextPosition(item);
    x.push(pos.x);
    y.push(pos.y);
  });

  return { x, y };
}

function buildSettingsExport() {
  return {
    version: 1,
    exportedAt: new Date().toISOString(),
    state: structuredClone(state)
  };
}

function applyImportedSettings(payload) {
  const importedState = payload && typeof payload === "object" && payload.state ? payload.state : payload;
  if (!importedState || typeof importedState !== "object") {
    throw new Error("missing-state");
  }
  state = normalizeState(importedState);
  selection = state.majorTicks[0]
    ? { type: "majorTick", id: state.majorTicks[0].id }
    : (state.freeTexts[0] ? { type: "freeText", id: state.freeTexts[0].id } : null);
  editorOpen = false;
  dragState = null;
  closeAddMenu();
}

function snapCoordinate(value, targets, threshold = 0.55) {
  let snapped = value;
  let guide = null;
  let bestDistance = threshold;

  targets.forEach((target) => {
    const distance = Math.abs(target - value);
    if (distance <= bestDistance) {
      bestDistance = distance;
      snapped = target;
      guide = target;
    }
  });

  return { value: snapped, guide };
}

Object.entries(fields).forEach(([key, input]) => {
  input.addEventListener("input", (event) => {
    if (event.target.type === "checkbox") {
      state[key] = event.target.checked;
      renderAll();
      commitHistory();
      return;
    }
    updateNumericField(key, event.target.value);
    renderAll();
    commitHistory();
  });
});

snapToggleButton.addEventListener("click", () => {
  state.snapEnabled = !state.snapEnabled;
  renderAll({ skipFields: true });
  commitHistory();
});

addMenuToggleButton.addEventListener("click", (event) => {
  event.stopPropagation();
  toggleAddMenu();
});

document.addEventListener("pointerdown", (event) => {
  if (!addMenu.contains(event.target) && event.target !== addMenuToggleButton && !addMenuToggleButton.contains(event.target)) {
    closeAddMenu();
  }
});

addMajorTickButton.addEventListener("click", () => {
  const newTick = createMajorTick({
    valueText: "新刻度",
    unitText: "M",
    showUnit: true,
    percent: 100,
    subdivisions: 10,
    fontFamily: getPreferredFontFamily()
  });
  state.majorTicks = [...state.majorTicks, newTick];
  sortMajorTicks();
  openInlineEditor({ type: "majorTick", id: newTick.id });
  closeAddMenu();
  renderAll();
  commitHistory();
});

addFreeTextButton.addEventListener("click", () => {
  const newText = createFreeText({
    xMm: state.widthMm / 2,
    yMm: state.heightMm / 2,
    fontFamily: getPreferredFontFamily()
  });
  state.freeTexts = [...state.freeTexts, newText];
  openInlineEditor({ type: "freeText", id: newText.id });
  closeAddMenu();
  renderAll();
  commitHistory();
});

tickFields.valueText.addEventListener("input", (event) => {
  const tick = selection?.type === "majorTick" ? getSelectedItem() : null;
  if (!tick) {
    return;
  }
  tick.valueText = event.target.value;
  renderAll({ skipFields: true });
  commitHistory();
});

tickFields.showValue.addEventListener("input", (event) => {
  const tick = selection?.type === "majorTick" ? getSelectedItem() : null;
  if (!tick) {
    return;
  }
  tick.showValue = event.target.checked;
  renderAll({ skipFields: true });
  commitHistory();
});

tickFields.unitText.addEventListener("input", (event) => {
  const tick = selection?.type === "majorTick" ? getSelectedItem() : null;
  if (!tick) {
    return;
  }
  tick.unitText = event.target.value;
  renderAll({ skipFields: true });
  commitHistory();
});

tickFields.showUnit.addEventListener("input", (event) => {
  const tick = selection?.type === "majorTick" ? getSelectedItem() : null;
  if (!tick) {
    return;
  }
  tick.showUnit = event.target.checked;
  renderAll({ skipFields: true });
  commitHistory();
});

tickFields.percent.addEventListener("input", (event) => {
  if (selection?.type !== "majorTick") {
    return;
  }
  const tick = getSelectedItem();
  const numericValue = Number(event.target.value);
  if (!tick || !Number.isFinite(numericValue)) {
    return;
  }
  tick.percent = clamp(Math.round(numericValue), 0, 100);
  sortMajorTicks();
  renderAll({ skipFields: true });
  commitHistory();
});

tickFields.subdivisions.addEventListener("input", (event) => {
  const tick = selection?.type === "majorTick" ? getSelectedItem() : null;
  const numericValue = Number(event.target.value);
  if (!tick || !Number.isFinite(numericValue)) {
    return;
  }
  tick.subdivisions = Math.max(1, Math.round(numericValue));
  renderAll({ skipFields: true });
  commitHistory();
});

tickFields.fontSizeMm.addEventListener("input", (event) => {
  const tick = selection?.type === "majorTick" ? getSelectedItem() : null;
  const numericValue = Number(event.target.value);
  if (!tick || !Number.isFinite(numericValue)) {
    return;
  }
  tick.fontSizeMm = Math.max(0.1, numericValue);
  if (tickFields.syncFontSize.checked) {
    state.majorTicks = state.majorTicks.map((item) => ({ ...item, fontSizeMm: tick.fontSizeMm }));
  }
  renderAll({ skipFields: true });
  commitHistory();
});

tickFields.fontFamily.addEventListener("input", (event) => {
  const tick = selection?.type === "majorTick" ? getSelectedItem() : null;
  if (!tick) {
    return;
  }
  tick.fontFamily = event.target.value;
  if (tickFields.syncFontFamily.checked) {
    state.majorTicks = state.majorTicks.map((item) => ({ ...item, fontFamily: tick.fontFamily }));
  }
  renderAll({ skipFields: true });
  commitHistory();
});

tickFields.syncFontSize.addEventListener("input", (event) => {
  const tick = selection?.type === "majorTick" ? getSelectedItem() : null;
  if (!tick || !event.target.checked) {
    return;
  }
  state.majorTicks = state.majorTicks.map((item) => ({ ...item, fontSizeMm: tick.fontSizeMm }));
  renderAll({ skipFields: true });
  commitHistory();
});

tickFields.syncFontFamily.addEventListener("input", (event) => {
  const tick = selection?.type === "majorTick" ? getSelectedItem() : null;
  if (!tick || !event.target.checked) {
    return;
  }
  state.majorTicks = state.majorTicks.map((item) => ({ ...item, fontFamily: tick.fontFamily }));
  renderAll({ skipFields: true });
  commitHistory();
});

freeTextFields.text.addEventListener("input", (event) => {
  const item = selection?.type === "freeText" ? getSelectedItem() : null;
  if (!item) {
    return;
  }
  item.text = event.target.value;
  renderAll({ skipFields: true });
  commitHistory();
});

freeTextFields.fontSizeMm.addEventListener("input", (event) => {
  const item = selection?.type === "freeText" ? getSelectedItem() : null;
  const numericValue = Number(event.target.value);
  if (!item || !Number.isFinite(numericValue)) {
    return;
  }
  item.fontSizeMm = Math.max(0.1, numericValue);
  renderAll({ skipFields: true });
  commitHistory();
});

freeTextFields.fontFamily.addEventListener("input", (event) => {
  const item = selection?.type === "freeText" ? getSelectedItem() : null;
  if (!item) {
    return;
  }
  item.fontFamily = event.target.value;
  renderAll({ skipFields: true });
  commitHistory();
});

deleteInlineItemButton.addEventListener("click", () => {
  if (!selection) {
    return;
  }
  if (selection.type === "majorTick") {
    state.majorTicks = state.majorTicks.filter((item) => item.id !== selection.id);
  } else {
    state.freeTexts = state.freeTexts.filter((item) => item.id !== selection.id);
  }
  selection = resolveSelection(selection);
  editorOpen = Boolean(selection);
  renderAll();
  commitHistory();
});

document.getElementById("close-inline-editor").addEventListener("click", closeInlineEditor);

document.getElementById("reset-defaults").addEventListener("click", () => {
  state = createDefaultState();
  selection = state.majorTicks[0] ? { type: "majorTick", id: state.majorTicks[0].id } : null;
  editorOpen = false;
  dragState = null;
  closeAddMenu();
  renderAll();
  commitHistory();
});

undoButton.addEventListener("click", () => {
  if (historyState.index <= 0) {
    return;
  }
  historyState.index -= 1;
  restoreSnapshot(historyState.entries[historyState.index].snapshot);
});

redoButton.addEventListener("click", () => {
  if (historyState.index >= historyState.entries.length - 1) {
    return;
  }
  historyState.index += 1;
  restoreSnapshot(historyState.entries[historyState.index].snapshot);
});

document.getElementById("download-svg").addEventListener("click", () => {
  const blob = new Blob([buildOutlinedSvgString(false)], { type: "image/svg+xml;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = "network-gauge.svg";
  link.click();
  URL.revokeObjectURL(url);
});

exportSettingsButton.addEventListener("click", () => {
  const validation = validateTickValueOrder();
  if (!validation.ok) {
    alert(validation.message);
    return;
  }
  const blob = new Blob([JSON.stringify(buildSettingsExport(), null, 2)], { type: "application/json;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = "network-gauge-settings.json";
  link.click();
  URL.revokeObjectURL(url);
});

downloadPngButton.addEventListener("click", async () => {
  const svgString = buildOutlinedSvgString(false);
  const blob = new Blob([svgString], { type: "image/svg+xml;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const image = new Image();
  const scale = 12;
  const canvas = document.createElement("canvas");
  canvas.width = Math.max(1, Math.round(state.widthMm * scale));
  canvas.height = Math.max(1, Math.round(state.heightMm * scale));
  const context = canvas.getContext("2d");
  if (!context) {
    URL.revokeObjectURL(url);
    return;
  }

  await new Promise((resolve, reject) => {
    image.onload = resolve;
    image.onerror = reject;
    image.src = url;
  }).catch((error) => {
    console.error("PNG export failed", error);
  });

  if (!image.complete) {
    URL.revokeObjectURL(url);
    return;
  }

  context.clearRect(0, 0, canvas.width, canvas.height);
  context.drawImage(image, 0, 0, canvas.width, canvas.height);
  URL.revokeObjectURL(url);
  canvas.toBlob((pngBlob) => {
    if (!pngBlob) {
      return;
    }
    const pngUrl = URL.createObjectURL(pngBlob);
    const link = document.createElement("a");
    link.href = pngUrl;
    link.download = "network-gauge.png";
    link.click();
    URL.revokeObjectURL(pngUrl);
  }, "image/png");
});

importSettingsButton.addEventListener("click", () => {
  importSettingsFileInput.value = "";
  importSettingsFileInput.click();
});

importSettingsFileInput.addEventListener("change", async (event) => {
  const file = event.target.files?.[0];
  if (!file) {
    return;
  }
  try {
    const payload = JSON.parse(await file.text());
    applyImportedSettings(payload);
    renderAll();
    commitHistory();
  } catch (error) {
    console.error("Settings import failed", error);
    alert("导入失败，请检查 JSON 文件格式。");
  }
});

previewSvg.addEventListener("pointerdown", (event) => {
  const needleTarget = event.target.closest("[data-role='needle-hit']");
  if (needleTarget) {
    dragState = { type: "needle", pointerId: event.pointerId };
    previewSvg.setPointerCapture(event.pointerId);
    return;
  }

  const labelTarget = event.target.closest("[data-major-tick-label-id]");
  if (labelTarget) {
    const tick = findMajorTick(labelTarget.dataset.majorTickLabelId);
    if (!tick) {
      return;
    }
    selection = { type: "majorTick", id: tick.id };
    const point = clientPointToSvg(event);
    const anchor = getMajorTickLabelAnchor(tick);
    dragState = {
      type: "tickLabel",
      id: tick.id,
      pointerId: event.pointerId,
      offsetX: point.x - (anchor.x + tick.dxMm),
      offsetY: point.y - (anchor.y + tick.dyMm),
      moved: false
    };
    previewSvg.setPointerCapture(event.pointerId);
    return;
  }

  const freeTextTarget = event.target.closest("[data-free-text-id]");
  if (freeTextTarget) {
    const item = findFreeText(freeTextTarget.dataset.freeTextId);
    if (!item) {
      return;
    }
    selection = { type: "freeText", id: item.id };
    const point = clientPointToSvg(event);
    dragState = {
      type: "freeText",
      id: item.id,
      pointerId: event.pointerId,
      offsetX: point.x - item.xMm,
      offsetY: point.y - item.yMm,
      moved: false
    };
    previewSvg.setPointerCapture(event.pointerId);
    return;
  }

  const majorTickTarget = event.target.closest("[data-major-tick-id]");
  if (majorTickTarget) {
    const tick = findMajorTick(majorTickTarget.dataset.majorTickId);
    if (!tick) {
      return;
    }
    selection = { type: "majorTick", id: tick.id };
    dragState = {
      type: "majorTick",
      id: tick.id,
      pointerId: event.pointerId,
      moved: false
    };
    previewSvg.setPointerCapture(event.pointerId);
  }
});

previewSvg.addEventListener("pointermove", (event) => {
  if (!dragState || event.pointerId !== dragState.pointerId) {
    return;
  }

  if (dragState.type === "needle") {
    const point = clientPointToSvg(event);
    const angle = angleFromPoint(point.x, point.y);
    const rawPercent = ((angle - state.arcStartDeg) / (state.arcEndDeg - state.arcStartDeg || 1)) * 100;
    state.previewPercent = clamp(rawPercent, 0, 100);
    renderAll({ skipFields: true });
    return;
  }

  if (dragState.type === "majorTick") {
    const tick = findMajorTick(dragState.id);
    if (!tick) {
      return;
    }
    const point = clientPointToSvg(event);
    const angle = angleFromPoint(point.x, point.y);
    const rawPercent = ((angle - state.arcStartDeg) / (state.arcEndDeg - state.arcStartDeg || 1)) * 100;
    tick.percent = clamp(Math.round(rawPercent), 0, 100);
    sortMajorTicks();
    dragState.moved = true;
    renderAll({ skipFields: true });
    return;
  }

  if (dragState.type === "tickLabel") {
    const tick = findMajorTick(dragState.id);
    if (!tick) {
      return;
    }
    const point = clientPointToSvg(event);
    const anchor = getMajorTickLabelAnchor(tick);
    const intendedX = point.x - dragState.offsetX;
    const intendedY = point.y - dragState.offsetY;
    const targets = state.snapEnabled ? getSnapTargets({ type: "majorTick", id: tick.id }) : { x: [], y: [] };
    const snappedX = state.snapEnabled ? snapCoordinate(intendedX, targets.x) : { value: intendedX, guide: null };
    const snappedY = state.snapEnabled ? snapCoordinate(intendedY, targets.y) : { value: intendedY, guide: null };
    dragState.moved = true;
    tick.dxMm = round(snappedX.value - anchor.x, 2);
    tick.dyMm = round(snappedY.value - anchor.y, 2);
    dragState.guideX = snappedX.guide;
    dragState.guideY = snappedY.guide;
    renderAll({ skipFields: true });
    return;
  }

  const item = findFreeText(dragState.id);
  if (!item) {
    return;
  }
  const point = clientPointToSvg(event);
  const intendedX = point.x - dragState.offsetX;
  const intendedY = point.y - dragState.offsetY;
  const targets = state.snapEnabled ? getSnapTargets({ type: "freeText", id: item.id }) : { x: [], y: [] };
  const snappedX = state.snapEnabled ? snapCoordinate(intendedX, targets.x) : { value: intendedX, guide: null };
  const snappedY = state.snapEnabled ? snapCoordinate(intendedY, targets.y) : { value: intendedY, guide: null };
  dragState.moved = true;
  item.xMm = round(snappedX.value, 2);
  item.yMm = round(snappedY.value, 2);
  dragState.guideX = snappedX.guide;
  dragState.guideY = snappedY.guide;
  renderAll({ skipFields: true });
});

function endDrag(event) {
  if (!dragState || event.pointerId !== dragState.pointerId) {
    return;
  }
  try {
    previewSvg.releasePointerCapture(event.pointerId);
  } catch (error) {
    // Ignore release failures when capture is already cleared.
  }

  if (!dragState.moved) {
    if (dragState.type === "majorTick" || dragState.type === "tickLabel") {
      openInlineEditor({ type: "majorTick", id: dragState.id });
    } else if (dragState.type === "freeText") {
      openInlineEditor({ type: "freeText", id: dragState.id });
    }
    dragState = null;
    renderAll({ skipFields: true });
    return;
  }

  const shouldCommit = dragState.type === "needle" || dragState.moved;
  dragState = null;
  renderAll();
  if (shouldCommit) {
    commitHistory();
  }
}

previewSvg.addEventListener("pointerup", endDrag);
previewSvg.addEventListener("pointercancel", endDrag);

async function initializeApp() {
  rebuildFontSelectOptions();
  renderAll();
  commitHistory();
  await loadCustomFontsFromFolder();
  renderAll({ skipFields: true });
}

initializeApp();
