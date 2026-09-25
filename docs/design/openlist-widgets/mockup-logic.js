
class Component extends DCLogic {
  static LISTS = { inbox: ["📥", "Inbox", "#3A7BD8"], kyoto: ["🗻", "Weekend in Kyoto", "#7C4DF0"], home: ["🏡", "Home", "#2F9E6E"], reading: ["📚", "Reading", "#C2532B"], q3: ["💼", "Q3 planning", "#2F6FE0"], hiring: ["🎯", "Hiring loop", "#B8479A"] };
  static SHORT = { inbox: "Inbox", kyoto: "Kyoto", home: "Home", reading: "Reading", q3: "Q3", hiring: "Hiring" };
  static TASKS = [
    ["q4", "q3", "Close out Q2 retro actions", -3, { prio: "medium" }], ["k3", "kyoto", "Reserve the Nishiki market tour", -2], ["h1", "home", "Fix the dripping bathroom tap", -1],
    ["q1", "q3", "Draft Q3 OKRs", 0, { prio: "high", time: "10:00" }], ["p1", "hiring", "Write interview feedback for Priya", 0, { star: true, time: "11:30" }],
    ["k4", "kyoto", "Ask Mika to water the planters", 0, { repeat: true }], ["k2", "kyoto", "Pay the ryokan deposit", 0, { time: "18:00" }],
    ["k1", "kyoto", "Renew passports", 3, { prio: "high" }], ["k5", "kyoto", "Pick up JR passes at Kyoto Station", 4], ["k6", "kyoto", "Reply to Kasuga about the tatami room", null, { done: true }],
    ["h2", "home", "Order new water filters", null], ["h3", "home", "Book the boiler service", 6], ["r1", "reading", "Finish The Overstory", null, { star: true }], ["r2", "reading", "Notes on Working in Public", null],
    ["q2", "q3", "Review hiring budget with Sam", 1], ["q5", "q3", "Prep board update slides", 2], ["q6", "q3", "Standup notes", null, { done: true }],
    ["p2", "hiring", "Schedule the onsite for Leo", 3], ["p3", "hiring", "Update the design role scorecard", null],
  ];
  static INBOX = [["Send Jun the photos from Nara", "2h"], ["Cancel the gym trial before it renews", "5h"], ["Call the dentist back about the crown", "1d"], ["Look into a standing desk", "2d"], ["Return the library books", "3d"], ["Gift ideas for Mika’s birthday", "4d"]];
  static EVENTS = [
    [[9.5, 10, "Standup"], [13, 14, "Design review"]], [[9.5, 10, "Standup"], [11, 12, "1:1 with Sam"], [15, 16.5, "Hiring sync"]],
    [[9.5, 10, "Standup"], [14, 15, "Board prep"], [15.5, 16, "Priya debrief"], [16, 16.5, "Coffee with Leo"]],
    [[9.5, 10, "Standup"], [10, 12, "Offsite planning"]], [[9.5, 10, "Standup"], [12, 13, "Team lunch"]], [[10, 11.5, "Pottery class"]], [],
  ];
  static PLAN = [["q4", 1, 14, 30], ["q1", 2, 10, 90], ["p1", 2, 11.5, 20], ["p3", 2, 13, 30], ["h2", 2, 16.5, 10], ["k2", 2, 18, 15], ["q2", 3, 13, 45], ["q5", 4, 10, 60]];
  static NOW_H = 10 + 40 / 60;
  static KINDS = [
    { kind: "today", name: "Today", desc: "What’s due and overdue. Tick tasks off without opening the app.", sizes: ["small", "medium", "large"] },
    { kind: "upnext", name: "Up Next", desc: "The block you should be on now, with Start, Pause and Done.", sizes: ["small", "medium"] },
    { kind: "capture", name: "Quick Add", desc: "One click to capture. Shows what’s waiting in Inbox.", sizes: ["small", "medium"] },
    { kind: "list", name: "List", desc: "Any list you pick, with progress and tickable tasks.", sizes: ["medium", "large"] },
    { kind: "agenda", name: "Agenda", desc: "Today’s plan around your meetings, or the whole week.", sizes: ["large", "xl"] },
    { kind: "summary", name: "Summary", desc: "Due, overdue, Inbox and done, plus this week.", sizes: ["small", "medium"] },
    { kind: "activity", name: "Activity", desc: "Your completion streak as a heatmap.", sizes: ["small", "medium"] },
  ];
  static DIMS = { small: [170, 170], medium: [358, 170], large: [358, 358], xl: [734, 358] };
  static SPAN = { small: [1, 1], medium: [2, 1], large: [2, 2], xl: [4, 2] };
  static SIZE_L = { small: "S", medium: "M", large: "L", xl: "XL" };

  constructor(props) {
    super(props);
    this.timers = {}; this.seq = 20;
    this.state = {
      mode: "light", editing: false, added: null, configUid: null, closing: {}, completed: {}, working: null, listId: "kyoto", showDone: false, toast: null, now: Date.now(),
      desktop: [["w1", "today", "large"], ["w2", "upnext", "medium"], ["w3", "capture", "small"], ["w4", "summary", "small"], ["w7", "agenda", "large"], ["w5", "list", "medium"], ["w6", "activity", "medium"]].map(([uid, kind, size]) => ({ uid, kind, size })),
      gSize: { today: "large", upnext: "medium", capture: "small", list: "medium", agenda: "large", summary: "small", activity: "small" },
    };
  }
  componentWillUnmount() { Object.values(this.timers).forEach(clearTimeout); clearInterval(this.tick); }
  later(k, fn, ms) { clearTimeout(this.timers[k]); this.timers[k] = setTimeout(fn, ms); }
  toast(text, icon) { this.setState((s) => ({ toast: { text, icon: icon || "check_circle", flip: !(s.toast && s.toast.flip) } })); this.later("toast", () => this.setState({ toast: null }), 2600); }
  T(id) { const t = Component.TASKS.find((x) => x[0] === id); if (!t) return null; const o = t[4] || {}; return { id: t[0], list: t[1], title: t[2], due: t[3], ...o, done: this.isDone(id) }; }
  isDone(id) { const t = Component.TASKS.find((x) => x[0] === id); const base = !!(t && t[4] && t[4].done); return this.state.completed[id] ? !base : base; }
  hm(h) { const hh = Math.floor(h + 1e-6), mm = Math.round((h - hh) * 60); return String(hh).padStart(2, "0") + ":" + String(mm).padStart(2, "0"); }

  toggle(id) {
    const s = this.state; const t = this.T(id); if (!t) return;
    if (s.closing[id]) { clearTimeout(this.timers["c" + id]); this.setState((st) => { const c = { ...st.closing }; delete c[id]; return { closing: c }; }); return; }
    if (this.isDone(id)) { this.setState((st) => ({ completed: { ...st.completed, [id]: !st.completed[id] } })); this.toast("Reopened “" + t.title + "”", "undo"); return; }
    this.setState((st) => ({ closing: { ...st.closing, [id]: true } }));
    this.later("c" + id, () => {
      this.setState((st) => { const c = { ...st.closing }; delete c[id]; return { closing: c, completed: { ...st.completed, [id]: !st.completed[id] }, working: st.working && st.working.id === id ? null : st.working }; });
      this.toast("Completed “" + t.title + "” — synced to Openlist");
    }, 900);
  }
  current() {
    const nowH = Component.NOW_H;
    const blocks = Component.PLAN.filter((p) => p[1] === 2).map(([id, , st, dur]) => ({ id, start: st, end: st + dur / 60 })).filter((b) => !this.isDone(b.id));
    const cur = blocks.find((b) => b.start <= nowH && nowH < b.end);
    if (cur) return { ...cur, state: "now" };
    const nx = blocks.filter((b) => b.start > nowH).sort((a, b) => a.start - b.start)[0];
    return nx ? { ...nx, state: "next" } : null;
  }
  elapsed() { const w = this.state.working; if (!w) return 0; return w.acc + (w.paused ? 0 : Math.max(0, this.state.now - w.start)); }
  start() { const c = this.current(); if (!c) return; this.setState({ working: { id: c.id, start: Date.now(), acc: 0, paused: false }, now: Date.now() }); clearInterval(this.tick); this.tick = setInterval(() => this.setState({ now: Date.now() }), 1000); this.toast("Started — the timer also shows in Openlist’s toolbar", "play_circle"); }
  pause() { this.setState((s) => { const w = s.working; if (!w) return {}; return w.paused ? { working: { ...w, paused: false, start: Date.now() } } : { working: { ...w, paused: true, acc: w.acc + (Date.now() - w.start) } }; }); }
  finish() { const w = this.state.working; const c = this.current(); const id = w ? w.id : c && c.id; if (!id) return; clearInterval(this.tick); this.setState({ working: null }); this.toggle(id); }

  model() {
    const s = this.state; const L = Component.LISTS;
    const item = (t) => { const l = L[t.list]; return { id: t.id, title: t.title, listEmoji: l[0], listName: l[1], color: l[2], prio: t.prio, star: t.star, late: t.due != null && t.due < 0 && !t.done, closing: !!s.closing[t.id], done: t.done,
      dueText: t.done ? "Done" : t.due == null ? "" : t.due < 0 ? Math.abs(t.due) + "d late" : t.due === 0 ? t.time || (t.repeat ? "Repeats" : "Today") : t.due === 1 ? "Tomorrow" : ["Thu", "Fri", "Sat", "Sun", "Mon", "Tue"][(t.due - 1) % 7] + " " + (23 + t.due) }; };
    const all = Component.TASKS.map((x) => this.T(x[0]));
    const todays = all.filter((t) => t.due != null && t.due <= 0 && (!t.done || s.closing[t.id])).sort((a, b) => (a.due - b.due) || ((a.time || "99") < (b.time || "99") ? -1 : 1));
    const doneToday = 2 + all.filter((t) => s.completed[t.id] && t.done).length;
    const listTasks = all.filter((t) => t.list === s.listId);
    const listItems = listTasks.filter((t) => !t.done || s.closing[t.id]).concat(s.showDone ? listTasks.filter((t) => t.done && !s.closing[t.id]) : []);
    // up next
    const c = this.current(); const w = s.working; let upnext;
    const ct = c && this.T(c.id);
    if (!c) upnext = { state: "none", title: "Nothing else planned", list: "Your day is clear", progress: 0, note: "", later: [] };
    else {
      const el = this.elapsed(); const dur = (c.end - c.start) * 60;
      const prog = w ? Math.min(1, el / 60000 / dur) : c.state === "now" ? (Component.NOW_H - c.start) / (c.end - c.start) : 0;
      const sec = Math.floor(el / 1000);
      upnext = { state: c.state, title: ct.title, list: L[ct.list][0] + " " + L[ct.list][1], time: this.hm(c.start) + "–" + this.hm(c.end), progress: prog,
        note: c.state === "now" ? Math.round((c.end - Component.NOW_H) * 60) + " min left" : "in " + Math.round((c.start - Component.NOW_H) * 60) + " min",
        working: w ? { paused: w.paused, elapsed: String(Math.floor(sec / 60)).padStart(2, "0") + ":" + String(sec % 60).padStart(2, "0") } : null };
      const after = c.end;
      const later = [];
      Component.EVENTS[2].forEach(([a, , t]) => { if (a >= after - 1e-6) later.push({ start: a, title: t, meet: true }); });
      Component.PLAN.filter((p) => p[1] === 2 && p[2] >= after - 1e-6 && !this.isDone(p[0])).forEach(([id, , st]) => { const t = this.T(id); later.push({ start: st, title: t.title, color: L[t.list][2] }); });
      upnext.later = later.sort((a, b) => a.start - b.start).map((l) => ({ ...l, time: this.hm(l.start) }));
    }
    // activity
    const weeks = []; const T = 20 * 7 + 2; let streak = 0, month = 0, week = 0;
    const cnt = (i) => { if (i > T) return null; if (i === T) return doneToday; const rr = Math.abs(Math.sin((i + 1) * 12.9898) * 43758.5453) % 1; return Math.floor(rr * rr * (i % 7 >= 5 ? 4 : 9)); };
    for (let wk = 0; wk < 21; wk++) { const cells = []; for (let d = 0; d < 7; d++) cells.push(cnt(wk * 7 + d)); weeks.push(cells); }
    for (let i = T; i >= 0; i--) { const v = cnt(i); if (v > 0) streak++; else if (i !== T) break; }
    for (let i = T - 22; i <= T; i++) month += cnt(i); for (let i = T - 2; i <= T; i++) week += cnt(i);
    // agenda
    const dayItems = (d) => {
      const ev = Component.EVENTS[d].map(([a, b, t]) => ({ start: a, end: b, title: t, meet: true, timeText: this.hm(a) + "–" + this.hm(b) }));
      const tk = Component.PLAN.filter((p) => p[1] === d).map(([id, , st, dur]) => { const t = this.T(id); return { start: st, end: st + dur / 60, title: t.title, color: L[t.list][2], done: this.isDone(id), timeText: this.hm(st) + "–" + this.hm(st + dur / 60) }; });
      return ev.concat(tk);
    };
    const dnames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
    return {
      dow: "Wednesday", dayNum: 23,
      today: { items: todays.map(item), done: doneToday, total: doneToday + todays.filter((t) => !s.closing[t.id]).length + Object.keys(s.closing).length * 0, late: todays.filter((t) => t.due < 0 && !s.closing[t.id]).length },
      list: { emoji: L[s.listId][0], name: L[s.listId][1], short: Component.SHORT[s.listId], color: L[s.listId][2], open: listTasks.filter((t) => !t.done).length, done: listTasks.filter((t) => t.done).length, items: listItems.map(item) },
      upnext,
      inbox: { count: Component.INBOX.length, items: Component.INBOX.map(([title, age]) => ({ title, age })) },
      summary: { due: all.filter((t) => t.due === 0 && !t.done).length, overdue: all.filter((t) => t.due != null && t.due < 0 && !t.done).length, inbox: Component.INBOX.length, done: doneToday,
        week: dnames.map((d, i) => ({ day: d[0], n: i <= 2 ? cnt(T - 2 + i) : null, today: i === 2 })), weekTotal: week },
      activity: { weeks, streak, month, week, today: doneToday, todayDow: 2 },
      agenda: { nowH: Component.NOW_H, day: dayItems(2), daySub: "Wed 23 · " + Component.EVENTS[2].length + " meetings · " + Component.PLAN.filter((p) => p[1] === 2).length + " planned",
        week: dnames.map((d, i) => ({ label: d + " " + (21 + i), isToday: i === 2, items: dayItems(i) })), range: "21 – 27 September" },
      on: { toggle: (id) => this.toggle(id), start: () => this.start(), pause: () => this.pause(), done: () => this.finish(),
        capture: (l) => this.toast("Opens Quick Add" + (l ? " in " + l : "") + " — type, ↩, done", "add_circle"), triage: () => this.toast("Opens Inbox triage in Openlist", "inbox") },
    };
  }

  renderVals() {
    const s = this.state; const model = this.model(); const A = "#7C4DF0";
    const dark = s.mode === "dark"; const dim = s.mode === "dimmed";
    const cfgLists = (uid) => Object.keys(Component.LISTS).filter((k) => k !== "inbox").map((k) => { const l = Component.LISTS[k]; const on = s.listId === k;
      return { emoji: l[0], name: l[1], onClick: (e) => { e.stopPropagation(); this.setState({ listId: k }); },
        style: "display:inline-flex; align-items:center; gap:5px; padding:6px 9px; border-radius:999px; cursor:pointer; font:500 11.5px/1 -apple-system,sans-serif; white-space:nowrap; transition:background 140ms ease, color 140ms ease; " + (on ? "background:" + l[2] + "; color:#fff;" : "background:rgba(23,22,26,0.05); color:rgba(23,22,26,0.7);") }; });
    const desk = s.desktop.map((w) => {
      const [c, r] = Component.SPAN[w.size]; const [W, H] = Component.DIMS[w.size];
      const cfg = s.configUid === w.uid;
      return { ...w, model, mode: s.mode, editing: s.editing, canConfig: s.editing && w.kind === "list" && !cfg, showWidget: !cfg, showConfig: cfg,
        cellStyle: "position:relative; grid-column:span " + c + "; grid-row:span " + r + ";" + (s.added === w.uid ? " animation:widgetIn 460ms cubic-bezier(0.2,0.9,0.2,1);" : ""),
        innerStyle: "transition:transform 220ms cubic-bezier(0.2,0.9,0.2,1), filter 220ms ease;" + (s.editing ? " transform:scale(0.97);" : ""),
        onClick: (e) => { if (s.editing) { e.stopPropagation(); if (w.kind === "list") this.setState({ configUid: w.uid }); } },
        onRemove: (e) => { e.stopPropagation(); this.setState((st) => ({ desktop: st.desktop.filter((x) => x.uid !== w.uid), configUid: null })); },
        onConfig: (e) => { e.stopPropagation(); this.setState({ configUid: w.uid }); },
        stop: (e) => e.stopPropagation(),
        configStyle: "width:" + W + "px; height:" + H + "px; box-sizing:border-box; border-radius:22px; padding:15px 16px; background:#FFFFFF; box-shadow:0 0 0 0.5px rgba(0,0,0,0.06), 0 14px 34px rgba(40,30,20,0.2); display:flex; flex-direction:column; gap:11px; animation:flipIn 380ms cubic-bezier(0.2,0.9,0.2,1); transform-origin:center;",
        cfgLists: cfg ? cfgLists(w.uid) : [],
        onToggleDone: (e) => { e.stopPropagation(); this.setState((st) => ({ showDone: !st.showDone })); },
        trackStyle: "width:32px; height:19px; border-radius:10px; position:relative; flex:none; transition:background 180ms ease; background:" + (s.showDone ? A : "rgba(23,22,26,0.16)") + ";",
        knobStyle: "position:absolute; top:2px; left:" + (s.showDone ? 15 : 2) + "px; width:15px; height:15px; border-radius:50%; background:#fff; box-shadow:0 1px 3px rgba(0,0,0,0.2); transition:left 200ms cubic-bezier(0.34,1.56,0.64,1);",
        onConfigDone: (e) => { e.stopPropagation(); this.setState({ configUid: null }); },
      };
    });
    const sc = 0.6;
    const gallery = Component.KINDS.map((k) => {
      const size = s.gSize[k.kind]; const [W, H] = Component.DIMS[size];
      return { ...k, size, model, mode: dark ? "dark" : "light",
        colStyle: "display:flex; flex-direction:column; gap:10px; flex:none; width:" + Math.max(210, Math.round(W * sc)) + "px;",
        boxStyle: "position:relative; width:" + Math.round(W * sc) + "px; height:" + Math.round(H * sc) + "px; cursor:pointer; transition:transform 200ms cubic-bezier(0.2,0.9,0.2,1);",
        scaleStyle: "width:" + W + "px; height:" + H + "px; transform:scale(" + sc + "); transform-origin:top left; pointer-events:none;",
        onAdd: () => { const uid = "w" + ++this.seq; this.setState((st) => ({ desktop: [...st.desktop, { uid, kind: k.kind, size }], added: uid })); this.later("added", () => this.setState({ added: null }), 600); this.toast("Added " + k.name + " · " + { small: "Small", medium: "Medium", large: "Large", xl: "Extra Large" }[size], "add_circle"); },
        sizes: k.sizes.map((z) => ({ label: Component.SIZE_L[z], onClick: () => this.setState((st) => ({ gSize: { ...st.gSize, [k.kind]: z } })),
          style: "min-width:26px; padding:5px 7px; box-sizing:border-box; text-align:center; border-radius:6px; cursor:pointer; font:600 10.5px/1 -apple-system,sans-serif; transition:background 140ms ease, color 140ms ease; " + (z === size ? "background:" + A + "; color:#fff;" : "background:var(--gchip); color:var(--gsub);") })) };
    });
    const apps = [["Openlist", "checklist", true], ["Calendar", "calendar_month"], ["Clock", "schedule"], ["Notes", "sticky_note_2"], ["Reminders", "format_list_bulleted"], ["Weather", "partly_cloudy_day"]].map(([name, icon, on]) => ({ name, icon,
      style: "display:flex; align-items:center; gap:9px; height:32px; padding:0 8px; border-radius:8px; font:" + (on ? 600 : 500) + " 13px/1 -apple-system,sans-serif; color:" + (on ? "var(--gink)" : "var(--gsub)") + ";" + (on ? " background:var(--gchip);" : " opacity:0.6;"),
      tileStyle: "width:22px; height:22px; border-radius:6px; display:flex; align-items:center; justify-content:center; color:#fff; background:" + (on ? A : "rgba(120,118,128,0.55)") + ";" }));
    const menuInk = dark || dim ? "#FFFFFF" : "#17161A";
    return {
      modes: [["light", "Light"], ["dark", "Dark"], ["dimmed", "Desktop · in background"]].map(([v, label]) => ({ label, onClick: () => this.setState({ mode: v }),
        style: "padding:6px 11px; border-radius:7px; cursor:pointer; font:500 12px/1 -apple-system,sans-serif; white-space:nowrap; transition:background 140ms ease; " + (s.mode === v ? "background:#fff; color:#17161A; box-shadow:0 1px 2px rgba(23,22,26,0.12);" : "color:rgba(23,22,26,0.55);") })),
      toggleEdit: (e) => { if (e) e.stopPropagation(); this.setState((st) => ({ editing: !st.editing, configUid: null })); },
      editIcon: s.editing ? "check" : "widgets", editLabel: s.editing ? "Done editing" : "Edit Widgets",
      editBtnStyle: "display:flex; align-items:center; gap:6px; padding:7px 12px; border-radius:8px; cursor:pointer; font:600 12px/1 -apple-system,sans-serif; white-space:nowrap; " + (s.editing ? "background:#17161A; color:#fff;" : "background:" + A + "; color:#fff; box-shadow:0 1px 2px rgba(124,77,240,0.4);"),
      desktopStyle: "position:relative; width:1400px; height:1000px; overflow:hidden; transition:background 400ms ease; background:" + (dark ? "radial-gradient(120% 90% at 20% 0%, #3A3546 0%, #211F28 55%, #15141A 100%)" : dim ? "radial-gradient(120% 90% at 20% 0%, #9A92A6 0%, #6E6880 55%, #4E4A5E 100%)" : "radial-gradient(120% 90% at 20% 0%, #E6DFD5 0%, #CBC4CF 55%, #A9A8BC 100%)") + ";",
      menubarStyle: "height:26px; display:flex; align-items:center; gap:16px; padding:0 16px; font:500 12.5px/1 -apple-system,sans-serif; color:" + menuInk + "; background:" + (dark || dim ? "rgba(0,0,0,0.22)" : "rgba(255,255,255,0.38)") + "; backdrop-filter:blur(20px); -webkit-backdrop-filter:blur(20px);",
      onDesktopClick: () => { if (s.configUid) this.setState({ configUid: null }); },
      desk, editing: s.editing, gallery, apps, stop: (e) => e.stopPropagation(),
      sheetStyle: "position:absolute; left:0; right:0; bottom:0; height:400px; display:flex; z-index:20; border-radius:16px 16px 0 0; backdrop-filter:blur(30px) saturate(1.2); -webkit-backdrop-filter:blur(30px) saturate(1.2); animation:sheetUp 380ms cubic-bezier(0.2,0.9,0.2,1); box-shadow:0 -18px 50px rgba(20,16,30,0.2); " + (dark ? "background:rgba(38,36,44,0.9); --gink:#F4F2F7; --gsub:rgba(244,242,247,0.6); --gline:rgba(244,242,247,0.1); --gchip:rgba(244,242,247,0.08); border-top:0.5px solid rgba(255,255,255,0.1);" : "background:rgba(248,246,243,0.9); --gink:#17161A; --gsub:rgba(23,22,26,0.56); --gline:rgba(23,22,26,0.1); --gchip:rgba(23,22,26,0.06); border-top:0.5px solid rgba(23,22,26,0.1);"),
      toastShow: !!s.toast, toastText: s.toast ? s.toast.text : "", toastIcon: s.toast ? s.toast.icon : "",
      toastStyle: "position:absolute; left:50%; bottom:" + (s.editing ? 424 : 28) + "px; transform:translateX(-50%); display:flex; align-items:center; gap:9px; padding:10px 14px; border-radius:11px; background:#17161A; color:#fff; font:500 12px/1 -apple-system,sans-serif; white-space:nowrap; box-shadow:0 14px 34px rgba(0,0,0,0.3); z-index:30; animation:toastIn 220ms cubic-bezier(0.2,0.9,0.2,1);",
      notes: [
        { name: "Today", sizes: "S · M · L", body: "Replaces the current Today widget. Tapping a circle runs a CompleteTask intent, so the task is ticked off without opening the app; the row settles out on the next reload. Tapping the title opens the task in Openlist." },
        { name: "Up Next", sizes: "S · M", body: "Reads today’s calendar sessions. Start, Pause and Done are intents that share state with the timer in the app’s toolbar. The live clock uses Text(timerInterval:), so it ticks without reloading the widget." },
        { name: "Quick Add", sizes: "S · M", body: "Widgets can’t hold a text field, so the small size is one widgetURL (openlist://capture) that opens the Quick Add panel. The medium size adds Links to Inbox and to triage." },
        { name: "List", sizes: "M · L", body: "Replaces Lists. An AppIntentConfiguration with a List entity and a Show completed switch; in Edit Widgets it flips over to choose. Rows can be ticked off." },
        { name: "Agenda", sizes: "L · XL", body: "Large shows today’s plan around meetings; Extra Large shows the week. The timeline gets an entry every 15 minutes, so the now line moves without the app running." },
        { name: "Summary", sizes: "S · M", body: "Keeps the current four counts, set in the display serif, and adds this week’s completions at medium size. Zero values fade out so the one that matters stands out." },
        { name: "Activity", sizes: "S · M", body: "The Activity screen’s heatmap: 10 weeks at small size, 21 at medium. Filled cells use .widgetAccentable() so they keep their shape in tinted and in-background modes." },
        { name: "Rendering modes", sizes: "All", body: "Designed for full colour, dark, and the desktop in-background (vibrant) mode, where accents collapse to white. Checkboxes, rings, bars and cells are the accentable parts; text stays primary or secondary." },
      ],
    };
  }
}
