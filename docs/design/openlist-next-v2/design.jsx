
class Component extends DCLogic {
  constructor(props) {
    super(props);
    this.timers = {}; this.seq = 0; this.capEl = null; this.palEl = null; this.searchEl = null; this.gKey = 0; this.rowIds = [];
    const H = 3600e3, D = 24 * H, now = Date.now();
    const t = (id, list, text, o = {}) => ({ id, list, text, due: null, labels: [], created: now - (o.age || 5) * D, ...o });
    this.state = {
      route: "today", prev: [], screenFlip: false,
      lists: [
        { id: "inbox", emoji: "📥", name: "Inbox", color: "#3A7BD8", section: null },
        { id: "kyoto", emoji: "🗻", name: "Weekend in Kyoto", color: "#7C4DF0", section: "Personal", kind: "personal" },
        { id: "home", emoji: "🏡", name: "Home", color: "#2F9E6E", section: "Personal", kind: "personal" },
        { id: "reading", emoji: "📚", name: "Reading", color: "#C2532B", section: "Personal", kind: "personal" },
        { id: "q3", emoji: "💼", name: "Q3 planning", color: "#2F6FE0", section: "Work", kind: "work" },
        { id: "hiring", emoji: "🎯", name: "Hiring loop", color: "#B8479A", section: "Work", kind: "work" },
      ],
      tasks: [
        t("i1", "inbox", "Call the dentist back about the crown", { age: 1 }),
        t("i2", "inbox", "Look into a standing desk for the study", { age: 2 }),
        t("i3", "inbox", "Return the library books", { age: 3, due: 2 }),
        t("i4", "inbox", "Gift ideas for Mika’s birthday", { age: 4 }),
        t("i5", "inbox", "Cancel the gym trial before it renews", { age: 0.2, due: 1, prio: "high" }),
        t("i6", "inbox", "Send Jun the photos from Nara", { age: 0.1 }),
        t("k1", "kyoto", "Renew passports", { due: 3, prio: "high", labels: ["travel"] }),
        t("k2", "kyoto", "Pay the ryokan deposit", { due: 0, time: "18:00", est: 15 }),
        t("k3", "kyoto", "Reserve the Nishiki market tour", { due: -2, labels: ["food", "travel"] }),
        t("k4", "kyoto", "Ask Mika to water the planters", { due: 0, repeat: "Every Wednesday" }),
        t("k5", "kyoto", "Pick up JR passes at Kyoto Station", { due: 4, labels: ["travel"] }),
        t("h1", "home", "Fix the dripping bathroom tap", { due: -1 }),
        t("h2", "home", "Order new water filters", { planned: true, est: 10 }),
        t("h3", "home", "Book the boiler service", { due: 6 }),
        t("r1", "reading", "Finish The Overstory", { star: true }),
        t("r2", "reading", "Notes on Working in Public", {}),
        t("q1", "q3", "Draft Q3 OKRs", { due: 0, prio: "high", planned: true, est: 90, labels: ["focus"], note: "Keep it to three objectives. Pull last quarter’s numbers from the board deck." }),
        t("q2", "q3", "Review hiring budget with Sam", { due: 1, est: 45 }),
        t("q3", "q3", "Prep board update slides", { due: 2, est: 60, labels: ["focus"] }),
        t("q4", "q3", "Close out Q2 retro actions", { due: -3, prio: "medium" }),
        t("p1", "hiring", "Write interview feedback for Priya", { due: 0, star: true, est: 20 }),
        t("p2", "hiring", "Schedule the onsite for Leo", { due: 3 }),
        t("p3", "hiring", "Update the design role scorecard", { planned: true, est: 30 }),
        t("d1", "kyoto", "Reply to Kasuga about the tatami room", { done: true, doneAt: now - 2.2 * H }),
        t("d2", "q3", "Standup notes", { done: true, doneAt: now - 0.9 * H }),
        t("x1", "kyoto", "Old packing list draft", { trashed: true, trashedAt: now - D }),
        t("x2", "home", "Try the new ramen place", { trashed: true, trashedAt: now - 3 * D }),
        t("x3", "q3", "Prep board update slides (duplicate)", { trashed: true, trashedAt: now - 3 * H }),
      ],
      placements: [
        { id: "d2", day: 2, start: 10.25, dur: 15 }, { id: "q4", day: 1, start: 14, dur: 30 },
        { id: "q1", day: 2, start: 10, dur: 90 }, { id: "p1", day: 2, start: 11.5, dur: 20 },
        { id: "p3", day: 2, start: 13, dur: 30 }, { id: "h2", day: 2, start: 16.5, dur: 10 },
        { id: "k2", day: 2, start: 18, dur: 15 }, { id: "q2", day: 3, start: 13, dur: 45 }, { id: "q3", day: 4, start: 10, dur: 60 },
      ],
      closing: {}, flying: {}, selected: {}, focusId: null, inspectId: null,
      undo: [], log: [], tray: null, capture: null, palette: null, search: null,
      kept: {}, triage: { exit: null, flip: false }, reviewed: 0,
      tf: { status: "open", group: "list", lists: {}, q: "", tq: "" }, tfMenu: null, tqFocus: false, calRange: 7, actDay: null, hold: null, working: null,
      completedOpen: false, moreOpen: false, collapsed: {}, pulseList: null, pulseId: null, freshBlock: null,
      settings: { showCompleted: false, reduce: false, quickAdd: true },
      now, blocks: [], edit: null, slash: null,
    };
    const seedOrder = { k1: 10, k7: 20, k8: 21, k9: 22, k2: 23, d1: 24, k3: 40, k4: 41, k5: 42, q1: 10, q2: 20, q3: 30, q4: 40 };
    const seedDepth = { k8: 1, k9: 1, k2: 1 };
    const extraTasks = [
      { id: "k7", list: "kyoto", text: "Book the ryokan", due: null, labels: ["travel"], star: true, created: now - 6 * D, noteOpen: true, note: "Kasuga replies in about a day. If the tatami room is gone, the annex is fine — ask for the garden side." },
      { id: "k8", list: "kyoto", text: "Compare Gion vs Arashiyama", due: null, labels: [], created: now - 6 * D, done: true, doneAt: now - 26 * H },
      { id: "k9", list: "kyoto", text: "Email Kasuga about the tatami room", due: null, labels: [], created: now - 6 * D },
    ];
    this.state.tasks = [...this.state.tasks, ...extraTasks].map((x, i) => ({ ...x, order: seedOrder[x.id] ?? 100 + i * 10, depth: seedDepth[x.id] || 0 }));
    this.state.blocks = [
      { id: "b1", list: "kyoto", kind: "h1", text: "Before we go", order: 0 },
      { id: "b3", list: "kyoto", kind: "h1", text: "On the ground", order: 30 },
      { id: "b4", list: "kyoto", kind: "bullet", text: "The JR pass covers the Nara day trip", order: 31 },
      { id: "b5", list: "kyoto", kind: "bullet", text: "Nishiki is closed most Wednesdays — go on Thursday", order: 32 },
      { id: "b6", list: "q3", kind: "h2", text: "This week", order: 0 },
      { id: "b7", list: "q3", kind: "h2", text: "Carried over", order: 35 },
    ];
  }

  static DAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
  static WDAYS = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
  static MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
  static MONTHS_L = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];
  static LABELS = [{ id: "travel", color: "#12807F" }, { id: "food", color: "#C2532B" }, { id: "focus", color: "#7C4DF0" }];
  static EVENTS = [
    [[9.5, 10, "Standup"], [13, 14, "Design review"]],
    [[9.5, 10, "Standup"], [11, 12, "1:1 with Sam"], [15, 16.5, "Hiring sync"]],
    [[9.5, 10, "Standup"], [14, 15, "Board prep"], [15.5, 16, "Priya debrief"], [16, 16.5, "Coffee with Leo"]],
    [[9.5, 10, "Standup"], [10, 12, "Offsite planning"]],
    [[9.5, 10, "Standup"], [12, 13, "Team lunch"]],
    [[10, 11.5, "Pottery class"]],
    [],
  ];
  static NOW_H = 10 + 40 / 60;
  static POOL = [["Book flights to Osaka", "🗻"], ["Pay council tax", "🏡"], ["Send offer letter to Ana", "🎯"], ["Review roadmap draft", "💼"], ["Buy descaler", "🏡"], ["Finish chapter 12", "📚"], ["Confirm rail passes", "🗻"], ["1:1 prep with Sam", "💼"], ["Portfolio review notes", "🎯"], ["Water the planters", "🗻"], ["Renew car insurance", "🏡"], ["Write retro summary", "💼"]];
  static PATTERNS = [
    { kind: "repeat", re: /\bevery\s(?:day|weekday|week|month|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b/i },
    { kind: "date", re: /\b(?:today|tonight|tomorrow|tmrw|next\sweek|(?:next\s)?(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)|in\s\d+\s(?:days?|weeks?))\b/i },
    { kind: "time", re: /\b(?:at\s)?\d{1,2}(?::\d{2})?\s?(?:am|pm)\b/i },
    { kind: "label", re: /#[a-z0-9_-]+/i },
    { kind: "priority", re: /!(?:high|med|medium|low|[1-3])\b/i },
    { kind: "est", re: /~\d+\s?(?:m|min|h)\b/i },
  ];

  ms() { const m = this.props.motion ?? "Expressive"; return this.state.settings.reduce ? 0.4 : m === "Restrained" ? 0.6 : m === "Playful" ? 1.2 : 1; }
  lively() { return (this.props.motion ?? "Expressive") !== "Restrained" && !this.state.settings.reduce; }
  dwell() { return Math.round((this.props.undoDwellSeconds ?? 5) * 1000); }
  A() { return this.props.accent ?? "#7C4DF0"; }
  pad() { return (this.props.density ?? "Comfortable") === "Compact" ? "3px 10px" : "5px 10px"; }

  dateFor(off) { const d = new Date(2026, 8, 23); d.setDate(d.getDate() + off); return d; }
  dueLabel(off) {
    if (off === 0) return "Today"; if (off === 1) return "Tomorrow"; if (off === -1) return "Yesterday";
    const d = this.dateFor(off);
    if (off > 1 && off < 7) return Component.DAYS[d.getDay()] + " " + d.getDate();
    return d.getDate() + " " + Component.MONTHS[d.getMonth()];
  }
  relLabel(off) { if (off === 0) return "today"; if (off === 1) return "tomorrow"; if (off < 0) return Math.abs(off) + " days ago"; return "in " + off + " days"; }
  resolve(raw) {
    const w = raw.toLowerCase().trim(); const dow = 3;
    if (/^(today|tonight)$/.test(w)) return 0; if (/^(tomorrow|tmrw)$/.test(w)) return 1;
    if (w === "next week") return 5;
    let m = w.match(/^in\s(\d+)\s(days?|weeks?)$/); if (m) return +m[1] * (m[2][0] === "w" ? 7 : 1);
    m = w.match(/^(next\s)?(sunday|monday|tuesday|wednesday|thursday|friday|saturday)$/);
    if (m) { const i = Component.WDAYS.map((x) => x.toLowerCase()).indexOf(m[2]); let d = (i - dow + 7) % 7 || 7; if (m[1] && d < 7) d += 7; return d; }
    return null;
  }
  fmtTime(raw) { const m = raw.match(/(\d{1,2})(?::(\d{2}))?\s?(am|pm)/i); if (!m) return null; const h = (+m[1] % 12) + (m[3].toLowerCase() === "pm" ? 12 : 0); return String(h).padStart(2, "0") + ":" + (m[2] || "00"); }
  hm(h) { const hh = Math.floor(h + 1e-6), mm = Math.round((h - hh) * 60); return String(hh).padStart(2, "0") + ":" + String(mm).padStart(2, "0"); }
  clock(ts) { const d = new Date(ts); return String(d.getHours()).padStart(2, "0") + ":" + String(d.getMinutes()).padStart(2, "0"); }
  rel(ts) { const s = (this.state.now - ts) / 1000; if (s < 45) return "just now"; if (s < 3600) return Math.round(s / 60) + " min ago"; if (s < 86400) return Math.round(s / 3600) + " h ago"; const d = Math.round(s / 86400); return d === 1 ? "yesterday" : d + " days ago"; }
  short(t) { return t.length > 30 ? t.slice(0, 29) + "…" : t; }
  parse(text) {
    const marks = [];
    Component.PATTERNS.forEach(({ kind, re }) => {
      const r = new RegExp(re.source, "gi"); let m;
      while ((m = r.exec(text)) !== null) { const st = m.index, en = st + m[0].length; if (marks.some((k) => st < k.end && k.start < en)) continue; marks.push({ kind, start: st, end: en, raw: m[0] }); }
    });
    marks.sort((a, b) => a.start - b.start);
    const segments = []; let i = 0;
    marks.forEach((mk) => { if (mk.start > i) segments.push({ text: text.slice(i, mk.start), kind: null }); segments.push({ text: text.slice(mk.start, mk.end), kind: mk.kind }); i = mk.end; });
    if (i < text.length) segments.push({ text: text.slice(i), kind: null });
    let title = text; [...marks].reverse().forEach((mk) => { title = title.slice(0, mk.start) + title.slice(mk.end); });
    return { segments, marks, title: title.replace(/\s{2,}/g, " ").trim() };
  }

  T(id) { return this.state.tasks.find((x) => x.id === id); }
  L(id) { return this.state.lists.find((l) => l.id === id) || this.state.lists[0]; }
  live(x) { return !x.trashed && !x.done; }
  targets() { const sel = Object.keys(this.state.selected).filter((id) => this.T(id)); if (sel.length) return sel; const f = this.state.focusId || this.state.inspectId; return f && this.T(f) ? [f] : []; }
  describe(ids) { if (ids.length === 1) { const x = this.T(ids[0]); return "“" + this.short(x ? x.text : "") + "”"; } return ids.length + " tasks"; }
  later(key, fn, ms) { clearTimeout(this.timers[key]); this.timers[key] = setTimeout(fn, ms); }
  patch(ids, fn) { this.setState((s) => ({ tasks: s.tasks.map((x) => (ids.includes(x.id) ? { ...x, ...fn(x) } : x)) })); }
  flash(ids, flag, ms) { this.later(flag + ids.join(","), () => this.patch(ids, () => ({ [flag]: false })), ms); }

  snap(label, icon, tone, ids, go, base) {
    const s = this.state; const b = base || s;
    const entry = { label, tasks: b.tasks, blocks: b.blocks, placements: b.placements, kept: b.kept, reviewed: b.reviewed };
    const idx = s.undo.length;
    const logs = ids.map((id) => ({ id: "l" + ++this.seq, taskId: id, label, icon, tone, at: Date.now(), undoIdx: idx }));
    this.setState((st) => ({ undo: [...st.undo, entry], log: [...logs, ...st.log].slice(0, 120) }));
    this.showTray({ text: label, icon, tone, undo: true, go });
  }
  showTray(t) { this.setState((s) => ({ tray: { ...t, flip: !(s.tray && s.tray.flip) } })); this.later("tray", () => this.setState({ tray: null }), this.dwell() + 300); }
  undoLast() {
    const s = this.state; if (!s.undo.length) return;
    const e = s.undo[s.undo.length - 1]; const idx = s.undo.length - 1;
    Object.keys(this.timers).forEach((k) => { if (!["tray", "pulse", "pulseList"].includes(k)) clearTimeout(this.timers[k]); });
    this.setState({ tasks: e.tasks.map((x) => ({ ...x, restored: true, fresh: false })), placements: e.placements, blocks: e.blocks || s.blocks, kept: e.kept, reviewed: e.reviewed, closing: {}, flying: {}, edit: null, slash: null, undo: s.undo.slice(0, -1), log: s.log.filter((l) => l.undoIdx !== idx), triage: { exit: null, flip: !s.triage.flip } });
    this.showTray({ text: "Undid — " + e.label, icon: "undo", tone: "neutral", undo: false });
    this.later("restored", () => this.setState((st) => ({ tasks: st.tasks.map((x) => (x.restored ? { ...x, restored: false } : x)) })), 900);
  }

  complete(ids) {
    ids = [...new Set(ids.flatMap((id) => [id, ...this.subtree(id).filter((y) => !y.isBlock && !y.done).map((y) => y.id)]))];
    const s = this.state; const go = [], rolls = [];
    ids.forEach((id) => { const x = this.T(id); if (!x || x.done || x.trashed || s.closing[id]) return; (x.repeat ? rolls : go).push(x); });
    if (!go.length && !rolls.length) return;
    const n = go.length + rolls.length;
    this.snap(n > 1 ? n + " tasks done" : go.length ? this.describe([go[0].id]) + " done" : "“" + this.short(rolls[0].text) + "” rolls to " + this.dueLabel((rolls[0].due ?? 0) + 7), rolls.length && !go.length ? "repeat" : "check_circle", "green", [...go, ...rolls].map((x) => x.id));
    if (rolls.length) { const r = rolls.map((x) => x.id); this.patch(r, (x) => ({ due: (x.due ?? 0) + 7, freshChip: true })); this.flash(r, "freshChip", 900); }
    const ms = this.ms();
    go.forEach((x, i) => {
      const id = x.id;
      this.later("start-" + id, () => {
        this.setState((st) => ({ closing: { ...st.closing, [id]: { struck: false } } }));
        this.later("strike-" + id, () => this.setState((st) => (st.closing[id] ? { closing: { ...st.closing, [id]: { struck: true } } } : {})), Math.round(130 * ms));
        this.later("settle-" + id, () => this.settle(id), this.dwell() + 300);
      }, Math.round(i * 75 * ms));
    });
    if (s.working && ids.includes(s.working.id)) this.setState({ working: null });
    this.setState({ pulseId: this.lively() ? ids[0] : null, selected: {} });
    this.later("pulse", () => this.setState({ pulseId: null }), 700);
  }
  cancelClose(id) { ["start-", "strike-", "settle-"].forEach((p) => clearTimeout(this.timers[p + id])); this.setState((s) => { const c = { ...s.closing }; delete c[id]; return { closing: c }; }); }
  settle(id) { this.setState((s) => { if (!s.closing[id]) return {}; const c = { ...s.closing }; delete c[id]; return { closing: c, tasks: s.tasks.map((x) => (x.id === id ? { ...x, done: true, doneAt: Date.now() } : x)) }; }); }
  reopen(id) { const x = this.T(id); if (!x) return; this.snap("Reopened “" + this.short(x.text) + "”", "undo", "neutral", [id]); this.patch([id], () => ({ done: false, doneAt: null, restored: true })); this.flash([id], "restored", 900); }
  toggle(id) { const x = this.T(id); if (!x) return; if (this.state.closing[id]) this.cancelClose(id); else if (x.done) this.reopen(id); else this.complete([id]); }
  schedule(ids, off) {
    const t = ids.filter((id) => this.T(id)); if (!t.length) return;
    this.snap(off == null ? "Cleared date on " + this.describe(t) : this.describe(t) + " → " + this.dueLabel(off), "event", "accent", t);
    this.patch(t, () => ({ due: off, freshChip: true })); this.flash(t, "freshChip", 700); this.setState({ selected: {} });
  }
  star(ids) { const t = ids.filter((id) => this.T(id)); if (!t.length) return; const on = !t.every((id) => this.T(id).star); this.snap((on ? "Starred " : "Unstarred ") + this.describe(t), "star", "amber", t); this.patch(t, () => ({ star: on, freshChip: true })); this.flash(t, "freshChip", 700); }
  plan(ids) { const t = ids.filter((id) => this.T(id)); if (!t.length) return; const on = !t.every((id) => this.T(id).planned); this.snap((on ? "Planned for today: " : "Unplanned: ") + this.describe(t), "calendar_clock", "accent", t); this.patch(t, () => ({ planned: on, freshChip: true })); this.flash(t, "freshChip", 700); this.setState({ selected: {} }); }
  setPrio(id, p) { this.snap("Priority " + (p || "none") + " · " + this.describe([id]), "flag", "red", [id]); this.patch([id], () => ({ prio: p })); }
  toggleLabel(id, lab) { const x = this.T(id); const has = (x.labels || []).includes(lab); this.snap((has ? "Removed #" : "Added #") + lab + " · " + this.describe([id]), "sell", "accent", [id]); this.patch([id], (y) => ({ labels: has ? y.labels.filter((l) => l !== lab) : [...(y.labels || []), lab], freshChip: true })); this.flash([id], "freshChip", 700); }
  setEst(id, d) { const x = this.T(id); const v = Math.max(5, Math.min(240, (x.est || 30) + d)); this.patch([id], () => ({ est: v })); }
  move(ids, listId, quiet) {
    const t = ids.filter((id) => this.T(id)); if (!t.length) return; const l = this.L(listId);
    this.snap("Moved " + this.describe(t) + " to " + l.name, "drive_file_move", "accent", t, quiet ? null : { label: "Open " + l.name, route: l.id === "inbox" ? "inbox" : "list:" + l.id });
    this.patch(t, () => ({ list: listId, freshChip: true })); this.flash(t, "freshChip", 700);
    this.setState({ pulseList: listId, selected: {} }); this.later("pulseList", () => this.setState({ pulseList: null }), 1100);
  }
  trash(ids) {
    ids = [...new Set(ids.flatMap((id) => [id, ...this.subtree(id).filter((y) => !y.isBlock).map((y) => y.id)]))];
    const t = ids.filter((id) => this.T(id)); if (!t.length) return;
    this.snap("Moved " + this.describe(t) + " to Trash", "delete", "red", t, { label: "Open Trash", route: "trash" });
    this.setState((s) => { const f = { ...s.flying }; t.forEach((id) => (f[id] = true)); return { flying: f, selected: {}, focusId: null, inspectId: t.includes(s.inspectId) ? null : s.inspectId }; });
    this.later("fly-" + t.join(","), () => this.setState((s) => { const f = { ...s.flying }; t.forEach((id) => delete f[id]); return { flying: f, tasks: s.tasks.map((x) => (t.includes(x.id) ? { ...x, trashed: true, trashedAt: Date.now() } : x)) }; }), Math.round(320 * this.ms()));
  }
  restore(id) {
    const x = this.T(id); const l = this.L(x.list);
    this.snap("Restored “" + this.short(x.text) + "” to " + l.name, "restore_from_trash", "accent", [id], { label: "Open " + l.name, route: l.id === "inbox" ? "inbox" : "list:" + l.id });
    this.setState((s) => ({ flying: { ...s.flying, [id]: true } }));
    this.later("fly-" + id, () => this.setState((s) => { const f = { ...s.flying }; delete f[id]; return { flying: f, tasks: s.tasks.map((y) => (y.id === id ? { ...y, trashed: false, restored: true } : y)) }; }), 300);
  }
  erase(ids) {
    this.setState((s) => ({ tasks: s.tasks.filter((x) => !ids.includes(x.id)), hold: null, undo: s.undo.map((u) => ({ ...u, tasks: u.tasks.filter((x) => !ids.includes(x.id)) })) }));
    this.showTray({ text: ids.length > 1 ? "Erased " + ids.length + " items for good" : "Erased for good", icon: "delete_forever", tone: "red", undo: false });
  }
  holdStart(key, ids) { if (!ids.length) return; this.setState({ hold: { key } }); this.later("hold", () => this.erase(ids), 900); }
  holdEnd() { clearTimeout(this.timers.hold); if (this.state.hold) this.setState({ hold: null }); }
  act(fn) { const t = this.targets(); if (!t.length) return; fn(t); }
  toggleSel(id) { this.setState((s) => { const sel = { ...s.selected }; if (sel[id]) delete sel[id]; else sel[id] = true; return { selected: sel }; }); }
  moveFocus(d, extend) {
    const ids = this.rowIds; if (!ids.length) return;
    const i = ids.indexOf(this.state.focusId);
    const next = ids[i < 0 ? (d > 0 ? 0 : ids.length - 1) : Math.max(0, Math.min(ids.length - 1, i + d))];
    this.setState((s) => ({ focusId: next, inspectId: s.inspectId ? next : null, selected: extend ? { ...s.selected, [next]: true, ...(s.focusId ? { [s.focusId]: true } : {}) } : s.selected }));
  }

  busy(day) {
    const out = Component.EVENTS[day].map((e) => [e[0], e[1]]);
    if (day < 5) out.push([12, 13]);
    this.state.placements.forEach((p) => { if (p.day === day) { const x = this.T(p.id); if (x && !x.trashed) out.push([p.start, p.start + p.dur / 60]); } });
    return out;
  }
  fit(id) {
    const x = this.T(id); if (!x) return; const dur = x.est || 30; const personal = this.L(x.list).kind === "personal";
    for (let day = 2; day < 7; day++) {
      const win = personal ? [18, 21] : day < 5 ? [9, 17] : null; if (!win) continue;
      let st = day === 2 ? Math.max(win[0], Math.ceil(Component.NOW_H * 4) / 4) : win[0];
      const busy = this.busy(day).filter((b) => !(this.state.placements.find((p) => p.id === id && p.day === day && Math.abs(p.start - b[0]) < 1e-6)));
      for (; st + dur / 60 <= win[1] + 1e-6; st += 0.25) {
        const en = st + dur / 60;
        if (!busy.some(([s0, e0]) => st < e0 - 1e-6 && s0 < en - 1e-6)) {
          this.snap("Planned “" + this.short(x.text) + "” · " + (day === 2 ? "Today" : this.dueLabel(day - 2)) + " " + this.hm(st), "auto_awesome", "accent", [id], this.state.route === "calendar" ? null : { label: "Show", route: "calendar" });
          this.setState((s) => ({ placements: [...s.placements.filter((p) => p.id !== id), { id, day, start: st, dur }], freshBlock: id }));
          this.later("freshBlock", () => this.setState({ freshBlock: null }), 1400); return;
        }
      }
    }
    this.showTray({ text: "No free slot this week — try a shorter estimate", icon: "event_busy", tone: "neutral", undo: false });
  }
  startWork(id) { this.setState({ working: { id, start: Date.now(), acc: 0, paused: false, startH: Component.NOW_H }, now: Date.now() }); }
  speed() { return (this.props.workClock ?? "60× demo") === "Real time" ? 1 : 60; }
  elapsed() { const w = this.state.working; if (!w) return 0; return (w.acc + (w.paused ? 0 : Math.max(0, this.state.now - w.start))) * this.speed(); }
  checkOverrun() {
    const s = this.state; const w = s.working; if (!w || w.paused) return;
    const p = s.placements.find((x) => x.id === w.id && x.day === 2); if (!p) return;
    const nowH = w.startH + this.elapsed() / 3600e3; const end = p.start + p.dur / 60;
    if (nowH < end - 1 / 60) return;
    let newEnd = Math.ceil((nowH + 1e-4) * 4) / 4 + 0.25;
    const fixedN = Component.EVENTS[2].concat([[12, 13, "Lunch"]]);
    const next = fixedN.filter((e) => e[0] >= end - 1e-6).sort((a, b) => a[0] - b[0])[0];
    if (next && newEnd > next[0]) newEnd = next[0];
    if (newEnd <= end + 1e-6) {
      if (!p.conflict && next) {
        const c = next[2] + " at " + this.hm(next[0]);
        this.setState((st) => ({ placements: st.placements.map((y) => (y.id === p.id ? { ...y, conflict: c } : y)) }));
        this.showTray({ text: "“" + this.short(this.T(p.id).text) + "” is running into " + c, icon: "event_busy", tone: "red", undo: false, go: s.route === "calendar" ? null : { label: "Show", route: "calendar" } });
      }
      return;
    }
    const newDur = Math.round((newEnd - p.start) * 60);
    const fixed = fixedN.map((e) => [e[0], e[1]]);
    let placements = s.placements.map((x) => (x.id === p.id ? { ...x, dur: newDur, orig: x.orig ?? x.dur } : x));
    const pending = placements.filter((x) => x.day === 2 && x.id !== p.id && x.start >= p.start - 1e-6 && this.T(x.id) && this.live(this.T(x.id))).sort((a, b) => a.start - b.start);
    const movedIds = []; let cursor = newEnd;
    pending.forEach((m, i) => {
      if (m.start >= cursor - 1e-6) { cursor = Math.max(cursor, m.start + m.dur / 60); return; }
      const later = new Set(pending.slice(i + 1).map((x) => x.id));
      const busy = fixed.concat(placements.filter((x) => x.day === 2 && x.id !== m.id && !later.has(x.id)).map((x) => [x.start, x.start + x.dur / 60]));
      for (let st = Math.ceil(cursor * 4 - 1e-6) / 4; st + m.dur / 60 <= 21 + 1e-6; st += 0.25) {
        const en = st + m.dur / 60;
        if (!busy.some(([a, b]) => st < b - 1e-6 && a < en - 1e-6)) { placements = placements.map((x) => (x.id === m.id ? { ...x, start: st, shifted: true } : x)); movedIds.push(m.id); cursor = en; break; }
      }
    });
    const x = this.T(p.id);
    this.snap("Extended “" + this.short(x.text) + "” to " + this.hm(newEnd) + (movedIds.length ? " · moved " + movedIds.length + (movedIds.length === 1 ? " task" : " tasks") : ""), "more_time", "amber", [p.id, ...movedIds], s.route === "calendar" ? null : { label: "Show", route: "calendar" });
    this.setState({ placements });
    this.later("shifted", () => this.setState((st) => ({ placements: st.placements.map((y) => (y.shifted ? { ...y, shifted: false } : y)) })), 1400);
  }

  go(route) {
    const s = this.state; if (route === s.route) return;
    this.setState({ route, prev: [...s.prev, s.route].slice(-20), focusId: null, selected: {}, screenFlip: !s.screenFlip, palette: null, search: null });
  }
  openCapture() { const r = this.state.route; const dest = r.startsWith("list:") ? r.slice(5) : "inbox"; this.setState({ capture: { text: "", dest, today: r === "today" }, palette: null, search: null }); setTimeout(() => this.capEl && this.capEl.focus(), 30); }
  createFromCapture(keepOpen) {
    const c = this.state.capture; if (!c) return; const { marks, title } = this.parse(c.text); if (!title) return;
    const id = "n" + ++this.seq + "_" + Date.now();
    const dm = marks.find((m) => m.kind === "date"), tm = marks.find((m) => m.kind === "time"), rp = marks.find((m) => m.kind === "repeat"), em = marks.find((m) => m.kind === "est");
    const x = { id, list: c.dest, text: title, created: Date.now(), fresh: true,
      due: dm ? this.resolve(dm.raw) : tm || rp || c.today ? 0 : null, time: tm ? this.fmtTime(tm.raw) : null,
      repeat: rp ? rp.raw.replace(/\b[a-z]/g, (k) => k.toUpperCase()) : null,
      labels: marks.filter((m) => m.kind === "label").map((m) => m.raw.slice(1).toLowerCase()),
      prio: marks.some((m) => m.kind === "priority") ? "high" : null,
      est: em ? (/h/i.test(em.raw) ? parseInt(em.raw.slice(1)) * 60 : parseInt(em.raw.slice(1))) : null };
    const l = this.L(c.dest); const r = this.state.route;
    const here = r === "list:" + l.id || (l.id === "inbox" && r === "inbox") || (r === "today" && x.due != null && x.due <= 0) || r === "tasks";
    this.snap("Added to " + l.name, "add_circle", "accent", [id], here ? null : { label: "Show", route: l.id === "inbox" ? "inbox" : "list:" + l.id });
    this.setState((s) => ({ tasks: [...s.tasks, x], capture: keepOpen ? { ...s.capture, text: "" } : null, pulseList: c.dest }));
    this.flash([id], "fresh", 1200); this.later("pulseList", () => this.setState({ pulseList: null }), 1100);
    if (keepOpen) setTimeout(() => this.capEl && this.capEl.focus(), 20);
  }

  queue() { const s = this.state; return s.tasks.filter((x) => x.list === "inbox" && this.live(x) && !s.kept[x.id] && !s.closing[x.id]).sort((a, b) => a.created - b.created); }
  triageLists() { return this.state.lists.filter((l) => l.id !== "inbox").slice(0, 9); }
  triage(kind, arg) {
    const s = this.state; const x = this.queue()[0]; if (!x || s.triage.exit) return;
    const dir = { move: "left", schedule: "up", keep: "right", done: "done", trash: "down" }[kind];
    this.setState({ triage: { exit: dir, flip: s.triage.flip } });
    this.later("triage", () => {
      if (kind === "move") this.move([x.id], arg, false);
      else if (kind === "schedule") { this.snap("“" + this.short(x.text) + "” → " + this.dueLabel(arg) + " · still in Inbox", "event", "accent", [x.id]); this.patch([x.id], () => ({ due: arg })); this.setState((st) => ({ kept: { ...st.kept, [x.id]: true } })); }
      else if (kind === "keep") { this.snap("Kept “" + this.short(x.text) + "” for later", "schedule", "neutral", [x.id]); this.setState((st) => ({ kept: { ...st.kept, [x.id]: true } })); }
      else if (kind === "done") { this.snap(this.describe([x.id]) + " done", "check_circle", "green", [x.id]); this.patch([x.id], () => ({ done: true, doneAt: Date.now() })); }
      else if (kind === "trash") { this.snap("Discarded “" + this.short(x.text) + "”", "delete", "red", [x.id], { label: "Open Trash", route: "trash" }); this.patch([x.id], () => ({ trashed: true, trashedAt: Date.now() })); }
      this.setState((st) => ({ reviewed: st.reviewed + 1, triage: { exit: null, flip: !st.triage.flip } }));
    }, Math.round(230 * this.ms()));
  }

  commands() {
    const t = this.targets(); const has = t.length > 0; const q = ((this.state.palette || {}).q || "").toLowerCase();
    const nav = [["inbox", "inbox", "Go to Inbox", "G I"], ["today", "wb_sunny", "Go to Today", "G T"], ["calendar", "calendar_month", "Go to Calendar", "G C"], ["tasks", "checklist", "Go to Tasks", "G A"], ["lists", "layers", "Go to Lists", "G L"], ["activity", "grid_view", "Go to Activity", "G H"], ["trash", "delete", "Go to Trash", ""], ["settings", "settings", "Open Settings", "⌘,"]];
    const c = [
      { icon: "check_circle", label: "Mark as done", key: "E", needs: 1, tone: "#2F9E6E", run: () => this.act((x) => this.complete(x)) },
      { icon: "today", label: "Due today", key: "T", needs: 1, run: () => this.act((x) => this.schedule(x, 0)) },
      { icon: "wb_twilight", label: "Due tomorrow", key: "M", needs: 1, run: () => this.act((x) => this.schedule(x, 1)) },
      { icon: "calendar_clock", label: "Plan for today", key: "P", needs: 1, run: () => this.act((x) => this.plan(x)) },
      { icon: "auto_awesome", label: "Find a slot in the calendar", key: "", needs: 1, run: () => this.act((x) => x.forEach((id) => this.fit(id))) },
      { icon: "play_arrow", label: "Start working", key: "", needs: 1, run: () => this.act((x) => this.startWork(x[0])) },
      { icon: "star", label: "Star", key: "F", needs: 1, tone: "#A87A06", run: () => this.act((x) => this.star(x)) },
      ...this.state.lists.map((l) => ({ icon: "subdirectory_arrow_right", label: "Move to " + l.name, key: "", needs: 1, run: () => this.act((x) => this.move(x, l.id)) })),
      { icon: "right_panel_open", label: "Open details", key: "↩", needs: 1, run: () => this.setState({ inspectId: t[0] }) },
      { icon: "delete", label: "Move to Trash", key: "D", needs: 1, tone: "#C03A42", run: () => this.act((x) => this.trash(x)) },
      { icon: "add_circle", label: "New task", key: "N", run: () => this.openCapture() },
      { icon: "search", label: "Search", key: "/", run: () => this.openSearch() },
      { icon: "undo", label: "Undo last change", key: "⌘Z", run: () => this.undoLast() },
      ...nav.map(([r, icon, label, key]) => ({ icon, label, key, run: () => this.go(r) })),
      ...this.state.lists.filter((l) => l.id !== "inbox").map((l) => ({ icon: "layers", label: "Open " + l.name, key: "", run: () => this.go("list:" + l.id) })),
    ];
    const f = c.filter((x) => (!x.needs || has) && (!q || x.label.toLowerCase().includes(q)));
    if (q) f.sort((a, b) => a.label.toLowerCase().indexOf(q) - b.label.toLowerCase().indexOf(q));
    return f;
  }
  runCmd(c) { this.setState({ palette: null }); setTimeout(() => c.run(), 20); }
  openPalette() { this.setState({ palette: { q: "", idx: 0 }, search: null, capture: null }); setTimeout(() => this.palEl && this.palEl.focus(), 30); }
  openSearch() { this.setState({ search: { q: "", idx: 0, done: false }, palette: null, capture: null }); setTimeout(() => this.searchEl && this.searchEl.focus(), 30); }
  hits() {
    const s = this.state.search; if (!s || !s.q.trim()) return [];
    const q = s.q.toLowerCase().trim(); const out = [];
    this.state.lists.forEach((l) => { const i = l.name.toLowerCase().indexOf(q); if (i >= 0) out.push({ id: l.id, text: l.name, i, q, sub: "List", icon: "layers", run: () => this.go(l.id === "inbox" ? "inbox" : "list:" + l.id) }); });
    this.state.tasks.forEach((x) => {
      if (x.trashed || (x.done && !s.done)) return;
      const i = x.text.toLowerCase().indexOf(q); const inNote = x.note && x.note.toLowerCase().includes(q);
      if (i < 0 && !inNote) return;
      const l = this.L(x.list);
      out.push({ id: x.id, text: x.text, i, q, icon: x.done ? "check_circle" : "radio_button_unchecked",
        sub: l.emoji + " " + l.name + (x.due != null && !x.done ? " · " + this.dueLabel(x.due) : "") + (x.done ? " · Completed" : "") + (i < 0 ? " · matched in note" : ""),
        run: () => { this.go(x.list === "inbox" ? "inbox" : "list:" + x.list); setTimeout(() => this.setState({ focusId: x.id, inspectId: x.id, search: null }), 10); } });
    });
    return out.slice(0, 12);
  }

  componentDidMount() {
    this.onKey = (e) => {
      const s = this.state; const k = e.key; const lk = k.toLowerCase(); const mod = e.metaKey || e.ctrlKey;
      if (mod && lk === "k") { e.preventDefault(); s.palette ? this.setState({ palette: null }) : this.openPalette(); return; }
      if (s.palette || s.search || s.capture) return;
      const typing = document.activeElement && /input|textarea/i.test(document.activeElement.tagName);
      if (typing) return;
      if (mod && lk === "z") { e.preventDefault(); this.undoLast(); return; }
      if (mod && k === ",") { e.preventDefault(); this.go("settings"); return; }
      if (mod && lk === "a") { e.preventDefault(); const sel = {}; this.rowIds.forEach((id) => (sel[id] = true)); this.setState({ selected: sel }); return; }
      if (mod || e.altKey) return;
      if (Date.now() - this.gKey < 900) {
        const m = { i: "inbox", t: "today", c: "calendar", a: "tasks", l: "lists", h: "activity" };
        this.gKey = 0; if (m[lk]) { e.preventDefault(); this.go(m[lk]); return; }
      }
      if (lk === "g") { this.gKey = Date.now(); return; }
      const q = this.queue();
      if (s.route === "inbox" && !s.focusId && q.length) {
        const tl = this.triageLists();
        if (/^[1-9]$/.test(k) && tl[+k - 1]) { e.preventDefault(); this.triage("move", tl[+k - 1].id); return; }
        const tm = { t: () => this.triage("schedule", 0), m: () => this.triage("schedule", 1), arrowright: () => this.triage("keep"), e: () => this.triage("done"), d: () => this.triage("trash"), enter: () => this.setState({ inspectId: q[0].id }) };
        if (tm[lk]) { e.preventDefault(); tm[lk](); return; }
      }
      const map = {
        n: () => this.openCapture(), "/": () => this.openSearch(),
        j: () => this.moveFocus(1, e.shiftKey), arrowdown: () => this.moveFocus(1, e.shiftKey),
        k: () => this.moveFocus(-1, e.shiftKey), arrowup: () => this.moveFocus(-1, e.shiftKey),
        x: () => s.focusId && this.toggleSel(s.focusId),
        e: () => this.act((t) => this.complete(t)), t: () => this.act((t) => this.schedule(t, 0)), m: () => this.act((t) => this.schedule(t, 1)),
        f: () => this.act((t) => this.star(t)), p: () => this.act((t) => this.plan(t)),
        d: () => this.act((t) => this.trash(t)), backspace: () => this.act((t) => this.trash(t)), delete: () => this.act((t) => this.trash(t)),
        enter: () => s.focusId && this.setState({ inspectId: s.focusId }),
        " ": () => s.focusId && this.toggleNote(s.focusId),
        escape: () => { if (s.inspectId) this.setState({ inspectId: null }); else if (Object.keys(s.selected).length) this.setState({ selected: {} }); else this.setState({ focusId: null }); },
      };
      if (map[lk]) { e.preventDefault(); map[lk](); }
    };
    window.addEventListener("keydown", this.onKey);
    this.lastTick = Date.now();
    this.tick = setInterval(() => { const w = this.state.working; if ((w && !w.paused) || Date.now() - this.lastTick > 20000) { this.lastTick = Date.now(); this.setState({ now: Date.now() }, () => this.checkOverrun()); } }, 1000);
  }
  componentWillUnmount() { window.removeEventListener("keydown", this.onKey); clearInterval(this.tick); Object.values(this.timers).forEach(clearTimeout); }

  chip(label, o = {}) {
    const A = this.A();
    const map = { neutral: ["rgba(23,22,26,0.58)", "rgba(23,22,26,0.06)"], accent: [A, A + "1F"], over: ["#C03A42", "rgba(216,67,75,0.13)"], green: ["#23865B", "rgba(47,158,110,0.14)"], amber: ["#A87A06", "rgba(232,169,23,0.18)"] };
    const [fg, bg] = o.color ? [o.color, o.color + "1F"] : map[o.tone || "neutral"] || map.neutral;
    return {
      label, icon: o.icon || "", hasIcon: !!o.icon, fg, tone: o.tone || (o.color ? "label" : "neutral"),
      iconStyle: "font-size:11px; " + (o.fill ? "font-variation-settings:'FILL' 1,'wght' 600;" : ""),
      style: "display:inline-flex; align-items:center; gap:4px; font:600 11px/1.2 -apple-system,sans-serif; color:" + fg + "; background:" + bg + "; padding:3px 7px; border-radius:6px; white-space:nowrap; transition:color 200ms ease, background 200ms ease;" + (o.fresh ? " animation:chipIn 280ms cubic-bezier(0.2,0.9,0.2,1);" : ""),
    };
  }
  labelColor(id) { const l = Component.LABELS.find((x) => x.id === id); return l ? l.color : "#12807F"; }

  mkRow(x, o = {}) {
    const s = this.state, A = this.A(), ms = this.ms(), dwell = this.dwell();
    const closing = s.closing[x.id]; const fly = s.flying[x.id];
    const filled = x.done || !!closing; const struck = closing ? closing.struck : x.done;
    const focused = s.focusId === x.id || s.inspectId === x.id; const selected = !!s.selected[x.id];
    const prioStroke = { high: "#D8434B", medium: "#E8A917", low: "#3A7BD8" };
    const f = x.fresh || x.freshChip;
    const chips = [];
    if (o.showList && x.list !== o.listId) { const l = this.L(x.list); chips.push(this.chip(l.emoji + " " + l.name, { fresh: x.freshChip })); }
    (x.labels || []).forEach((lab) => chips.push(this.chip(lab, { color: this.labelColor(lab), fresh: f })));
    if (x.repeat) chips.push(this.chip(x.repeat, { icon: "repeat", fresh: f }));
    if (x.time && !x.done) chips.push(this.chip(x.time, { icon: "notifications", fill: true, fresh: f }));
    if (x.planned && !x.done && o.showPlanned !== false) chips.push(this.chip(x.est ? x.est + "m" : "Planned", { icon: "calendar_clock", tone: "accent", fresh: f }));
    if (x.due != null && !x.done) chips.push(this.chip(this.dueLabel(x.due), { icon: x.due < 0 ? "error" : "today", fill: x.due < 0, tone: x.due < 0 ? "over" : x.due === 0 ? "accent" : "neutral", fresh: f }));
    if (x.star) chips.push(this.chip("", { icon: "star", fill: true, tone: "amber", fresh: x.freshChip }));
    if (x.done && x.doneAt) chips.push(this.chip(this.rel(x.doneAt)));
    if (o.quiet) chips.forEach((c) => { const strong = ["over", "accent", "amber"].includes(c.tone); c.style = "display:inline-flex; align-items:center; gap:3px; font:500 11.5px/1.2 -apple-system,sans-serif; white-space:nowrap; color:" + (strong || c.tone === "label" ? c.fg : "rgba(23,22,26,0.42)") + "; transition:color 200ms ease;"; if (c.tone === "label") c.label = "#" + c.label; });
    let bg = "transparent", shadow = "none";
    if (focused) { bg = "#fff"; shadow = "0 4px 16px rgba(40,30,20,0.09), 0 0 0 1px " + A + "40"; }
    else if (selected) { bg = A + "14"; shadow = "0 0 0 1px " + A + "30"; }
    else if (x.fresh) bg = A + "1C";
    else if (x.restored) bg = A + "12";
    const T = Math.round(280 * ms);
    const wrapStyle = [
      "position:relative; display:flex; align-items:flex-start; border-radius:9px; padding:" + this.pad(),
      "background:" + bg, "box-shadow:" + shadow,
      "transition:background 700ms ease, box-shadow 180ms ease, opacity " + T + "ms ease, transform " + T + "ms cubic-bezier(0.4,0,0.2,1)",
      closing ? "opacity:0.62" : "", fly ? "opacity:0; transform:translateX(-56px) scale(0.97)" : "",
      x.fresh ? "animation:rowIn " + Math.round(320 * ms) + "ms cubic-bezier(0.2,0.9,0.2,1)" : "", focused ? "z-index:3" : "",
    ].filter(Boolean).join("; ") + ";";
    return {
      id: x.id, text: x.text, chips, wrapStyle, isSelected: selected,
      hasNote: !!(o.notes && x.note), note: x.note || "",
      indentStyle: "width:0; flex:none;",
      railStyle: closing ? "position:absolute; left:0; top:5px; bottom:5px; width:2.5px; border-radius:2px; background:" + A + "; transform-origin:top center; animation:drainV " + dwell + "ms linear forwards;" : "display:none;",
      boxStyle: "width:16px; height:16px; border-radius:50%; box-sizing:border-box; display:flex; align-items:center; justify-content:center; transition:background " + Math.round(200 * ms) + "ms ease, border-color 160ms ease, transform " + Math.round(240 * ms) + "ms cubic-bezier(0.34,1.56,0.64,1); " +
        (filled ? "background:" + (closing ? A : "#2F9E6E") + "; border:1.5px solid transparent; transform:scale(" + (this.lively() && closing && !closing.struck ? 1.18 : 1) + ");" : "background:transparent; border:1.5px solid " + (prioStroke[x.prio] || "rgba(23,22,26,0.3)") + ";"),
      checkStyle: "font-size:11px; color:#fff; font-variation-settings:'wght' 700; transition:opacity 140ms ease, transform 200ms cubic-bezier(0.34,1.56,0.64,1); opacity:" + (filled ? 1 : 0) + "; transform:scale(" + (filled ? 1 : 0.3) + ");",
      ringStyle: s.pulseId === x.id && closing ? "position:absolute; left:0; top:2px; width:16px; height:16px; border-radius:50%; border:2px solid " + A + "; box-sizing:border-box; animation:ring " + Math.round(640 * ms) + "ms ease-out forwards; pointer-events:none;" : "display:none;",
      textStyle: "font:400 13.8px/1.45 -apple-system,sans-serif; color:" + (x.done && !closing ? "rgba(23,22,26,0.42)" : "#17161A") + "; position:relative; display:inline; padding-right:2px;",
      strikeStyle: "position:absolute; left:0; top:52%; height:1.5px; background:" + (closing ? A : "rgba(23,22,26,0.36)") + "; border-radius:1px; width:" + (struck ? "100%" : "0%") + "; transition:width " + Math.round(340 * ms) + "ms cubic-bezier(0.3,0.8,0.2,1);",
      selMarkStyle: "width:16px; height:16px; border-radius:5px; background:" + A + "; display:inline-flex; align-items:center; justify-content:center; animation:chipIn 180ms ease;",
      openStyle: "font-size:15px; padding:3px; border-radius:6px; cursor:pointer; color:rgba(23,22,26,0.45); transition:opacity 140ms ease; opacity:" + (focused ? 1 : o.quiet ? 0 : 0.22) + ";",
      onToggle: (e) => { e.stopPropagation(); this.toggle(x.id); },
      onClick: (e) => {
        e.stopPropagation();
        if (s.closing[x.id]) { this.cancelClose(x.id); return; }
        if (e.metaKey || e.ctrlKey || e.shiftKey) { this.toggleSel(x.id); return; }
        this.setState((st) => ({ focusId: x.id, selected: {}, inspectId: st.inspectId ? x.id : null }));
      },
      onOpen: (e) => { e.stopPropagation(); this.setState({ focusId: x.id, inspectId: x.id }); },
    };
  }

  // ---------- document editing ----------
  docItems(listId, s = this.state) {
    const bl = s.blocks.filter((b) => b.list === listId).map((b) => ({ ...b, isBlock: true }));
    const tk = s.tasks.filter((x) => x.list === listId && !x.trashed).map((x) => ({ ...x, kind: "task", isBlock: false }));
    return [...bl, ...tk].sort((a, b) => (a.order ?? 1e6) - (b.order ?? 1e6) || (a.created || 0) - (b.created || 0));
  }
  lineOf(id, s = this.state) {
    const t = s.tasks.find((x) => x.id === id); if (t) return { ...t, kind: "task", isBlock: false };
    const b = s.blocks.find((x) => x.id === id); return b ? { ...b, isBlock: true } : null;
  }
  isHead(k) { return k === "h1" || k === "h2"; }
  subtree(id, s = this.state) {
    const ln = this.lineOf(id, s); if (!ln || this.isHead(ln.kind)) return [];
    const items = this.docItems(ln.list, s); const i = items.findIndex((y) => y.id === id); const d = ln.depth || 0; const out = [];
    for (let j = i + 1; j < items.length; j++) { const y = items[j]; if (this.isHead(y.kind) || (y.depth || 0) <= d) break; out.push(y); }
    return out;
  }
  patchLine(st, id, p) { return { tasks: st.tasks.map((x) => (x.id === id ? { ...x, ...p } : x)), blocks: st.blocks.map((x) => (x.id === id ? { ...x, ...p } : x)) }; }
  baseSnap() { const s = this.state; return { tasks: s.tasks, blocks: s.blocks, placements: s.placements, kept: s.kept, reviewed: s.reviewed }; }
  pushUndo(pre, label, id) {
    const s = this.state; const idx = s.undo.length;
    this.setState((st) => ({ undo: [...st.undo, { label, tasks: pre.tasks, blocks: pre.blocks, placements: pre.placements, kept: pre.kept, reviewed: pre.reviewed }], log: [{ id: "l" + ++this.seq, taskId: id, label, icon: "edit", tone: "neutral", at: Date.now(), undoIdx: idx }, ...st.log].slice(0, 120) }));
  }
  convert(st, id, kind) {
    const t = st.tasks.find((x) => x.id === id), b = st.blocks.find((x) => x.id === id);
    const depthFor = (d) => (kind === "bullet" || kind === "task" ? d || 0 : 0);
    if (kind === "task") { if (t) return {}; return { blocks: st.blocks.filter((x) => x.id !== id), tasks: [...st.tasks, { id, list: b.list, text: b.text, order: b.order, depth: depthFor(b.depth), due: null, labels: [], created: Date.now(), morph: true, _new: b._new }] }; }
    if (t) return { tasks: st.tasks.filter((x) => x.id !== id), blocks: [...st.blocks, { id, list: t.list, kind, text: t.text, order: t.order, depth: depthFor(t.depth), morph: true, _new: t._new }] };
    return { blocks: st.blocks.map((x) => (x.id === id ? { ...x, kind, depth: depthFor(x.depth), morph: true } : x)) };
  }
  unmorph(id) { this.later("morph" + id, () => this.setState((st) => this.patchLine(st, id, { morph: false })), 420); }
  startEdit(id, field = "text", caret = null) {
    const ln = this.lineOf(id); if (!ln) return;
    if (!this.preEdit || this.preEdit.id !== id) this.preEdit = { id, isNew: false, ...this.baseSnap() };
    this.focusPending = id + ":" + field; this.caretAt = caret;
    this.setState((st) => ({ edit: { id, field, text: field === "note" ? ln.note || "" : ln.text }, slash: null, focusId: ln.isBlock ? null : id, selected: {}, ...(field === "note" ? this.patchLine(st, id, { noteOpen: true }) : {}) }));
  }
  commitEdit(after) {
    const s = this.state; const e = s.edit; const pre = this.preEdit; this.preEdit = null;
    if (!e) { if (after) after(); return; }
    const ln = this.lineOf(e.id);
    if (!ln) { this.setState({ edit: null, slash: null }, after); return; }
    if (e.field === "text" && !e.text.trim()) {
      this.setState((st) => ({ edit: null, slash: null, tasks: st.tasks.filter((x) => x.id !== e.id), blocks: st.blocks.filter((x) => x.id !== e.id) }), after);
      if (pre && !pre.isNew) this.pushUndo(pre, "Removed an empty line", e.id);
      return;
    }
    const val = e.field === "note" ? e.text.replace(/\s+$/, "") : e.text.trim();
    const changed = e.field === "note" ? val !== (ln.note || "") : val !== ln.text;
    const structural = pre && (pre.tasks !== s.tasks || pre.blocks !== s.blocks);
    this.setState((st) => ({ edit: null, slash: null, ...this.patchLine(st, e.id, e.field === "note" ? { note: val, noteOpen: !!val } : { text: val, _new: false }) }), after);
    if (pre && (changed || structural)) this.pushUndo(pre, pre.isNew ? "Added “" + this.short(val) + "”" : e.field === "note" ? "Edited note on “" + this.short(ln.text) + "”" : "Edited “" + this.short(val) + "”", e.id);
  }
  addLine(refId, opts = {}) {
    const s = this.state; const ref = refId ? this.lineOf(refId) : null; const listId = ref ? ref.list : opts.list;
    const items = this.docItems(listId); let depth = 0, order, kind = opts.kind || "task";
    if (ref) {
      const head = this.isHead(ref.kind); const sub = this.subtree(ref.id);
      kind = opts.kind || (head || ref.kind === "text" ? (ref.kind === "text" ? "text" : "task") : ref.kind);
      const idxOf = (id) => items.findIndex((y) => y.id === id);
      if (!ref.isBlock && !ref.collapsed && sub.length) { depth = (ref.depth || 0) + 1; const nx = items[idxOf(ref.id) + 1]; order = ((ref.order ?? 0) + (nx.order ?? (ref.order ?? 0) + 10)) / 2; }
      else { depth = head || kind === "text" ? 0 : ref.depth || 0; const last = sub.length ? sub[sub.length - 1] : ref; const nx = items[idxOf(last.id) + 1]; const lo = last.order ?? 0; order = nx && nx.order != null ? (lo + nx.order) / 2 : lo + 10; }
    } else { const last = items[items.length - 1]; order = (last && last.order != null ? last.order : 0) + 10; }
    const id = "e" + ++this.seq + "_" + Date.now();
    this.preEdit = { id, isNew: true, ...this.baseSnap() };
    const base = { id, list: listId, text: "", order, depth, fresh: true, _new: true };
    this.focusPending = id + ":text"; this.caretAt = null;
    this.setState((st) => ({ ...(kind === "task" ? { tasks: [...st.tasks, { ...base, due: null, labels: [], created: Date.now() }] } : { blocks: [...st.blocks, { ...base, kind }] }), edit: { id, field: "text", text: "" }, slash: null, focusId: kind === "task" ? id : null, selected: {} }));
    this.later("fresh" + id, () => this.setState((st) => this.patchLine(st, id, { fresh: false })), 1100);
  }
  indent(id, dir) {
    this.setState((st) => {
      const ln = this.lineOf(id, st); if (!ln || this.isHead(ln.kind) || ln.kind === "text") return {};
      const items = this.docItems(ln.list, st); const i = items.findIndex((y) => y.id === id); const prev = items[i - 1];
      const d = ln.depth || 0; const maxD = prev && (prev.kind === "task" || prev.kind === "bullet") ? (prev.depth || 0) + 1 : 0;
      const nd = Math.max(0, Math.min(d + dir, maxD, 2)); if (nd === d) return {};
      const sub = this.subtree(id, st).map((y) => y.id); const delta = nd - d;
      const f = (x) => (x.id === id || sub.includes(x.id) ? { ...x, depth: Math.max(0, (x.depth || 0) + delta) } : x);
      return { tasks: st.tasks.map(f), blocks: st.blocks.map(f) };
    });
  }
  neighbour(id, dir) { const ids = this.visibleIds || []; const i = ids.indexOf(id); return i < 0 ? null : ids[i + dir] || null; }
  slashOpts(q) {
    return [["task", "Task", "check_box_outline_blank", "[ ]"], ["h1", "Heading", "format_h1", "#"], ["h2", "Subheading", "format_h2", "##"], ["bullet", "Bullet", "format_list_bulleted", "-"], ["text", "Text", "notes", ">"]]
      .filter(([, l]) => !q || l.toLowerCase().includes(q)).map(([kind, label, icon, hint]) => ({ kind, label, icon, hint }));
  }
  applySlash(id, kind) { this.focusPending = id + ":text"; this.caretAt = 0; this.setState((st) => ({ ...this.convert(st, id, kind), edit: { ...st.edit, text: "" }, slash: null })); this.unmorph(id); }
  toggleNote(id) {
    const x = this.T(id); if (!x) return;
    if (!x.noteOpen && !x.note) { this.startEdit(id, "note"); return; }
    this.setState((st) => this.patchLine(st, id, { noteOpen: !x.noteOpen }));
  }
  onEditChange(e) {
    const v = e.target.value; const s = this.state; const ed = s.edit; if (!ed) return;
    if (ed.field === "text") {
      const m = v.match(/^(##|#|-|\*|\[ ?\]|>)\s/);
      if (m) {
        const kind = m[1] === "#" ? "h1" : m[1] === "##" ? "h2" : m[1] === ">" ? "text" : m[1].startsWith("[") ? "task" : "bullet";
        this.focusPending = ed.id + ":text"; this.caretAt = 0;
        this.setState((st) => ({ ...this.convert(st, ed.id, kind), edit: { ...ed, text: v.slice(m[0].length) }, slash: null })); this.unmorph(ed.id); return;
      }
      if (v.startsWith("/")) { this.setState({ edit: { ...ed, text: v }, slash: { id: ed.id, q: v.slice(1).toLowerCase(), idx: s.slash && s.slash.id === ed.id ? s.slash.idx : 0 } }); return; }
    }
    this.setState({ edit: { ...ed, text: v }, slash: null });
  }
  onEditKey(e) {
    const s = this.state; const ed = s.edit; if (!ed) return; const ln = this.lineOf(ed.id); if (!ln) return;
    const sl = s.slash && s.slash.id === ed.id ? s.slash : null;
    if (sl) {
      const opts = this.slashOpts(sl.q); const n = Math.max(1, opts.length);
      if (e.key === "ArrowDown" || e.key === "ArrowUp") { e.preventDefault(); this.setState({ slash: { ...sl, idx: (sl.idx + (e.key === "ArrowDown" ? 1 : -1) + n) % n } }); return; }
      if (e.key === "Enter") { e.preventDefault(); if (opts[sl.idx]) this.applySlash(ed.id, opts[sl.idx].kind); return; }
      if (e.key === "Escape") { e.preventDefault(); this.setState({ slash: null }); return; }
    }
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      if (!ed.text.trim()) { if ((ln.depth || 0) > 0) this.indent(ed.id, -1); else if (ln.kind !== "task") { this.setState((st) => this.convert(st, ed.id, "task")); this.unmorph(ed.id); } return; }
      this.commitEdit(() => this.addLine(ed.id)); return;
    }
    if (e.key === "Enter" && e.shiftKey && ln.kind === "task") { e.preventDefault(); this.commitEdit(() => this.startEdit(ed.id, "note")); return; }
    if (e.key === "Tab") { e.preventDefault(); this.indent(ed.id, e.shiftKey ? -1 : 1); return; }
    if (e.key === "Backspace" && e.target.selectionStart === 0 && e.target.selectionEnd === 0) {
      if (!ed.text) { e.preventDefault(); const prev = this.neighbour(ed.id, -1); this.commitEdit(() => prev && this.startEdit(prev)); return; }
      if (ln.kind !== "task" && ln.kind !== "text") { e.preventDefault(); this.setState((st) => this.convert(st, ed.id, "text")); this.unmorph(ed.id); return; }
      if ((ln.depth || 0) > 0) { e.preventDefault(); this.indent(ed.id, -1); return; }
    }
    if (e.key === "ArrowUp" || e.key === "ArrowDown") { const nb = this.neighbour(ed.id, e.key === "ArrowUp" ? -1 : 1); if (nb) { e.preventDefault(); this.commitEdit(() => this.startEdit(nb)); } return; }
    if (e.key === "Escape") { e.preventDefault(); this.commitEdit(); }
  }
  onEditBlur(id, field) {
    setTimeout(() => { const ed = this.state.edit; if (ed && ed.id === id && ed.field === field && !(document.activeElement && /input|textarea/i.test(document.activeElement.tagName) && document.activeElement.dataset.line === id)) this.commitEdit(); }, 0);
  }

  mkDoc(listId) {
    const s = this.state, A = this.A(); const items = this.docItems(listId);
    const vis = []; let hideDepth = null, hideHead = null;
    items.forEach((it) => {
      const lvl = it.kind === "h1" ? 1 : it.kind === "h2" ? 2 : 9; const d = it.depth || 0;
      if (hideHead != null) { if (lvl <= hideHead) hideHead = null; else return; }
      if (hideDepth != null) { if (d > hideDepth && lvl === 9) return; hideDepth = null; }
      if (!it.isBlock && it.done && !s.closing[it.id] && d === 0) { hideDepth = d; return; }
      vis.push(it);
      if (!it.isBlock && it.collapsed) hideDepth = d;
      if (lvl < 9 && it.collapsed) hideHead = lvl;
    });
    this.visibleIds = vis.map((v) => v.id);
    const fonts = {
      task: "font:400 13.8px/1.45 -apple-system,sans-serif; color:#17161A;", bullet: "font:400 13.8px/1.45 -apple-system,sans-serif; color:#17161A;",
      text: "font:400 13.5px/1.55 -apple-system,sans-serif; color:rgba(23,22,26,0.66);",
      h1: "font:700 20px/1.3 -apple-system,sans-serif; color:#17161A; letter-spacing:-0.01em;", h2: "font:600 15.5px/1.35 -apple-system,sans-serif; color:#17161A;",
    };
    const holders = { task: "Task — “/” turns it into anything, ⇥ makes it a subtask", bullet: "List item", text: "Write something…", h1: "Heading", h2: "Subheading" };
    return vis.map((it) => {
      const kind = it.kind; const isTask = kind === "task"; const head = this.isHead(kind); const d = it.depth || 0;
      const ed = s.edit && s.edit.id === it.id ? s.edit : null; const editing = !!ed && ed.field === "text"; const noteEditing = !!ed && ed.field === "note";
      const i = items.findIndex((y) => y.id === it.id); const sect = [];
      for (let j = i + 1; j < items.length; j++) { const y = items[j]; const yl = y.kind === "h1" ? 1 : y.kind === "h2" ? 2 : 9; if (head ? yl <= (kind === "h1" ? 1 : 2) : yl < 9 || (y.depth || 0) <= d) break; sect.push(y); }
      const kidTasks = sect.filter((y) => !y.isBlock); const kd = kidTasks.filter((y) => y.done || s.closing[y.id]).length;
      const base = isTask ? this.mkRow(this.T(it.id), { showList: false, listId }) : {};
      const chips = isTask ? [...(kidTasks.length ? [this.chip(kd + "/" + kidTasks.length, { icon: "subdirectory_arrow_right", tone: kd === kidTasks.length ? "green" : "neutral" })] : []), ...base.chips]
        : head && it.collapsed && kidTasks.length ? [this.chip(kidTasks.filter((y) => !y.done).length + " open", {})] : [];
      const edStyle = editing || noteEditing ? " background:" + (head ? "transparent" : "rgba(23,22,26,0.035)") + "; box-shadow:none; z-index:4;" : "";
      const anim = it.fresh ? " animation:rowIn 300ms cubic-bezier(0.2,0.9,0.2,1);" : it.morph ? " animation:morphIn 320ms cubic-bezier(0.2,0.9,0.2,1);" : "";
      const lineStyle = isTask ? base.wrapStyle + edStyle + anim
        : "position:relative; display:flex; align-items:flex-start; border-radius:9px; transition:background 180ms ease, box-shadow 180ms ease; padding:" + (kind === "h1" ? "20px 10px 4px" : kind === "h2" ? "13px 10px 3px" : "5px 10px") + ";" + edStyle + anim;
      const slashOn = s.slash && s.slash.id === it.id; const opts = slashOn ? this.slashOpts(s.slash.q) : [];
      return {
        ...base, id: it.id, isTask, isBullet: kind === "bullet", text: it.text, chips, lineStyle,
        indentStyle: "width:" + d * 26 + "px; flex:none;",
        hasCaret: isTask ? sect.length > 0 : head && sect.length > 0,
        caretStyle: "position:absolute; left:" + (d * 26 - 10) + "px; top:" + (kind === "h1" ? 23 : kind === "h2" ? 15 : 6) + "px; font-size:16px; border-radius:5px; cursor:pointer; color:rgba(23,22,26,0.34); transition:transform 180ms ease; transform:rotate(" + (it.collapsed ? 0 : 90) + "deg);",
        onCaret: (e) => { e.stopPropagation(); this.setState((st) => this.patchLine(st, it.id, { collapsed: !it.collapsed })); },
        showText: !editing, editing, draft: ed ? ed.text : "", placeholder: holders[kind],
        textStyle: isTask ? base.textStyle : fonts[kind] + " position:relative; display:inline; white-space:pre-wrap;",
        strikeStyle: isTask ? base.strikeStyle : "display:none;",
        inputStyle: "display:block; width:100%; box-sizing:border-box; border:none; outline:none; background:transparent; padding:0; margin:0; caret-color:" + A + "; " + fonts[kind],
        inputRef: (el) => { if (!el) return; el.dataset.line = it.id; if (this.focusPending === it.id + ":text") { this.focusPending = null; el.focus(); const p = this.caretAt == null ? el.value.length : Math.min(this.caretAt, el.value.length); try { el.setSelectionRange(p, p); } catch (x) {} } },
        onChange: (e) => this.onEditChange(e), onKeyDown: (e) => this.onEditKey(e), onBlur: () => this.onEditBlur(it.id, "text"),
        onLineClick: isTask ? base.onClick : (e) => { e.stopPropagation(); this.startEdit(it.id); },
        onEdit: (e) => { e.stopPropagation(); if (s.closing[it.id]) { this.cancelClose(it.id); return; } if (e.metaKey || e.ctrlKey || e.shiftKey) { isTask && this.toggleSel(it.id); return; } this.startEdit(it.id); },
        onOpen: isTask ? base.onOpen : () => {},
        showNote: isTask && (it.noteOpen || noteEditing), noteEditing, noteShow: isTask && it.noteOpen && !noteEditing,
        noteDraft: noteEditing ? ed.text : "", noteRows: Math.max(1, ((noteEditing ? ed.text : it.note) || "").split("\n").length),
        noteText: it.note || "Add a note…", noteHint: isTask && !!it.note && !it.noteOpen,
        noteStyle: "font:400 13px/1.55 -apple-system,sans-serif; white-space:pre-wrap; cursor:text; text-wrap:pretty; color:" + (it.note ? "rgba(23,22,26,0.62)" : "rgba(23,22,26,0.32)") + ";",
        noteRef: (el) => { if (!el) return; el.dataset.line = it.id; if (this.focusPending === it.id + ":note") { this.focusPending = null; el.focus(); const p = el.value.length; try { el.setSelectionRange(p, p); } catch (x) {} } },
        onNoteChange: (e) => { const v = e.target.value; this.setState((st) => ({ edit: { ...st.edit, text: v } })); },
        onNoteKey: (e) => { if (e.key === "Escape" || (e.key === "Enter" && (e.metaKey || e.ctrlKey))) { e.preventDefault(); this.commitEdit(); } else if (e.key === "Tab" && e.shiftKey) { e.preventDefault(); this.commitEdit(() => this.startEdit(it.id)); } },
        onNoteBlur: () => this.onEditBlur(it.id, "note"),
        onNoteEdit: (e) => { e.stopPropagation(); this.startEdit(it.id, "note"); },
        onNoteToggle: (e) => { e.stopPropagation(); this.toggleNote(it.id); },
        noteBtnStyle: "font-size:15px; padding:3px; border-radius:6px; cursor:pointer; transition:opacity 140ms ease; color:" + (it.noteOpen ? A : "rgba(23,22,26,0.45)") + "; opacity:" + (it.note || it.noteOpen ? 0.9 : 0.2) + ";",
        slashOpen: slashOn, keep: (e) => e.preventDefault(),
        slashItems: opts.map((o, k) => ({ ...o, onPick: (e) => { e.preventDefault(); this.applySlash(it.id, o.kind); },
          style: "display:flex; align-items:center; gap:10px; padding:8px 9px; border-radius:7px; cursor:pointer; " + (k === (s.slash ? s.slash.idx : 0) ? "background:" + A + "; color:#fff;" : "color:#17161A;"),
          iconStyle: "font-size:16px; color:" + (k === (s.slash ? s.slash.idx : 0) ? "#fff" : "rgba(23,22,26,0.5)") + ";" })),
      };
    });
  }

  buildGroups() {
    const s = this.state, r = s.route;
    const visible = (x) => !x.trashed && (!x.done || !!s.closing[x.id]);
    const openAll = s.tasks.filter(visible);
    const H = 3600e3; const doneToday = s.tasks.filter((x) => x.done && !x.trashed && x.doneAt && x.doneAt > s.now - 18 * H).sort((a, b) => b.doneAt - a.doneAt);
    const G = (key, title, icon, color, rows, o = {}) => ({ key, title, icon, color, rows, ...o });
    let groups = [], rowOpts = { showList: true }, extra = {};
    if (r === "today") {
      const od = openAll.filter((x) => x.due != null && x.due < 0);
      const dt = openAll.filter((x) => x.due === 0);
      const pl = openAll.filter((x) => x.planned && !(x.due != null && x.due <= 0));
      const st = openAll.filter((x) => x.star && !(x.due != null && x.due <= 0) && !x.planned);
      if (od.length) groups.push(G("overdue", "Overdue", "error", "#D8434B", od, { action: { label: "Move all to today", run: () => this.schedule(od.map((x) => x.id), 0) } }));
      if (dt.length) groups.push(G("due", "Due today", "today", this.A(), dt));
      if (pl.length) groups.push(G("planned", "Planned for today", "calendar_clock", this.A(), pl, { action: { label: "Fit into calendar", run: () => pl.forEach((x) => { if (!s.placements.find((p) => p.id === x.id)) this.fit(x.id); }) } }));
      if (st.length) groups.push(G("starred", "Starred", "star", "#E8A917", st));
      extra.todayClear = !od.length && !dt.length && !pl.length && !st.length;
      if (doneToday.length) groups.push(G("done", "Completed today", "check_circle", "#2F9E6E", doneToday, { collapsible: true, openOverride: s.completedOpen || s.settings.showCompleted }));
      extra.progress = [doneToday.length, doneToday.length + od.length + dt.length + pl.length + st.length];
    } else if (r === "inbox") {
      const q = this.queue(); const kept = openAll.filter((x) => x.list === "inbox" && s.kept[x.id]);
      rowOpts = { showList: false, listId: "inbox" };
      if (q.length > 1) groups.push(G("next", "Up next", "low_priority", "#3A7BD8", q.slice(1)));
      if (kept.length) groups.push(G("kept", "Kept for later", "schedule", "rgba(23,22,26,0.45)", kept, { collapsible: true }));
    } else if (r.startsWith("list:") || r.startsWith("label:")) {
      const isList = r.startsWith("list:"); const id = r.slice(isList ? 5 : 6);
      const mine = (x) => (isList ? x.list === id : (x.labels || []).includes(id));
      rowOpts = { showList: !isList, listId: isList ? id : null, notes: true };
      const open = openAll.filter(mine); const done = s.tasks.filter((x) => x.done && !x.trashed && mine(x) && !s.closing[x.id] && !(isList && (x.depth || 0) > 0));
      if (!isList) groups.push(G("open", "", "", "", open, { noHead: true, emptyText: "No open tasks. Press N to capture one." }));
      if (done.length) groups.push(G("ldone", "Completed", "check_circle", "#2F9E6E", done, { collapsible: true, openOverride: s.completedOpen || s.settings.showCompleted }));
      extra.progress = [s.tasks.filter((x) => x.done && !x.trashed && mine(x)).length, s.tasks.filter((x) => !x.trashed && mine(x)).length];
    } else if (r === "tasks") {
      const tf = s.tf; const lf = Object.keys(tf.lists).filter((k) => tf.lists[k]);
      let pool = s.tasks.filter((x) => !x.trashed && (tf.status === "open" ? !x.done || s.closing[x.id] : tf.status === "done" ? x.done : true));
      if (this.queryMode()) pool = this.tqApply(pool);
      else { if (lf.length) pool = pool.filter((x) => lf.includes(x.list)); if (tf.q && tf.q.trim()) { const qq = tf.q.trim().toLowerCase(); pool = pool.filter((x) => x.text.toLowerCase().includes(qq)); } }
      extra.tfCount = pool.length;
      rowOpts = { showList: tf.group !== "list", quiet: true };
      if (tf.group === "list") s.lists.forEach((l) => { const rows = pool.filter((x) => x.list === l.id); if (rows.length) groups.push(G("l-" + l.id, l.emoji + "  " + l.name, "", "", rows, { collapsible: true, noIcon: true })); });
      else if (tf.group === "due") {
        const b = [["Overdue", (d) => d != null && d < 0, "#D8434B"], ["Today", (d) => d === 0, this.A()], ["Tomorrow", (d) => d === 1, "rgba(23,22,26,0.5)"], ["This week", (d) => d > 1 && d <= 6, "rgba(23,22,26,0.5)"], ["Later", (d) => d > 6, "rgba(23,22,26,0.5)"], ["No date", (d) => d == null, "rgba(23,22,26,0.35)"]];
        b.forEach(([t, fn, c]) => { const rows = pool.filter((x) => fn(x.due)); if (rows.length) groups.push(G("d-" + t, t, "event", c, rows, { collapsible: true })); });
      } else groups.push(G("all", "All tasks", "checklist", "#2F9E6E", pool));
      if (!groups.length) groups.push(G("none", "", "", "", [], { noHead: true, emptyText: "Nothing matches these filters." }));
    }
    return { groups, rowOpts, extra };
  }

  queryMode() { return (this.props.tasksFilter ?? "Query") === "Query"; }
  listKey(l) { return /^u\d+$/.test(l.id) ? l.name.toLowerCase().split(/\s+/).pop() : l.id; }
  tqVocab() {
    const v = [];
    [["overdue", "date"], ["today", "date"], ["tomorrow", "date"], ["week", "date"], ["later", "date"], ["undated", "date"], ["starred", "flag"], ["planned", "flag"], ["high", "flag"]].forEach(([w, kind]) => v.push({ w, kind }));
    this.state.lists.forEach((l) => { const keys = new Set([this.listKey(l), ...l.name.toLowerCase().split(/\s+/).filter((x) => x.length >= 4)]); keys.forEach((w) => v.push({ w, kind: "list", list: l.id, color: l.color })); });
    Component.LABELS.forEach((lb) => v.push({ w: "#" + lb.id, kind: "label", label: lb.id, color: lb.color }));
    return v;
  }
  tqParse(q) {
    const vocab = this.tqVocab(); const segs = []; const f = { lists: [], due: [], labels: [], flags: [], text: [] };
    const re = /\S+|\s+/g; let m;
    while ((m = re.exec(q)) !== null) {
      const w = m[0]; if (/^\s+$/.test(w)) { segs.push({ text: w, kind: null }); continue; }
      const lw = w.toLowerCase(); const hit = vocab.find((x) => x.w === lw);
      if (!hit) { segs.push({ text: w, kind: null }); f.text.push(lw); continue; }
      segs.push({ text: w, kind: hit.kind, color: hit.color });
      if (hit.kind === "list") f.lists.push(hit.list); else if (hit.kind === "label") f.labels.push(hit.label); else if (hit.kind === "date") f.due.push(lw); else f.flags.push(lw);
    }
    let ghost = ""; const last = q.match(/(\S+)$/);
    if (last) { const lw = last[1].toLowerCase(); if (!vocab.find((x) => x.w === lw)) { const g = vocab.find((x) => x.w.startsWith(lw)); if (g) ghost = g.w.slice(lw.length); } }
    return { segs, f, ghost };
  }
  tqApply(pool) {
    const { f } = this.tqParse(this.state.tf.tq || "");
    const ok = { overdue: (d) => d != null && d < 0, today: (d) => d === 0, tomorrow: (d) => d === 1, week: (d) => d != null && d >= 0 && d <= 6, later: (d) => d != null && d > 6, undated: (d) => d == null };
    return pool.filter((x) => (!f.lists.length || f.lists.includes(x.list)) && (!f.due.length || f.due.some((k) => ok[k](x.due))) && (!f.labels.length || f.labels.some((l) => (x.labels || []).includes(l))) && f.flags.every((k) => (k === "starred" ? x.star : k === "planned" ? x.planned : x.prio === "high")) && f.text.every((t) => x.text.toLowerCase().includes(t)));
  }
  tqToggle(word) {
    const parts = (this.state.tf.tq || "").split(/\s+/).filter(Boolean); const i = parts.findIndex((p) => p.toLowerCase() === word);
    if (i >= 0) parts.splice(i, 1); else parts.push(word);
    const nq = parts.length ? parts.join(" ") + " " : "";
    this.setState((st) => ({ tf: { ...st.tf, tq: nq } }));
  }
  tqVals(extra, onTasks) {
    const s = this.state, A = this.A(), tf = s.tf; const q = tf.tq || ""; const qm = this.queryMode();
    const { segs, ghost } = this.tqParse(q);
    const parts = q.toLowerCase().split(/\s+/).filter(Boolean);
    const nonTrash = s.tasks.filter((x) => !x.trashed);
    const counts = { open: nonTrash.filter((x) => !x.done).length, done: nonTrash.filter((x) => x.done).length, all: nonTrash.length };
    const tabs = [["open", "Open"], ["done", "Completed"], ["all", "All"]].map(([v, label]) => { const on = tf.status === v; return { label, count: String(counts[v]),
      onClick: () => this.setState((st) => ({ tf: { ...st.tf, status: v } })),
      style: "position:relative; display:flex; align-items:baseline; gap:6px; padding:0 0 13px; cursor:pointer; font:" + (on ? 600 : 500) + " 13.5px/1 -apple-system,sans-serif; color:" + (on ? "#17161A" : "rgba(23,22,26,0.42)") + "; transition:color 160ms ease;",
      countStyle: "font:500 11px/1 -apple-system,sans-serif; font-variant-numeric:tabular-nums; color:rgba(23,22,26," + (on ? 0.45 : 0.28) + ");",
      barStyle: "position:absolute; left:0; right:0; bottom:-0.5px; height:2px; border-radius:2px; background:#17161A; transform-origin:center; transition:transform 280ms cubic-bezier(0.2,0.9,0.2,1); transform:scaleX(" + (on ? 1 : 0) + ");" }; });
    const col = (sg) => sg.color || (sg.kind === "flag" ? "#A87A06" : A);
    const pill = (word, label, color, emoji) => { const on = parts.includes(word); return { label, emoji: emoji || "", hasEmoji: !!emoji, onClick: () => this.tqToggle(word),
      style: "display:inline-flex; align-items:center; gap:5px; padding:6px 10px; border-radius:999px; cursor:pointer; font:500 12px/1 -apple-system,sans-serif; white-space:nowrap; transition:background 140ms ease, color 140ms ease, box-shadow 140ms ease; " + (on ? "background:" + color + "; color:#fff; box-shadow:inset 0 0 0 1px " + color + ";" : "background:transparent; color:rgba(23,22,26,0.7); box-shadow:inset 0 0 0 1px rgba(23,22,26,0.12);") }; };
    const focus = !!s.tqFocus; const hasQ = !!q.trim();
    return {
      tqShow: onTasks && qm, tfSentenceShow: onTasks && !qm,
      tqTabs: tabs, tqText: q, tqGhost: focus ? ghost : "",
      tqSegs: segs.map((sg) => ({ text: sg.text, style: "white-space:pre; " + (sg.kind ? "color:" + col(sg) + "; background:" + (sg.kind === "flag" ? "#E8A917" : col(sg)) + "1C; border-radius:5px; box-shadow:inset 0 -1.5px 0 " + col(sg) + "55;" : "color:#17161A;") })),
      tqPlaceholder: q ? "" : focus ? "Try “kyoto overdue”" : "Filter",
      tqPlaceholderStyle: focus ? "color:rgba(23,22,26,0.34);" : "color:rgba(23,22,26,0.42); font-weight:500;",
      tqBarStyle: "position:absolute; left:0; right:0; bottom:-0.5px; height:2px; border-radius:2px; transform-origin:left center; transition:transform 280ms cubic-bezier(0.2,0.9,0.2,1), background 180ms ease; background:" + (focus ? "#17161A" : "rgba(23,22,26,0.22)") + "; transform:scaleX(" + (focus || hasQ ? 1 : 0) + ");",
      tqHasQ: hasQ, tqCount: String(extra.tfCount ?? ""),
      tqClear: (e) => { if (e) e.stopPropagation(); this.setState((st) => ({ tf: { ...st.tf, tq: "" } })); setTimeout(() => this.tqEl && this.tqEl.focus(), 10); },
      tqKeep: (e) => e.preventDefault(),
      tqFocus: focus,
      tqGroups: [
        { title: "When", pills: [["overdue", "Overdue"], ["today", "Today"], ["tomorrow", "Tomorrow"], ["week", "This week"], ["later", "Later"], ["undated", "No date"]].map(([w, l]) => pill(w, l, A)) },
        { title: "List", pills: s.lists.map((l) => pill(this.listKey(l), l.name, l.color, l.emoji)) },
        { title: "Label", pills: Component.LABELS.map((lb) => pill("#" + lb.id, "#" + lb.id, lb.color)) },
        { title: "Only", pills: [["starred", "Starred"], ["planned", "Planned"], ["high", "High priority"]].map(([w, l]) => pill(w, l, "#A87A06")) },
      ],
      tqRef: (el) => { this.tqEl = el; },
      tqFocusField: () => this.tqEl && this.tqEl.focus(),
      onTqChange: (e) => { const v = e.target.value; this.setState((st) => ({ tf: { ...st.tf, tq: v } })); },
      onTqFocus: () => { clearTimeout(this.timers.tqBlur); this.setState({ tqFocus: true }); },
      onTqBlur: () => this.later("tqBlur", () => this.setState({ tqFocus: false }), 120),
      onTqKey: (e) => {
        if (e.key === "Tab") { e.preventDefault(); if (ghost) this.setState((st) => ({ tf: { ...st.tf, tq: st.tf.tq + ghost + " " } })); }
        else if (e.key === "Escape") { e.preventDefault(); if (q) this.setState((st) => ({ tf: { ...st.tf, tq: "" } })); else e.target.blur(); }
        else if (e.key === "Enter") { e.preventDefault(); e.target.blur(); }
      },
      tqGroupIcon: { list: "layers", due: "event", none: "view_agenda" }[tf.group],
      tqGroupLabel: { list: "By list", due: "By date", none: "Flat" }[tf.group],
      tqCycleGroup: () => this.setState((st) => ({ tf: { ...st.tf, group: { list: "due", due: "none", none: "list" }[st.tf.group] } })),
      tqFieldStyle: "position:relative; display:flex; align-items:center; gap:8px; padding:0 0 9px; box-sizing:border-box; cursor:text; transition:width 280ms cubic-bezier(0.2,0.9,0.2,1); width:" + (focus ? 300 : hasQ ? 240 : 44) + "px; max-width:100%;",
      tqIconStyle: "font-size:15px; transition:color 160ms ease; color:" + (focus || hasQ ? "#17161A" : "rgba(23,22,26,0.38)") + ";",
    };
  }

  tfVals() {
    const s = this.state, A = this.A(), tf = s.tf; const lf = Object.keys(tf.lists).filter((k) => tf.lists[k]);
    const nonTrash = s.tasks.filter((x) => !x.trashed);
    const tok = (key) => "display:inline-flex; align-items:center; gap:1px; padding:5px 4px 5px 7px; border-radius:7px; cursor:pointer; font:600 13px/1 -apple-system,sans-serif; color:#17161A; white-space:nowrap; transition:background 140ms ease;" + (s.tfMenu && s.tfMenu.key === key ? " background:rgba(23,22,26,0.07);" : "");
    const open = (key) => (e) => { e.stopPropagation(); const el = e.currentTarget; this.setState((st) => ({ tfMenu: st.tfMenu && st.tfMenu.key === key ? null : { key, left: el.offsetLeft, top: el.offsetTop + el.offsetHeight + 6 } })); };
    const row = (on) => "display:flex; align-items:center; gap:9px; padding:8px 9px; border-radius:7px; cursor:pointer; color:#17161A;" + (on ? " background:" + A + "10;" : "");
    const chk = (on) => "font-size:15px; color:" + A + "; opacity:" + (on ? 1 : 0) + "; transition:opacity 120ms ease;";
    let items = [];
    const m = s.tfMenu;
    if (m && m.key === "status") items = [["open", "Open", nonTrash.filter((x) => !x.done).length], ["done", "Completed", nonTrash.filter((x) => x.done).length], ["all", "All", nonTrash.length]].map(([v, label, n]) => ({ emoji: "", label, count: String(n), style: row(tf.status === v), checkStyle: chk(tf.status === v), onClick: () => this.setState((st) => ({ tf: { ...st.tf, status: v }, tfMenu: null })) }));
    if (m && m.key === "group") items = [["list", "List"], ["due", "Due date"], ["none", "Nothing — one list"]].map(([v, label]) => ({ emoji: "", label, count: "", style: row(tf.group === v), checkStyle: chk(tf.group === v), onClick: () => this.setState((st) => ({ tf: { ...st.tf, group: v }, tfMenu: null })) }));
    if (m && m.key === "lists") items = [{ emoji: "", label: "All lists", count: "", style: row(!lf.length), checkStyle: chk(!lf.length), onClick: () => this.setState((st) => ({ tf: { ...st.tf, lists: {} } })) },
      ...s.lists.map((l) => { const on = !!tf.lists[l.id]; return { emoji: l.emoji, label: l.name, count: String(nonTrash.filter((x) => x.list === l.id && !x.done).length), style: row(on), checkStyle: chk(on), onClick: () => this.setState((st) => ({ tf: { ...st.tf, lists: { ...st.tf.lists, [l.id]: !st.tf.lists[l.id] } } })) }; })];
    const one = lf.length === 1 ? this.L(lf[0]) : null;
    return {
      tfStatusLabel: { open: "open", done: "completed", all: "all" }[tf.status],
      tfListsLabel: !lf.length ? "all lists" : one ? one.emoji + " " + one.name : lf.length + " lists",
      tfGroupLabel: { list: "list", due: "due date", none: "nothing" }[tf.group],
      tfTokStatus: tok("status"), tfTokLists: tok("lists"), tfTokGroup: tok("group"),
      tfOpenStatus: open("status"), tfOpenLists: open("lists"), tfOpenGroup: open("group"),
      tfMenuOpen: !!m, tfMenuItems: items,
      tfMenuStyle: m ? "position:absolute; z-index:20; left:" + m.left + "px; top:" + m.top + "px; width:250px; padding:5px; border-radius:11px; background:#fff; box-shadow:0 16px 40px rgba(40,30,20,0.18), 0 0 0 0.5px rgba(23,22,26,0.14); display:flex; flex-direction:column; gap:1px; animation:popIn 160ms cubic-bezier(0.2,0.9,0.2,1); transform-origin:top left;" : "display:none;",
    };
  }

  renderVals() {
    const s = this.state, A = this.A(), ms = this.ms(), dwell = this.dwell(), r = s.route;
    const H = 3600e3;
    const isList = r.startsWith("list:"), isLabel = r.startsWith("label:");
    const curList = isList ? this.L(r.slice(5)) : null;
    const openTasks = s.tasks.filter((x) => this.live(x));
    const q = this.queue();

    // groups
    const { groups: rawGroups, rowOpts, extra } = this.buildGroups();
    const rowIds = [];
    const groups = rawGroups.map((g) => {
      const collapsed = g.collapsible && (g.openOverride !== undefined ? !g.openOverride : !!s.collapsed[g.key]);
      const rows = collapsed ? [] : g.rows.map((x) => { rowIds.push(x.id); return this.mkRow(x, rowOpts); });
      return {
        title: g.title, icon: g.icon || "circle", count: g.rows.length ? String(g.rows.length) : "", showHead: !g.noHead,
        collapsible: !!g.collapsible, open: !collapsed, rows, isEmpty: !collapsed && g.rows.length === 0, emptyText: g.emptyText || "",
        hasAction: !!g.action, actionLabel: g.action ? g.action.label : "",
        onAction: (e) => { e.stopPropagation(); g.action && g.action.run(); },
        onToggle: (e) => { e.stopPropagation(); if (!g.collapsible) return; if (g.openOverride !== undefined) this.setState((st) => ({ completedOpen: !st.completedOpen })); else this.setState((st) => ({ collapsed: { ...st.collapsed, [g.key]: !st.collapsed[g.key] } })); },
        headStyle: "display:flex; align-items:center; gap:7px; padding:6px 10px; border-radius:8px; cursor:" + (g.collapsible ? "pointer" : "default") + ";",
        iconStyle: g.noIcon ? "display:none;" : "font-size:14px; color:" + g.color + ";",
        chevStyle: "font-size:14px; color:rgba(23,22,26,0.36); transition:transform 180ms ease; transform:rotate(" + (collapsed ? 0 : 90) + "deg);",
      };
    });
    const doc = isList ? this.mkDoc(curList.id) : [];
    this.rowIds = [...doc.filter((d) => d.isTask).map((d) => d.id), ...rowIds];
    const showGroups = ["today", "inbox", "tasks"].includes(r) || isList || isLabel;

    // header
    const hdrMap = {
      inbox: ["inbox", "#3A7BD8", "Inbox", q.length + " to triage" + (Object.keys(s.kept).length ? " · " + openTasks.filter((x) => x.list === "inbox" && s.kept[x.id]).length + " kept for later" : "")],
      today: ["wb_sunny", "#E0861F", "Today", "Wednesday, 23 September"],
      calendar: ["calendar_month", A, "Calendar", s.calRange === 7 ? "21 – 27 September" : s.calRange === 3 ? "23 – 25 September" : "Wednesday, 23 September"],
      tasks: ["checklist", "#2F9E6E", "Tasks", openTasks.length + " open across " + (s.lists.length) + " lists"],
      lists: ["layers", "#5B5BD6", "Lists", (s.lists.length - 1) + " lists in 2 sections"],
            activity: ["grid_view", A, "Activity", "What you finished and what changed"],
      trash: ["delete", "#6E6A73", "Trash", "Stays here until you erase it"],
      settings: ["settings", "#6E6A73", "Settings", "Preferences for this Mac"],
    };
    let hdr = hdrMap[r];
    if (isList) hdr = [null, curList.color, curList.name, openTasks.filter((x) => x.list === curList.id).length + " open · " + (curList.section || "")];
    if (isLabel) { const id = r.slice(6); hdr = ["sell", this.labelColor(id), "#" + id, openTasks.filter((x) => (x.labels || []).includes(id)).length + " open tasks with this label"]; }
    if (!hdr) hdr = hdrMap.today;
    const prog = extra.progress;
    const pct = prog && prog[1] ? Math.round((prog[0] / prog[1]) * 100) : 0;

    // triage
    const tx = r === "inbox" ? q[0] : null;
    const tr = s.triage; const totalQ = Math.min(12, s.reviewed + q.length);
    const exitMap = { left: "transform:translateX(-90px) rotate(-1.5deg); opacity:0;", right: "transform:translateX(90px) rotate(1.5deg); opacity:0;", up: "transform:translateY(-26px) scale(0.97); opacity:0;", done: "transform:scale(0.95); opacity:0; box-shadow:0 0 0 2px #2F9E6E;", down: "transform:translateY(26px); opacity:0;" };
    const load = {}; openTasks.forEach((x) => { if (x.due != null) load[x.due] = (load[x.due] || 0) + 1; });
    const dayDots = (off) => Array.from({ length: Math.min(load[off] || 0, 4) }, () => ({ style: "width:4px; height:4px; border-radius:50%; background:" + ((load[off] || 0) >= 3 ? "#D8434B" : "rgba(23,22,26,0.3)") + ";" }));

    // calendar
    const HH = 40, H0 = 8, H1 = 21;
    const dayIdx = s.calRange === 7 ? [0, 1, 2, 3, 4, 5, 6] : s.calRange === 3 ? [2, 3, 4] : [2];
    const cols = "52px repeat(" + dayIdx.length + ", minmax(92px,1fr))";
    const nowY = (Component.NOW_H - H0) * HH;
    const calDays = dayIdx.map((di) => {
      const d = this.dateFor(di - 2); const isToday = di === 2; const wk = di >= 5; const past = di < 2;
      const busyH = this.busy(di).reduce((a, [x0, x1]) => a + (x1 - x0), 0) - (di < 5 ? 1 : 0);
      const bands = [];
      if (di < 5) bands.push({ style: "position:absolute; left:0; right:0; top:" + (12 - H0) * HH + "px; height:" + HH + "px; background:repeating-linear-gradient(135deg, rgba(23,22,26,0.035) 0 4px, transparent 4px 8px);" });
      if (isToday) bands.push({ style: "position:absolute; left:0; right:0; top:0; height:" + nowY + "px; background:rgba(23,22,26,0.022);" });
      if (past) bands.push({ style: "position:absolute; inset:0; background:rgba(23,22,26,0.022);" });
      const events = Component.EVENTS[di].map(([a, b, title]) => ({ _s: a, _e: b, title, time: this.hm(a) + "–" + this.hm(b),
        style: "position:absolute; left:3px; right:3px; top:" + ((a - H0) * HH + 1) + "px; height:" + Math.max(16, (b - a) * HH - 2) + "px; border-radius:6px; background:rgba(23,22,26,0.06); color:rgba(23,22,26,0.62); padding:3px 6px; box-sizing:border-box; display:flex; flex-direction:column; gap:1px; overflow:hidden;" }));
      const blocks = s.placements.filter((p) => p.day === di).map((p) => {
        const x = this.T(p.id); if (!x || x.trashed) return null;
        const l = this.L(x.list); const c = l.color; const end = p.start + p.dur / 60;
        const closing = s.closing[x.id]; const done = x.done || !!closing;
        const isPast = past || (isToday && end <= Component.NOW_H);
        const missed = isPast && !done; const working = s.working && s.working.id === x.id; const isNow = isToday && p.start <= Component.NOW_H && Component.NOW_H < end;
        const h = Math.max(18, (p.dur / 60) * HH - 2); const fresh = s.freshBlock === x.id; const foc = s.inspectId === x.id;
        let bg = c + "1F", ring = "inset 0 0 0 1px " + c + "40", fg = "#17161A";
        if (done) { bg = "rgba(47,158,110,0.1)"; ring = "inset 0 0 0 1px rgba(47,158,110,0.28)"; fg = "rgba(23,22,26,0.5)"; }
        else if (missed) { bg = "rgba(255,255,255,0.7)"; ring = "inset 0 0 0 1px rgba(216,67,75,0.35)"; }
        if (working) { bg = c; ring = "0 6px 16px " + c + "55"; fg = "#fff"; }
        if (foc) ring += ", 0 0 0 2px " + A;
        return {
          _s: p.start, _e: end,
          title: x.text, meta: this.hm(p.start) + "–" + this.hm(end) + (missed ? " · carried forward" : working ? (p.conflict ? " · runs into " + p.conflict.split(" at ")[0] : p.orig ? " · extended" : " · working") : p.shifted ? " · rescheduled" : isNow ? " · now" : ""),
          style: "position:absolute; left:3px; right:3px; top:" + ((p.start - H0) * HH + 1) + "px; height:" + h + "px; border-radius:7px; background:" + bg + "; box-shadow:" + ring + "; padding:3px 6px; box-sizing:border-box; display:flex; flex-direction:column; gap:1px; overflow:hidden; cursor:pointer; z-index:2; transition:background 240ms ease, box-shadow 240ms ease;" + (missed ? " border:1px dashed rgba(216,67,75,0.45);" : "") + (fresh || p.shifted ? " animation:rowIn 380ms cubic-bezier(0.2,0.9,0.2,1);" : "") + " transition:top 420ms cubic-bezier(0.2,0.9,0.2,1), height 420ms cubic-bezier(0.2,0.9,0.2,1), background 240ms ease, box-shadow 240ms ease;",
          titleStyle: "font:600 10.5px/1.25 -apple-system,sans-serif; color:" + fg + "; overflow:hidden; " + (done ? "text-decoration:line-through;" : "") + (h < 30 ? " white-space:nowrap; text-overflow:ellipsis;" : ""),
          metaStyle: h < 34 ? "display:none;" : "font:500 9.5px/1.3 -apple-system,sans-serif; color:" + (working ? "rgba(255,255,255,0.8)" : missed ? "#C03A42" : "rgba(23,22,26,0.5)") + "; padding-left:17px;",
          boxStyle: "width:12px; height:12px; flex:none; margin-top:1px; border-radius:50%; box-sizing:border-box; display:flex; align-items:center; justify-content:center; cursor:pointer; transition:background 200ms ease; " + (done ? "background:" + (closing ? A : "#2F9E6E") + "; border:1px solid transparent;" : "border:1.3px solid " + (working ? "#fff" : c) + ";"),
          checkStyle: "font-size:9px; color:#fff; font-variation-settings:'wght' 700; opacity:" + (done ? 1 : 0) + ";",
          onToggle: (e) => { e.stopPropagation(); this.toggle(x.id); },
          onOpen: (e) => { e.stopPropagation(); this.setState({ inspectId: x.id, focusId: null }); },
        };
      }).filter(Boolean);
      const items = [...events, ...blocks].sort((a, b) => a._s - b._s || b._e - a._e);
      let cluster = [], cEnd = -1;
      const flush = () => { const lanes = []; cluster.forEach((it) => { let li = lanes.findIndex((e) => e <= it._s + 1e-6); if (li < 0) { li = lanes.length; lanes.push(0); } lanes[li] = it._e; it._lane = li; }); cluster.forEach((it) => (it._n = lanes.length)); cluster = []; };
      items.forEach((it) => { if (cluster.length && it._s >= cEnd - 1e-6) flush(); cluster.push(it); cEnd = Math.max(cluster.length === 1 ? it._e : cEnd, it._e); });
      flush();
      items.forEach((it) => { if (it._n > 1) it.style = it.style.replace("left:3px; right:3px;", "left:calc(" + ((it._lane / it._n) * 100).toFixed(3) + "% + 2px); width:calc(" + (100 / it._n).toFixed(3) + "% - 4px);"); });
      return {
        dow: isToday ? "Today" : Component.DAYS[d.getDay()], num: d.getDate(), load: busyH > 0 ? busyH.toFixed(busyH % 1 ? 1 : 0) + "h" : "", isToday, bands, events, blocks,
        headStyle: "display:grid; grid-template-columns:auto 1fr; grid-template-rows:auto auto; align-items:end; column-gap:6px; row-gap:4px; padding:9px 9px 8px; min-width:0; border-left:0.5px solid rgba(23,22,26,0.07);" + (isToday ? " background:" + A + "0A;" : ""),
        dowStyle: "grid-column:1 / 3; white-space:nowrap; font:600 10px/1 -apple-system,sans-serif; letter-spacing:0.04em; text-transform:uppercase; color:" + (isToday ? A : "rgba(23,22,26,0.45)") + ";",
        numStyle: "font:500 17px/1 -apple-system,sans-serif; font-variant-numeric:tabular-nums; color:" + (isToday ? A : wk ? "rgba(23,22,26,0.5)" : "#17161A") + ";",
        loadStyle: "justify-self:end; white-space:nowrap; font:500 10px/1 -apple-system,sans-serif; color:rgba(23,22,26,0.36);",
        colStyle: "position:relative; border-left:0.5px solid rgba(23,22,26,0.07); background-image:repeating-linear-gradient(to bottom, transparent 0, transparent " + (HH - 0.5) + "px, rgba(23,22,26,0.06) " + (HH - 0.5) + "px, rgba(23,22,26,0.06) " + HH + "px);" + (isToday ? " background-color:" + A + "06;" : wk ? " background-color:rgba(23,22,26,0.015);" : ""),
      };
    });
    const calHours = []; for (let h = H0 + 1; h < H1; h++) calHours.push({ label: this.hm(h), style: "position:absolute; right:8px; top:" + ((h - H0) * HH - 6) + "px; font:500 10px/1 ui-monospace,Menlo,monospace; color:rgba(23,22,26,0.36);" });
    const upP = s.placements.find((p) => p.day === 2 && p.start <= Component.NOW_H && Component.NOW_H < p.start + p.dur / 60 && this.T(p.id) && this.live(this.T(p.id)));
    const upX = upP && !s.working && !s.closing[upP.id] ? this.T(upP.id) : null;
    const placed = new Set(s.placements.map((p) => p.id));
    const unplanned = openTasks.filter((x) => !placed.has(x.id) && !s.closing[x.id] && ((x.due != null && x.due >= -7 && x.due <= 4) || x.planned)).sort((a, b) => (a.due ?? 99) - (b.due ?? 99));

    // lists gallery
    const mkCard = (l) => {
      const all = s.tasks.filter((x) => x.list === l.id && !x.trashed); const open = all.filter((x) => !x.done); const done = all.length - open.length;
      const dueT = open.filter((x) => x.due != null && x.due <= 0).length;
      return { name: l.name, emoji: l.emoji,
        meta: open.length + " open" + (dueT ? " · " + dueT + " due today" : "") + (done ? " · " + done + " done" : ""),
        peek: open.slice(0, 3).map((x) => ({ text: x.text })),
        coverStyle: "position:relative; height:58px; background:linear-gradient(135deg, " + l.color + "33, " + l.color + "12);",
        barStyle: "height:4px; border-radius:2px; background:" + l.color + "; width:" + (all.length ? Math.round((done / all.length) * 100) : 0) + "%; transition:width 500ms ease;",
        onClick: () => this.go("list:" + l.id) };
    };
    const gallery = ["Personal", "Work"].map((sec) => ({ title: sec, cards: s.lists.filter((l) => l.section === sec).map(mkCard) })).filter((g) => g.cards.length);

    // updates
    const toneMap = { green: ["#2F9E6E", "rgba(47,158,110,0.14)"], red: ["#C03A42", "rgba(216,67,75,0.12)"], accent: [A, A + "1A"], amber: ["#A87A06", "rgba(232,169,23,0.16)"], neutral: ["rgba(23,22,26,0.6)", "rgba(23,22,26,0.07)"] };
    const seen = new Set(); const sessionItems = [];
    s.log.forEach((lg) => { const key = lg.undoIdx + lg.label; if (seen.has(key)) return; seen.add(key); const x = this.T(lg.taskId); const tn = toneMap[lg.tone] || toneMap.neutral;
      sessionItems.push({ icon: lg.icon, label: lg.label, list: x ? this.L(x.list).emoji + " " + this.L(x.list).name : "", when: this.rel(lg.at), canRevert: lg.undoIdx === s.undo.length - 1, onRevert: () => this.undoLast(), iconWrapStyle: "width:26px; height:26px; flex:none; border-radius:8px; display:flex; align-items:center; justify-content:center; color:" + tn[0] + "; background:" + tn[1] + ";" }); });
    const old = [["check_circle", "green", "“Reply to Kasuga about the tatami room” done", "🗻 Weekend in Kyoto", "2 h ago"], ["drive_file_move", "accent", "Moved “Scorecard draft” to Hiring loop", "🎯 Hiring loop", "yesterday"], ["event", "accent", "“Prep board update slides” → Fri 25", "💼 Q3 planning", "yesterday"], ["add_circle", "accent", "Added “Return the library books”", "📥 Inbox", "3 days ago"]].map(([icon, tone, label, list, when]) => { const tn = toneMap[tone]; return { icon, label, list, when, canRevert: false, onRevert: () => {}, iconWrapStyle: "width:26px; height:26px; flex:none; border-radius:8px; display:flex; align-items:center; justify-content:center; color:" + tn[0] + "; background:" + tn[1] + ";" }; });
    const updates = [...(sessionItems.length ? [{ title: "This session", items: sessionItems }] : []), { title: "Earlier", items: old }];

    // activity
    const todayCount = s.tasks.filter((x) => x.done && x.doneAt && x.doneAt > s.now - 18 * H).length;
    const countFor = (i) => { const off = i - 79; if (off > 0) return null; if (off === 0) return todayCount; const rr = Math.abs(Math.sin((i + 1) * 12.9898) * 43758.5453) % 1; const dow = i % 7; return Math.floor(rr * rr * (dow >= 5 ? 4 : 9)); };
    const band = (c) => (c == null ? "transparent" : c === 0 ? "rgba(23,22,26,0.05)" : c === 1 ? A + "33" : c <= 3 ? A + "66" : c <= 6 ? A + "A6" : A);
    const sel = s.actDay ?? 79;
    const first = new Date(2026, 6, 6);
    const heatWeeks = Array.from({ length: 12 }, (_, w) => ({ cells: Array.from({ length: 7 }, (_, dw) => {
      const i = w * 7 + dw; const c = countFor(i); const isSel = i === sel; const isT = i === 79;
      return { label: c ? String(c) : "", onClick: () => c != null && this.setState({ actDay: i }),
        style: "width:30px; height:30px; border-radius:7px; box-sizing:border-box; display:flex; align-items:center; justify-content:center; font:600 10.5px/1 -apple-system,sans-serif; font-variant-numeric:tabular-nums; cursor:" + (c == null ? "default" : "pointer") + "; transition:background 500ms ease, box-shadow 150ms ease; background:" + band(c) + "; color:" + (c >= 4 ? "#fff" : "rgba(23,22,26,0.62)") + "; box-shadow:" + (isSel ? "0 0 0 2px #17161A" : isT ? "0 0 0 1.5px " + A : c == null ? "inset 0 0 0 1px rgba(23,22,26,0.07)" : "none") + ";" };
    }) }));
    const heatMonths = Array.from({ length: 12 }, (_, w) => { const d = new Date(first); d.setDate(d.getDate() + w * 7); const d2 = new Date(d); d2.setDate(d2.getDate() + 6); const show = w === 0 || d2.getMonth() !== d.getMonth() || d.getDate() === 1; const m = d2.getDate() < 7 ? d2.getMonth() : d.getMonth(); return { label: show ? Component.MONTHS[m] : "", style: "width:30px; font:500 10px/1 -apple-system,sans-serif; color:rgba(23,22,26,0.42);" }; });
    let total = 0, streak = 0; for (let i = 0; i <= 79; i++) total += countFor(i) || 0;
    for (let i = 79; i >= 0; i--) { const c = countFor(i); if (c > 0) streak++; else if (i !== 79) break; }
    const selDate = new Date(first); selDate.setDate(selDate.getDate() + sel);
    const selCount = countFor(sel) || 0;
    const heatDayItems = sel === 79
      ? s.tasks.filter((x) => x.done && x.doneAt && x.doneAt > s.now - 18 * H).sort((a, b) => b.doneAt - a.doneAt).map((x) => ({ text: x.text, list: this.L(x.list).emoji, time: this.clock(x.doneAt) }))
      : Array.from({ length: selCount }, (_, k) => { const p = Component.POOL[(sel * 3 + k * 5) % Component.POOL.length]; return { text: p[0], list: p[1], time: this.hm(9 + ((sel + k * 7) % 10) + ((k * 17) % 4) / 4) }; });

    // trash
    const trashed = s.tasks.filter((x) => x.trashed).sort((a, b) => b.trashedAt - a.trashedAt);
    const holdFill = (key) => (s.hold && s.hold.key === key ? "position:absolute; inset:0; background:rgba(216,67,75,0.28); transform-origin:left center; animation:drain 900ms linear reverse forwards;" : "display:none;");

    // settings
    const tog = (key, label, hint) => ({ label, hint, isToggle: true, isValue: false, value: "", onClick: () => this.setState((st) => ({ settings: { ...st.settings, [key]: !st.settings[key] } })),
      trackStyle: "width:34px; height:20px; border-radius:10px; flex:none; position:relative; transition:background 180ms ease; background:" + (s.settings[key] ? A : "rgba(23,22,26,0.16)") + ";",
      knobStyle: "position:absolute; top:2px; left:" + (s.settings[key] ? 16 : 2) + "px; width:16px; height:16px; border-radius:50%; background:#fff; box-shadow:0 1px 3px rgba(0,0,0,0.2); transition:left 200ms cubic-bezier(0.34,1.56,0.64,1);" });
    const val = (label, hint, value) => ({ label, hint, value, isToggle: false, isValue: true, onClick: () => {}, trackStyle: "", knobStyle: "" });
    const settingsGroups = [
      { title: "Tasks", items: [tog("showCompleted", "Show completed tasks", "Lists and Today expand their Completed section by default"), val("Week starts on", "Used by Calendar and Activity", "Monday"), tog("quickAdd", "Quick Add from anywhere", "⌥Space opens capture over any app")] },
      { title: "Motion & feedback", items: [tog("reduce", "Reduce motion", "Keeps state changes, drops the bounce, ring and slides"), val("Undo window", "How long a finished task stays in place", (this.props.undoDwellSeconds ?? 5) + " s")] },
      { title: "Calendar", items: [val("Work hours", "Planning uses these for Work lists", "Mon–Fri 09:00–17:00"), val("Personal hours", "Planning uses these for Personal lists", "Every day 18:00–21:00"), val("Default estimate", "For tasks without their own", "30 min")] },
      { title: "Library", items: [val("iCloud sync", "Last synced a moment ago", "Up to date"), val("Back up library", "Keeps 14 daily snapshots", "Daily")] },
    ];

    // inspector
    const ix = s.inspectId ? this.T(s.inspectId) : null;
    let ins = { listOpts: [], dueOpts: [], prioOpts: [], labelOpts: [], activity: [] };
    if (ix && !ix.trashed) {
      const l = this.L(ix.list); const closing = s.closing[ix.id]; const filled = ix.done || !!closing;
      const pl = s.placements.find((p) => p.id === ix.id); const working = s.working && s.working.id === ix.id;
      const pill = (on) => "display:inline-flex; align-items:center; gap:5px; white-space:nowrap; padding:5px 8px; border-radius:7px; cursor:pointer; font:500 11.5px/1 -apple-system,sans-serif; transition:background 140ms ease, color 140ms ease; " + (on ? "background:" + A + "; color:#fff;" : "background:rgba(23,22,26,0.05); color:rgba(23,22,26,0.66);");
      const dueSet = [["Today", 0], ["Tomorrow", 1], ["Next week", 5], ["None", null]];
      if (ix.due != null && ![0, 1, 5].includes(ix.due)) dueSet.unshift([this.dueLabel(ix.due), ix.due]);
      const pc = { null: "rgba(23,22,26,0.25)", low: "#3A7BD8", medium: "#E8A917", high: "#D8434B" };
      const acts = s.log.filter((lg) => lg.taskId === ix.id).map((lg) => ({ icon: lg.icon, text: lg.label, when: this.rel(lg.at) }));
      acts.push({ icon: "add_circle", text: "Captured in " + (ix.list === "inbox" ? "Inbox" : l.name), when: this.rel(ix.created) });
      const dItems = this.docItems(ix.list); const di = dItems.findIndex((y) => y.id === ix.id); const dd = ix.depth || 0;
      let parent = null;
      if (dd > 0) for (let j = di - 1; j >= 0; j--) { const y = dItems[j]; if (this.isHead(y.kind)) break; if (!y.isBlock && (y.depth || 0) < dd) { parent = y; break; } }
      const subAll = this.subtree(ix.id).filter((y) => !y.isBlock);
      const subDone = subAll.filter((y) => y.done || s.closing[y.id]).length;
      const pSubs = parent ? this.subtree(parent.id).filter((y) => !y.isBlock) : [];
      const inDoc = ix.list !== "inbox";
      ins = {
        hasParent: !!parent, parentText: parent ? parent.text : "",
        parentProgress: parent ? pSubs.filter((y) => y.done || s.closing[y.id]).length + "/" + pSubs.length : "",
        onParent: () => parent && this.setState({ inspectId: parent.id, focusId: parent.id }),
        showSubs: inDoc && dd < 2, subCount: subAll.length ? subDone + "/" + subAll.length : "",
        subBarStyle: "height:3px; border-radius:2px; transition:width 400ms ease; width:" + (subAll.length ? Math.round((subDone / subAll.length) * 100) : 0) + "%; background:" + (subAll.length && subDone === subAll.length ? "#2F9E6E" : A) + ";",
        subs: subAll.map((k) => { const kc = !!s.closing[k.id]; const kf = k.done || kc; const rel = (k.depth || 0) - dd - 1; return {
          text: k.text, onOpen: () => this.setState({ inspectId: k.id, focusId: k.id }),
          onToggle: (e) => { e.stopPropagation(); this.toggle(k.id); },
          style: "display:flex; align-items:center; gap:9px; padding:6px 8px; border-radius:8px; cursor:pointer; transition:opacity 300ms ease;" + (kc ? " opacity:0.6;" : ""),
          indentStyle: "width:" + rel * 18 + "px; flex:none;",
          boxStyle: "width:15px; height:15px; flex:none; border-radius:50%; box-sizing:border-box; display:flex; align-items:center; justify-content:center; cursor:pointer; transition:background 200ms ease; " + (kf ? "background:" + (kc ? A : "#2F9E6E") + "; border:1.5px solid transparent;" : "border:1.5px solid rgba(23,22,26,0.3);"),
          checkStyle: "font-size:10px; color:#fff; font-variation-settings:'wght' 700; opacity:" + (kf ? 1 : 0) + ";",
          textStyle: "font:400 13px/1.3 -apple-system,sans-serif; flex:1; min-width:0; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; color:" + (kf ? "rgba(23,22,26,0.42)" : "#17161A") + ";" + (kf ? " text-decoration:line-through;" : "") }; }),
        onAddSub: () => {
          const id = ix.id; const go = () => { if (s.route !== "list:" + ix.list) this.go("list:" + ix.list); this.setState((st) => this.patchLine(st, id, { collapsed: false })); setTimeout(() => {
            const sub = this.subtree(id); const ref = this.lineOf(id);
            if (sub.length) this.addLine(sub[sub.length - 1].id, { kind: "task" });
            else { this.addLine(id, { kind: "task" }); setTimeout(() => { const ed = this.state.edit; if (ed) this.indent(ed.id, 1); }, 0); }
          }, 30); };
          this.commitEdit(go);
        },
        listEmoji: l.emoji, listName: l.name, text: ix.text, hasNote: !!ix.note, note: ix.note || "",
        titleStyle: "font:600 18px/1.3 -apple-system,sans-serif; color:" + (ix.done ? "rgba(23,22,26,0.45)" : "#17161A") + "; text-wrap:pretty;" + (ix.done ? " text-decoration:line-through;" : ""),
        boxStyle: "width:18px; height:18px; border-radius:50%; box-sizing:border-box; display:flex; align-items:center; justify-content:center; transition:background 200ms ease; " + (filled ? "background:" + (closing ? A : "#2F9E6E") + "; border:1.5px solid transparent;" : "border:1.5px solid " + (pc[ix.prio] && ix.prio ? pc[ix.prio] : "rgba(23,22,26,0.3)") + ";"),
        checkStyle: "font-size:12px; color:#fff; font-variation-settings:'wght' 700; opacity:" + (filled ? 1 : 0) + ";",
        onToggle: () => this.toggle(ix.id),
        listOpts: s.lists.map((o) => ({ emoji: o.emoji, onClick: () => o.id !== ix.list && this.move([ix.id], o.id, true), style: pill(o.id === ix.list) + " font-size:13px; padding:4px 7px;" })),
        dueOpts: dueSet.map(([lab, v]) => ({ label: lab, onClick: () => this.schedule([ix.id], v), style: pill(ix.due === v || (v === null && ix.due == null)) })),
        prioOpts: [["None", null], ["Low", "low"], ["Med", "medium"], ["High", "high"]].map(([lab, v]) => ({ label: lab, onClick: () => this.setPrio(ix.id, v), style: pill((ix.prio || null) === v), dotStyle: "width:6px; height:6px; border-radius:50%; background:" + ((ix.prio || null) === v ? "#fff" : pc[v]) + ";" })),
        labelOpts: Component.LABELS.map((lb) => { const on = (ix.labels || []).includes(lb.id); return { label: "#" + lb.id, onClick: () => this.toggleLabel(ix.id, lb.id), style: "display:inline-flex; padding:5px 8px; border-radius:7px; cursor:pointer; font:600 11px/1 -apple-system,sans-serif; transition:background 140ms ease; " + (on ? "background:" + lb.color + "; color:#fff;" : "background:" + lb.color + "14; color:" + lb.color + ";") }; }),
        onStar: () => this.star([ix.id]), starLabel: ix.star ? "Starred" : "Not starred",
        starStyle: pill(false) + (ix.star ? " background:rgba(232,169,23,0.16); color:#A87A06;" : "") + " justify-self:start;",
        starIconStyle: "font-size:13px; " + (ix.star ? "font-variation-settings:'FILL' 1,'wght' 600;" : ""),
        onPlan: () => this.plan([ix.id]),
        planTrack: "width:34px; height:20px; border-radius:10px; flex:none; position:relative; cursor:pointer; transition:background 180ms ease; background:" + (ix.planned ? A : "rgba(23,22,26,0.16)") + ";",
        planKnob: "position:absolute; top:2px; left:" + (ix.planned ? 16 : 2) + "px; width:16px; height:16px; border-radius:50%; background:#fff; box-shadow:0 1px 3px rgba(0,0,0,0.2); transition:left 200ms cubic-bezier(0.34,1.56,0.64,1);",
        est: (ix.est || 30) + " min", estDown: () => this.setEst(ix.id, -5), estUp: () => this.setEst(ix.id, 5),
        slot: pl ? "In the calendar " + (pl.day === 2 ? "today" : Component.DAYS[this.dateFor(pl.day - 2).getDay()] + " " + this.dateFor(pl.day - 2).getDate()) + ", " + this.hm(pl.start) + "–" + this.hm(pl.start + pl.dur / 60) : "Not in the calendar yet — ⌘K › Find a slot",
        activity: acts,
        onTrash: () => this.trash([ix.id]),
        onStart: () => (working ? null : this.startWork(ix.id)),
        startIcon: working ? "timer" : "play_arrow", startLabel: working ? "Working…" : "Start working",
        startStyle: "display:flex; align-items:center; gap:5px; padding:8px 12px; border-radius:8px; cursor:pointer; font:600 12px/1 -apple-system,sans-serif; " + (working ? "background:rgba(23,22,26,0.06); color:rgba(23,22,26,0.55);" : "background:" + A + "; color:#fff;"),
      };
    }

    // capture
    const cap = s.capture;
    const capParsed = cap ? this.parse(cap.text) : { segments: [], marks: [] };
    const segTone = { date: A, repeat: A, time: A, est: A, label: "#12807F", priority: "#C03A42" };
    const capSegments = capParsed.segments.map((seg) => ({ text: seg.text, style: "white-space:pre; " + (seg.kind ? "color:" + segTone[seg.kind] + "; background:" + segTone[seg.kind] + "1A; border-radius:5px; box-shadow:inset 0 -1.5px 0 " + segTone[seg.kind] + "55;" : "color:#17161A;") }));
    const capChips = [];
    let hasDate = false;
    capParsed.marks.forEach((m) => {
      if (m.kind === "date") { const off = this.resolve(m.raw); if (off != null) { hasDate = true; capChips.push(this.chip(this.dueLabel(off) + " · " + this.relLabel(off), { icon: "today", tone: "accent", fresh: true })); } }
      if (m.kind === "time") capChips.push(this.chip(this.fmtTime(m.raw) || m.raw, { icon: "notifications", tone: "accent", fresh: true }));
      if (m.kind === "repeat") capChips.push(this.chip(m.raw, { icon: "repeat", tone: "accent", fresh: true }));
      if (m.kind === "label") capChips.push(this.chip(m.raw.slice(1), { color: this.labelColor(m.raw.slice(1).toLowerCase()), fresh: true }));
      if (m.kind === "priority") capChips.push(this.chip("High", { icon: "priority_high", tone: "over", fresh: true }));
      if (m.kind === "est") capChips.push(this.chip(m.raw.slice(1) + " estimate", { icon: "timer", tone: "accent", fresh: true }));
    });
    if (cap && cap.today && !hasDate) capChips.unshift(this.chip("Today", { icon: "today", tone: "accent" }));
    const capDests = s.lists.map((l) => ({ emoji: l.emoji, name: l.name, onClick: () => { this.setState((st) => ({ capture: { ...st.capture, dest: l.id } })); setTimeout(() => this.capEl && this.capEl.focus(), 10); },
      style: "display:inline-flex; align-items:center; gap:4px; padding:5px 8px; border-radius:7px; cursor:pointer; font:500 11.5px/1 -apple-system,sans-serif; white-space:nowrap; transition:background 140ms ease; " + (cap && cap.dest === l.id ? "background:" + A + "; color:#fff;" : "background:rgba(23,22,26,0.05); color:rgba(23,22,26,0.66);") }));

    // search
    const hitList = this.hits(); const sIdx = s.search ? Math.min(s.search.idx, Math.max(0, hitList.length - 1)) : 0;
    const searchHits = hitList.map((h, i) => {
      const on = i === sIdx; const has = h.i >= 0;
      return { icon: h.icon, pre: has ? h.text.slice(0, h.i) : h.text, mark: has ? h.text.slice(h.i, h.i + h.q.length) : "", post: has ? h.text.slice(h.i + h.q.length) : "", sub: h.sub,
        style: "display:flex; align-items:center; gap:11px; padding:9px 10px; border-radius:8px; cursor:pointer; color:#17161A; " + (on ? "background:" + A + "14; box-shadow:inset 0 0 0 1px " + A + "33;" : ""),
        iconStyle: "font-size:16px; color:" + (on ? A : "rgba(23,22,26,0.4)") + ";",
        markStyle: "background:" + A + "26; border-radius:3px; color:" + A + ";",
        subStyle: "font:500 11px/1 -apple-system,sans-serif; color:rgba(23,22,26,0.45);",
        onRun: () => h.run(), onHover: () => this.setState((st) => (st.search ? { search: { ...st.search, idx: i } } : {})) };
    });

    // palette
    const cmds = s.palette ? this.commands() : [];
    const pIdx = s.palette ? Math.min(s.palette.idx, Math.max(0, cmds.length - 1)) : 0;
    const paletteItems = cmds.map((c, i) => ({ icon: c.icon, label: c.label, key: c.key,
      iconStyle: "font-size:16px; color:" + (i === pIdx ? "#fff" : c.tone || "rgba(23,22,26,0.5)") + ";",
      style: "display:flex; align-items:center; gap:10px; padding:9px 10px; border-radius:8px; cursor:pointer; " + (i === pIdx ? "background:" + A + "; color:#fff;" : "color:#17161A;"),
      onRun: () => this.runCmd(c), onHover: () => this.setState((st) => (st.palette ? { palette: { ...st.palette, idx: i } } : {})) }));
    const tgt = this.targets();

    // sidebar
    const todayCountBadge = openTasks.filter((x) => (x.due != null && x.due <= 0) || x.planned || x.star).length;
    const navDef = [["inbox", "inbox", "Inbox", q.length, "#3A7BD8"], ["today", "wb_sunny", "Today", todayCountBadge, "#E0861F"], ["calendar", "calendar_month", "Calendar", "", A], ["tasks", "checklist", "Tasks", "", "#2F9E6E"], ["lists", "layers", "Lists", "", "#5B5BD6"], ["activity", "grid_view", "Activity", "", A]];
    const moreDef = [];
    const mkNav = ([id, icon, label, count, color]) => { const on = r === id; const pulse = id === "inbox" && s.pulseList === "inbox";
      return { icon, label, count: count ? String(count) : "", onClick: () => this.go(id),
        style: "display:flex; align-items:center; gap:9px; height:29px; padding:0 8px; border-radius:8px; cursor:pointer; transition:background 300ms ease, box-shadow 300ms ease; " + (on ? "background:#FCFBFA; box-shadow:0 1px 2px rgba(23,22,26,0.08), 0 0 0 0.5px rgba(23,22,26,0.06);" : pulse ? "background:" + A + "1F;" : ""),
        iconStyle: "font-size:16px; width:16px; color:" + (on ? color : "rgba(23,22,26,0.55)") + "; " + (on ? "font-variation-settings:'FILL' 1,'wght' 500;" : ""),
        labelStyle: "font:" + (on ? 600 : 500) + " 13px/1 -apple-system,sans-serif; color:" + (on ? "#17161A" : "rgba(23,22,26,0.66)") + ";",
        countStyle: "font:" + (pulse ? 700 : 500) + " 11px/1 -apple-system,sans-serif; color:" + (pulse ? A : "rgba(23,22,26,0.38)") + "; font-variant-numeric:tabular-nums; display:inline-block;" + (pulse ? " animation:bump 420ms cubic-bezier(0.34,1.56,0.64,1);" : "") };
    };
    const sideSections = ["Personal", "Work"].map((sec) => ({ title: sec, open: !s.collapsed["sec-" + sec],
      onToggle: () => this.setState((st) => ({ collapsed: { ...st.collapsed, ["sec-" + sec]: !st.collapsed["sec-" + sec] } })),
      chevStyle: "font-size:12px; color:rgba(23,22,26,0.3); transition:transform 160ms ease; transform:rotate(" + (s.collapsed["sec-" + sec] ? 0 : 90) + "deg);",
      lists: s.lists.filter((l) => l.section === sec).map((l) => { const on = r === "list:" + l.id; const pulse = s.pulseList === l.id; const n = openTasks.filter((x) => x.list === l.id).length;
        return { emoji: l.emoji, name: l.name, count: n ? String(n) : "", onClick: () => this.go("list:" + l.id),
          style: "display:flex; align-items:center; gap:9px; height:29px; padding:0 8px; border-radius:8px; cursor:pointer; transition:background 300ms ease, box-shadow 300ms ease; " + (on ? "background:#FCFBFA; box-shadow:0 1px 2px rgba(23,22,26,0.08), 0 0 0 0.5px rgba(23,22,26,0.06);" : pulse ? "background:" + A + "1F; box-shadow:0 0 0 1px " + A + "40;" : ""),
          nameStyle: "font:" + (on ? 600 : 500) + " 13px/1 -apple-system,sans-serif; color:" + (on ? "#17161A" : "rgba(23,22,26,0.66)") + "; white-space:nowrap; overflow:hidden; text-overflow:ellipsis;",
          countStyle: "font:" + (pulse ? 700 : 500) + " 11px/1 -apple-system,sans-serif; color:" + (pulse ? A : "rgba(23,22,26,0.36)") + "; font-variant-numeric:tabular-nums; display:inline-block;" + (pulse ? " animation:bump 420ms cubic-bezier(0.34,1.56,0.64,1);" : "") }; }) }));
    const sideLabels = Component.LABELS.map((lb) => { const on = r === "label:" + lb.id; const n = openTasks.filter((x) => (x.labels || []).includes(lb.id)).length;
      return { name: lb.id, count: n ? String(n) : "", onClick: () => this.go("label:" + lb.id),
        style: "display:flex; align-items:center; gap:9px; height:27px; padding:0 8px; border-radius:8px; cursor:pointer; " + (on ? "background:#FCFBFA; box-shadow:0 1px 2px rgba(23,22,26,0.08), 0 0 0 0.5px rgba(23,22,26,0.06);" : ""),
        dotStyle: "width:8px; height:8px; border-radius:3px; margin:0 4px; background:" + lb.color + ";",
        nameStyle: "font:" + (on ? 600 : 500) + " 12.5px/1 -apple-system,sans-serif; color:" + (on ? "#17161A" : "rgba(23,22,26,0.62)") + ";",
        countStyle: "font:500 11px/1 -apple-system,sans-serif; color:rgba(23,22,26,0.36);" }; });

    const crumb = isList ? (curList.section || "") + " › " + curList.name : isLabel ? "Labels › #" + r.slice(6) : hdr[2];
    const wide = ["calendar", "lists", "activity"].includes(r);
    const w = s.working; const wx = w ? this.T(w.id) : null; const wp = w ? s.placements.find((p) => p.id === w.id && p.day === 2) : null; const el = this.elapsed(); const estMs = ((wx && wx.est) || 30) * 60000;
    const mmss = (t) => { const sec = Math.floor(t / 1000); const hh = Math.floor(sec / 3600), mm = Math.floor((sec % 3600) / 60), ss = sec % 60; return (hh ? hh + ":" + String(mm).padStart(2, "0") : String(mm).padStart(2, "0")) + ":" + String(ss).padStart(2, "0"); };
    const trayTone = s.tray ? (toneMap[s.tray.tone] || toneMap.neutral) : toneMap.neutral;
    const selIds = Object.keys(s.selected).filter((id) => this.T(id));

    return {
      // sidebar
      openSearch: () => this.openSearch(), navItems: navDef.map(mkNav), moreItems: moreDef.map(mkNav),
      moreOpen: s.moreOpen || ["updates", "activity", "trash"].includes(r), toggleMore: () => this.setState((st) => ({ moreOpen: !st.moreOpen })),
      moreChevStyle: "font-size:13px; color:rgba(23,22,26,0.36); transition:transform 180ms ease; transform:rotate(" + (s.moreOpen || ["updates", "activity", "trash"].includes(r) ? 90 : 0) + "deg);",
      sideSections, sideLabels,
      labelsOpen: !s.collapsed["sec-labels"],
      toggleLabels: () => this.setState((st) => ({ collapsed: { ...st.collapsed, "sec-labels": !st.collapsed["sec-labels"] } })),
      labelsChevStyle: "font-size:12px; color:rgba(23,22,26,0.3); transition:transform 160ms ease; transform:rotate(" + (s.collapsed["sec-labels"] ? 0 : 90) + "deg);",
      newList: () => { const id = "u" + ++this.seq; this.setState((st) => ({ lists: [...st.lists, { id, emoji: "📝", name: "Untitled list", color: A, section: "Personal", kind: "personal" }] })); this.go("list:" + id); this.showTray({ text: "Created “Untitled list” in Personal", icon: "add", tone: "accent", undo: false }); },
      goSettings: () => this.go("settings"), goTrash: () => this.go("trash"),
      trashCount: String(trashed.length), trashHasCount: trashed.length > 0,
      trashBtnStyle: "display:flex; align-items:center; gap:4px; padding:6px; border-radius:7px; cursor:pointer; color:" + (r === "trash" ? "#17161A" : "rgba(23,22,26,0.5)") + "; " + (r === "trash" ? "background:rgba(23,22,26,0.07);" : ""),
      tfQ: s.tf.q || "", tfCount: extra.tfCount != null && s.tf.q ? String(extra.tfCount) : "",
      onTfQ: (e) => { const v = e.target.value; this.setState((st) => ({ tf: { ...st.tf, q: v } })); },
      onTfQKey: (e) => { if (e.key === "Escape") { e.preventDefault(); this.setState((st) => ({ tf: { ...st.tf, q: "" } })); e.target.blur(); } },
      ...this.tfVals(), ...this.tqVals(extra, r === "tasks"),
      settingsBtnStyle: "display:flex; padding:6px; border-radius:7px; cursor:pointer; color:" + (r === "settings" ? "#17161A" : "rgba(23,22,26,0.5)") + "; " + (r === "settings" ? "background:rgba(23,22,26,0.07);" : ""),
      // toolbar
      goBack: () => { const p = s.prev; if (!p.length) return; this.setState({ route: p[p.length - 1], prev: p.slice(0, -1), focusId: null, selected: {}, screenFlip: !s.screenFlip }); },
      backStyle: "display:flex; padding:3px; border-radius:6px; cursor:" + (s.prev.length ? "pointer" : "default") + "; color:" + (s.prev.length ? "rgba(23,22,26,0.6)" : "rgba(23,22,26,0.2)") + ";",
      crumb, canUndo: s.undo.length > 0, undoLabel: s.undo.length ? s.undo[s.undo.length - 1].label : "", undoLast: () => this.undoLast(),
      openPalette: (e) => { if (e) e.stopPropagation(); this.openPalette(); }, openCapture: (e) => { if (e) e.stopPropagation(); this.openCapture(); },
      captureBtnStyle: "display:flex; align-items:center; gap:5px; padding:5px 10px; border-radius:8px; background:" + A + "; color:#fff; cursor:pointer; box-shadow:0 1px 2px " + A + "66;",
      // working
      isWorking: !!wx, workTitle: wx ? wx.text : "", workElapsed: mmss(el), workState: w && w.paused ? "Paused" : "Working",
      workDotStyle: "width:7px; height:7px; flex:none; border-radius:50%; background:" + (w && w.paused ? "#E8A917" : A) + ";" + (w && !w.paused ? " animation:breathe 1.6s ease-in-out infinite;" : ""),
      workBarStyle: "height:2px; border-radius:2px; background:" + (el > estMs ? "#E8A917" : A) + "; width:" + Math.min(100, Math.round((el / estMs) * 100)) + "%; transition:width 900ms linear, background 300ms ease;",
      workElapsedStyle: "font:600 12px/1 ui-monospace,Menlo,monospace; font-variant-numeric:tabular-nums; flex:none; color:" + (el > estMs ? "#A87A06" : A) + ";",
      workHasExt: !!wp && !!(wp.orig || wp.conflict), workExt: wp && wp.conflict ? wp.conflict : wp && wp.orig ? "+" + (wp.dur - wp.orig) + "m" : "",
      workExtStyle: "font:600 10px/1 -apple-system,sans-serif; padding:3px 6px; border-radius:5px; white-space:nowrap; flex:none; animation:chipIn 280ms cubic-bezier(0.2,0.9,0.2,1); " + (wp && wp.conflict ? "color:#C03A42; background:rgba(216,67,75,0.12);" : "color:#A87A06; background:rgba(232,169,23,0.16);"),
      actionsLabelStyle: w ? "display:none;" : "font:500 11.5px/1 -apple-system,sans-serif;",
      actionsKeyStyle: w ? "display:none;" : "font:500 10px/1 ui-monospace,Menlo,monospace; opacity:0.6;",
      newLabelStyle: w ? "display:none;" : "font:600 11.5px/1 -apple-system,sans-serif;",
      newKeyStyle: w ? "display:none;" : "font:500 10px/1 ui-monospace,Menlo,monospace; opacity:0.65;",
      undoLabelStyle: w ? "display:none;" : "font:500 11.5px/1 -apple-system,sans-serif; max-width:180px; white-space:nowrap; overflow:hidden; text-overflow:ellipsis;",
      workOf: "of " + ((wx && wx.est) || 30) + " min",
      workPauseIcon: w && w.paused ? "play_arrow" : "pause", workPauseLabel: w && w.paused ? "Resume" : "Pause",
      workPause: () => this.setState((st) => { const x = st.working; if (!x) return {}; return x.paused ? { working: { ...x, paused: false, start: Date.now() } } : { working: { ...x, paused: true, acc: x.acc + (Date.now() - x.start) } }; }),
      workDone: () => { if (w) this.complete([w.id]); this.setState({ working: null }); },
      workStop: () => { this.setState({ working: null }); this.showTray({ text: "Stopped — " + mmss(el) + " recorded", icon: "timer", tone: "neutral", undo: false }); },
      // content
      onBackgroundClick: () => this.setState({ focusId: null, inspectId: null, tfMenu: null }), stop: (e) => e.stopPropagation(),
      contentStyle: (wide ? "max-width:none;" : "max-width:880px;") + " animation:" + (s.screenFlip ? "screenIn" : "screenIn2") + " " + Math.round(260 * ms) + "ms cubic-bezier(0.2,0.9,0.2,1);",
      hdrTileStyle: "width:44px; height:44px; flex:none; border-radius:12px; background:" + hdr[1] + "1F; color:" + hdr[1] + "; display:flex; align-items:center; justify-content:center;",
      hdrIsEmoji: !hdr[0], hdrEmoji: curList ? curList.emoji : "", hdrIsIcon: !!hdr[0], hdrIcon: hdr[0] || "",
      titleStyle: (this.props.serifTitles ?? true) ? "font:400 34px/1.05 'Instrument Serif',Georgia,serif; color:#17161A;" : "font:700 27px/1.1 -apple-system,sans-serif; color:#17161A; letter-spacing:-0.01em;",
      hdrTitle: hdr[2], hdrSub: hdr[3],
      hdrHasProgress: !!(prog && prog[1]), hdrProgressText: prog ? prog[0] + " of " + prog[1] + " done" : "",
      hdrProgressFill: "height:4px; border-radius:3px; width:" + pct + "%; background:" + (pct === 100 ? "#2F9E6E" : A) + "; transition:width 560ms cubic-bezier(0.2,0.8,0.2,1);",
      isInbox: r === "inbox", isTasks: r === "tasks", isCalendar: r === "calendar", isLists: r === "lists", isUpdates: r === "updates", isActivity: r === "activity", isTrash: r === "trash", isSettings: r === "settings",
      // triage
      triageHas: !!tx, triageEmpty: r === "inbox" && !tx,
      triageCardStyle: "border-radius:16px; background:#fff; box-shadow:0 0 0 0.5px rgba(23,22,26,0.12), 0 14px 40px rgba(40,30,20,0.09); overflow:hidden; transition:transform " + Math.round(230 * ms) + "ms cubic-bezier(0.4,0,0.2,1), opacity " + Math.round(230 * ms) + "ms ease, box-shadow 200ms ease; " + (tr.exit ? exitMap[tr.exit] : "animation:" + (tr.flip ? "liftIn" : "liftIn2") + " " + Math.round(320 * ms) + "ms cubic-bezier(0.2,0.9,0.2,1);"),
      triageDots: Array.from({ length: totalQ }, (_, i) => ({ style: "height:5px; border-radius:3px; transition:all 300ms ease; " + (i < s.reviewed ? "width:5px; background:#3A7BD8;" : i === s.reviewed ? "width:16px; background:#3A7BD8;" : "width:5px; background:rgba(23,22,26,0.12);") })),
      triageCountText: q.length + " to go", triageAge: tx ? "Captured " + this.rel(tx.created) : "", triageTitle: tx ? tx.text : "",
      triageChips: tx ? [...(tx.due != null ? [this.chip(this.dueLabel(tx.due), { icon: "today", tone: tx.due <= 0 ? "accent" : "neutral" })] : []), ...(tx.prio ? [this.chip(tx.prio === "high" ? "High priority" : tx.prio, { icon: "flag", tone: "over" })] : [])] : [],
      triageLists: this.triageLists().map((l, i) => ({ key: String(i + 1), emoji: l.emoji, name: l.name, count: openTasks.filter((x) => x.list === l.id).length, onClick: () => this.triage("move", l.id) })),
      triageDays: [0, 1, 2, 3, 4, 5, 6, 7].map((off) => { const d = this.dateFor(off); return { top: off === 0 ? "Today" : off === 1 ? "Tmrw" : Component.DAYS[d.getDay()], num: d.getDate(), dots: dayDots(off), onClick: () => this.triage("schedule", off) }; }),
      triageDone: () => this.triage("done"), triageTrash: () => this.triage("trash"), triageKeep: () => this.triage("keep"),
      triageOpen: () => tx && this.setState({ inspectId: tx.id }),
      triageSummary: s.reviewed + " reviewed this session. Tasks you kept or scheduled stay in Inbox until you file them.",
      triageAgain: () => this.setState({ kept: {}, reviewed: 0 }),
      // tasks filters
      tfStatus: [["open", "Open"], ["done", "Completed"], ["all", "All"]].map(([v, lab]) => ({ label: lab, onClick: () => this.setState((st) => ({ tf: { ...st.tf, status: v } })), style: "padding:6px 10px; border-radius:7px; cursor:pointer; font:500 12px/1 -apple-system,sans-serif; transition:background 140ms ease; " + (s.tf.status === v ? "background:#fff; color:#17161A; box-shadow:0 1px 2px rgba(23,22,26,0.12);" : "color:rgba(23,22,26,0.55);") })),
      tfGroup: [["list", "List"], ["due", "Due date"], ["none", "None"]].map(([v, lab]) => ({ label: lab, onClick: () => this.setState((st) => ({ tf: { ...st.tf, group: v } })), style: "padding:6px 10px; border-radius:7px; cursor:pointer; font:500 12px/1 -apple-system,sans-serif; transition:background 140ms ease; " + (s.tf.group === v ? "background:#fff; color:#17161A; box-shadow:0 1px 2px rgba(23,22,26,0.12);" : "color:rgba(23,22,26,0.55);") })),
      tfLists: s.lists.map((l) => { const on = !!s.tf.lists[l.id]; return { emoji: l.emoji, label: l.name, onClick: () => this.setState((st) => ({ tf: { ...st.tf, lists: { ...st.tf.lists, [l.id]: !st.tf.lists[l.id] } } })), style: "display:inline-flex; align-items:center; gap:5px; padding:5px 8px; border-radius:7px; cursor:pointer; font:500 11.5px/1 -apple-system,sans-serif; transition:background 140ms ease; " + (on ? "background:" + A + "; color:#fff;" : "background:rgba(23,22,26,0.05); color:rgba(23,22,26,0.62);") }; }),
      tfDirty: s.tf.status !== "open" || s.tf.group !== "list" || Object.values(s.tf.lists).some(Boolean) || !!s.tf.q,
      tfReset: () => this.setState({ tf: { status: "open", group: "list", lists: {}, q: "", tq: "" }, tfMenu: null }),
      // groups
      showGroups, groups, groupsWrapStyle: "padding-top:" + (r === "inbox" ? 10 : 6) + "px;",
      todayClear: r === "today" && !!extra.todayClear, todayClearText: (prog ? prog[0] : 0) + " finished today. Nothing is overdue, due, planned or starred.",
      goCalendar: () => this.go("calendar"),
      isDoc: isList, doc,
      docAdd: (e) => { e.stopPropagation(); const lid = curList.id; this.commitEdit(() => this.addLine(null, { list: lid, kind: "task" })); },
      docAddText: doc.length ? "Add to " + (curList ? curList.name : "") : "Start typing — # for a heading, / to turn a line into anything",
      showAddRow: r === "today" || isLabel, addRowText: isList ? "Add to " + curList.name : r === "today" ? "Add a task for today" : "Add a task",
      // calendar
      calRanges: [[1, "Day"], [3, "3 days"], [7, "Week"]].map(([v, lab]) => ({ label: lab, onClick: () => this.setState({ calRange: v }), style: "padding:6px 10px; border-radius:7px; cursor:pointer; font:500 12px/1 -apple-system,sans-serif; " + (s.calRange === v ? "background:#fff; color:#17161A; box-shadow:0 1px 2px rgba(23,22,26,0.12);" : "color:rgba(23,22,26,0.55);") })),
      calHeadGrid: "display:grid; grid-template-columns:" + cols + "; border-bottom:0.5px solid rgba(23,22,26,0.09); min-width:" + (52 + dayIdx.length * 92) + "px;",
      calBodyGrid: "display:grid; grid-template-columns:" + cols + "; position:relative; height:" + (H1 - H0) * HH + "px; min-width:" + (52 + dayIdx.length * 92) + "px;",
      calDays, calHours,
      calNowLabelStyle: "position:absolute; right:4px; top:" + (nowY - 7) + "px; font:600 9.5px/1 ui-monospace,Menlo,monospace; color:#fff; background:#D8434B; padding:2px 4px; border-radius:4px; z-index:6;",
      calNowLineStyle: "position:absolute; left:0; right:0; top:" + nowY + "px; height:2px; background:#D8434B; z-index:5; pointer-events:none;",
      upNextShow: !!upX, upNextTitle: upX ? upX.text : "", upNextTime: upP ? this.hm(upP.start) + "–" + this.hm(upP.start + upP.dur / 60) : "",
      upNextStart: () => upX && this.startWork(upX.id),
      unplanned: unplanned.map((x) => ({ emoji: this.L(x.list).emoji, text: x.text, due: x.due != null ? this.dueLabel(x.due) : "Picked for today", est: (x.est || 30) + " min",
        dueStyle: "font:600 10.5px/1 -apple-system,sans-serif; padding:3px 6px; border-radius:5px; " + (x.due != null && x.due < 0 ? "color:#C03A42; background:rgba(216,67,75,0.12);" : "color:" + A + "; background:" + A + "14;"),
        onPlan: () => this.fit(x.id) })),
      unplannedCount: String(unplanned.length), unplannedEmpty: unplanned.length === 0,
      // lists / updates / activity
      gallery, updates,
      heatWeeks, heatMonths, heatDow: ["Mon", "", "Wed", "", "Fri", "", "Sun"].map((label) => ({ label })),
      heatLegend: [[0, "0"], [1, "1"], [2, "2–3"], [5, "4–6"], [8, "7+"]].map(([c, label]) => ({ label, style: "min-width:22px; height:16px; padding:0 4px; box-sizing:border-box; border-radius:4px; display:inline-flex; align-items:center; justify-content:center; font:600 9px/1 -apple-system,sans-serif; background:" + band(c) + "; color:" + (c >= 4 ? "#fff" : "rgba(23,22,26,0.55)") + ";" })),
      heatSummary: total + " completions · " + streak + "-day streak",
      heatDayTitle: sel === 79 ? "Today" : Component.WDAYS[selDate.getDay()] + " " + selDate.getDate() + " " + Component.MONTHS_L[selDate.getMonth()],
      heatDaySub: selCount === 0 ? "No completions recorded" : selCount + (selCount === 1 ? " task" : " tasks") + " completed",
      heatDayItems,
      // trash
      trashHas: trashed.length > 0, trashEmpty: trashed.length === 0,
      holdAllStart: () => this.holdStart("all", trashed.map((x) => x.id)), holdEnd: () => this.holdEnd(), holdAllFill: holdFill("all"),
      trashRows: trashed.map((x) => { const l = this.L(x.list); const fly = s.flying[x.id]; return { icon: "radio_button_unchecked", text: x.text, meta: "From " + l.emoji + " " + l.name + " · deleted " + this.rel(x.trashedAt),
        wrapStyle: "display:flex; align-items:center; gap:11px; padding:10px 12px; border-radius:10px; transition:opacity 300ms ease, transform 300ms cubic-bezier(0.4,0,0.2,1);" + (fly ? " opacity:0; transform:translateX(-56px);" : "") + (x.restored ? "" : ""),
        onRestore: () => this.restore(x.id), onHoldStart: () => this.holdStart(x.id, [x.id]), holdFill: holdFill(x.id), holdLabel: s.hold && s.hold.key === x.id ? "Keep holding…" : "Hold to erase" }; }),
      settingsGroups,
      // inspector
      insHas: !!(ix && !ix.trashed), ins, closeInspector: () => this.setState({ inspectId: null }),
      insStyle: "position:absolute; top:52px; right:0; bottom:0; width:360px; background:#F7F5F2; border-left:0.5px solid rgba(23,22,26,0.1); box-shadow:-14px 0 34px rgba(40,30,20," + (ix ? 0.1 : 0) + "); display:flex; flex-direction:column; z-index:36; transition:transform " + Math.round(300 * ms) + "ms cubic-bezier(0.2,0.9,0.2,1), box-shadow 300ms ease; transform:translateX(" + (ix && !ix.trashed ? 0 : 104) + "%);",
      // selection bar
      barVisible: selIds.length > 0 && !s.palette, selectedCount: selIds.length,
      barCountStyle: "min-width:22px; height:22px; padding:0 6px; box-sizing:border-box; border-radius:7px; background:" + A + "; display:inline-flex; align-items:center; justify-content:center; font:700 12px/1 -apple-system,sans-serif;",
      barDone: () => this.act((x) => this.complete(x)), barToday: () => this.act((x) => this.schedule(x, 0)), barTomorrow: () => this.act((x) => this.schedule(x, 1)),
      barPlan: () => this.act((x) => this.plan(x)), barStar: () => this.act((x) => this.star(x)), barTrash: () => this.act((x) => this.trash(x)),
      clearSelection: () => this.setState({ selected: {} }),
      // tray
      trayVisible: !!s.tray && selIds.length === 0, trayText: s.tray ? s.tray.text : "", trayIcon: s.tray ? s.tray.icon : "",
      trayIconStyle: "font-size:15px; color:" + (s.tray && s.tray.tone === "green" ? "#6FD3A4" : s.tray && s.tray.tone === "red" ? "#FF8A8A" : s.tray && s.tray.tone === "amber" ? "#F2C14E" : "#C9AEFF") + ";",
      trayHasUndo: !!(s.tray && s.tray.undo), trayHasGo: !!(s.tray && s.tray.go), trayGoLabel: s.tray && s.tray.go ? s.tray.go.label : "",
      trayGo: () => { if (s.tray && s.tray.go) { this.go(s.tray.go.route); this.setState({ tray: null }); } },
      trayDrainStyle: "position:absolute; left:0; bottom:0; height:2px; width:100%; background:" + trayTone[0] + "; transform-origin:left center; animation:" + (s.tray && s.tray.flip ? "drainB " : "drain ") + dwell + "ms linear forwards;",
      // capture
      captureOpen: !!cap, closeCapture: () => this.setState({ capture: null }),
      capText: cap ? cap.text : "", capSegments, capChips, capDests, capRef: (el) => { this.capEl = el; },
      capGhost: cap && !cap.text ? "Pay deposit friday 6pm #travel ~15m" : "",
      onCapChange: (e) => { const v = e.target.value; this.setState((st) => ({ capture: { ...st.capture, text: v } })); },
      onCapKey: (e) => {
        if (e.key === "Enter") { e.preventDefault(); this.createFromCapture(e.shiftKey); }
        else if (e.key === "Tab") { e.preventDefault(); const ids = s.lists.map((l) => l.id); const i = ids.indexOf(cap.dest); this.setState((st) => ({ capture: { ...st.capture, dest: ids[(i + (e.shiftKey ? -1 : 1) + ids.length) % ids.length] } })); }
        else if (e.key === "Escape") { e.preventDefault(); this.setState({ capture: null }); }
      },
      // search
      searchOpen: !!s.search, closeSearch: () => this.setState({ search: null }), searchQ: s.search ? s.search.q : "", searchRef: (el) => { this.searchEl = el; },
      onSearchChange: (e) => { const v = e.target.value; this.setState((st) => ({ search: { ...st.search, q: v, idx: 0 } })); },
      onSearchKey: (e) => {
        if (e.key === "ArrowDown") { e.preventDefault(); this.setState((st) => ({ search: { ...st.search, idx: Math.min(hitList.length - 1, sIdx + 1) } })); }
        else if (e.key === "ArrowUp") { e.preventDefault(); this.setState((st) => ({ search: { ...st.search, idx: Math.max(0, sIdx - 1) } })); }
        else if (e.key === "Enter") { e.preventDefault(); if (hitList[sIdx]) hitList[sIdx].run(); }
        else if (e.key === "Escape") { e.preventDefault(); this.setState({ search: null }); }
      },
      toggleSearchDone: () => this.setState((st) => ({ search: { ...st.search, done: !st.search.done } })),
      searchDoneStyle: "padding:5px 8px; border-radius:6px; cursor:pointer; font:600 10.5px/1 -apple-system,sans-serif; white-space:nowrap; " + (s.search && s.search.done ? "background:" + A + "; color:#fff;" : "background:rgba(23,22,26,0.06); color:rgba(23,22,26,0.55);"),
      searchHits, searchFooter: !s.search || !s.search.q.trim() ? "Search tasks, notes and lists" : hitList.length ? hitList.length + " results · ↑↓ choose · ↩ open" : "Nothing matches “" + s.search.q + "”" + (s.search.done ? "" : " — try including completed"),
      // palette
      paletteOpen: !!s.palette, paletteQ: s.palette ? s.palette.q : "", paletteItems, paletteRef: (el) => { this.palEl = el; },
      paletteTarget: tgt.length ? (tgt.length === 1 ? this.short((this.T(tgt[0]) || {}).text || "") : tgt.length + " selected") : "No task focused",
      paletteTargetStyle: "font:600 10.5px/1 -apple-system,sans-serif; padding:5px 8px; border-radius:6px; white-space:nowrap; max-width:200px; overflow:hidden; text-overflow:ellipsis; " + (tgt.length ? "color:" + A + "; background:" + A + "1A;" : "color:rgba(23,22,26,0.45); background:rgba(23,22,26,0.06);"),
      onPaletteChange: (e) => { const v = e.target.value; this.setState({ palette: { q: v, idx: 0 } }); },
      onPaletteKey: (e) => {
        if (e.key === "ArrowDown") { e.preventDefault(); this.setState((st) => ({ palette: { ...st.palette, idx: Math.min(cmds.length - 1, pIdx + 1) } })); }
        else if (e.key === "ArrowUp") { e.preventDefault(); this.setState((st) => ({ palette: { ...st.palette, idx: Math.max(0, pIdx - 1) } })); }
        else if (e.key === "Enter") { e.preventDefault(); if (cmds[pIdx]) this.runCmd(cmds[pIdx]); }
        else if (e.key === "Escape") { e.preventDefault(); this.setState({ palette: null }); }
      },
      closePalette: () => this.setState({ palette: null }),
    };
  }
}
