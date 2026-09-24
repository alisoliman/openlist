class Component extends DCLogic {
  pal(mode) {
    if (mode === "dark") return { bg: "#232128", ink: "#F4F2F7", sub: "rgba(244,242,247,0.6)", faint: "rgba(244,242,247,0.36)", line: "rgba(244,242,247,0.1)", chip: "rgba(244,242,247,0.08)", track: "rgba(244,242,247,0.12)", acc: "#9B78FF", orange: "#F0A04B", red: "#FF6B72", green: "#4CC08A", amber: "#F2C14E", blue: "#6AA1F0", bluechip: "rgba(106,161,240,0.16)", onacc: "#FFFFFF", accshadow: "rgba(155,120,255,0.3)", meet: "rgba(244,242,247,0.08)" };
    if (mode === "dimmed") { const w = "rgba(255,255,255,0.95)"; return { bg: "rgba(255,255,255,0.18)", ink: "rgba(255,255,255,0.97)", sub: "rgba(255,255,255,0.74)", faint: "rgba(255,255,255,0.52)", line: "rgba(255,255,255,0.2)", chip: "rgba(255,255,255,0.14)", track: "rgba(255,255,255,0.24)", acc: w, orange: w, red: w, green: w, amber: w, blue: w, bluechip: "rgba(255,255,255,0.18)", onacc: "rgba(36,32,46,0.82)", accshadow: "transparent", meet: "rgba(255,255,255,0.13)" }; }
    return { bg: "#FFFFFF", ink: "#17161A", sub: "rgba(23,22,26,0.58)", faint: "rgba(23,22,26,0.36)", line: "rgba(23,22,26,0.09)", chip: "rgba(23,22,26,0.05)", track: "rgba(23,22,26,0.08)", acc: "#7C4DF0", orange: "#E0861F", red: "#D8434B", green: "#2F9E6E", amber: "#E8A917", blue: "#3A7BD8", bluechip: "rgba(58,123,216,0.12)", onacc: "#FFFFFF", accshadow: "rgba(124,77,240,0.32)", meet: "rgba(23,22,26,0.055)" };
  }

  renderVals() {
    const p = this.props; const m = p.model; const kind = p.kind ?? "today"; const size = p.size ?? "medium"; const mode = p.mode ?? "light";
    const D = { small: [170, 170], medium: [358, 170], large: [358, 358], xl: [734, 358] }[size] || [358, 170];
    const P = this.pal(mode); const dim = mode === "dimmed";
    const S = size === "small", M = size === "medium", L = size === "large", XL = size === "xl";
    const vars = Object.keys(P).map((k) => "--" + k + ":" + P[k]).join("; ");
    const shadow = dim ? "0 0 0 0.5px rgba(255,255,255,0.3)" : mode === "dark" ? "0 0 0 0.5px rgba(255,255,255,0.08), 0 12px 30px rgba(0,0,0,0.35)" : "0 0 0 0.5px rgba(0,0,0,0.05), 0 10px 28px rgba(40,30,20,0.14)";
    const col = (c) => (dim ? "rgba(255,255,255,0.92)" : c || "var(--sub)");
    const tint = (c) => (dim ? "rgba(255,255,255,0.16)" : c + (mode === "dark" ? "3D" : "24"));
    const v = {
      rootStyle: "width:" + D[0] + "px; height:" + D[1] + "px; box-sizing:border-box; border-radius:22px; padding:" + (S ? "14px" : "15px 16px") + "; display:flex; position:relative; overflow:hidden; background:var(--bg); color:var(--ink); font-family:-apple-system,'SF Pro Text','Helvetica Neue',sans-serif; -webkit-font-smoothing:antialiased; transition:background 300ms ease, box-shadow 300ms ease; box-shadow:" + shadow + ";" + (dim ? " backdrop-filter:blur(26px) saturate(1.3); -webkit-backdrop-filter:blur(26px) saturate(1.3);" : "") + " " + vars + ";",
      noModel: !m, todaySide: false, todayHead: false, isList: false, hasRows: false, rowsEmpty: false, hasFooter: false, isUpnext: false, isCapture: false, isSummary: false, isActivity: false, isAgenda: false,
      rows: [], hasMore: false, moreText: "", ringOff: 62.83, doneText: "", lateText: "", lateStyle: "", dow: "", dayNum: "", todayTitle: "", todayTitleStyle: "",
      emptyTitle: "", emptySub: "", footerAdd: "", footerNote: "", onCapture: () => {}, rowsWrapStyle: "",
    };
    if (!m) return v;
    const on = m.on || {};

    const mkRow = (i, compact, noMeta) => {
      const lbl = (dim ? "" : i.listEmoji + " ") + i.listName;
      const closing = !!i.closing, done = !!i.done; const filled = closing || done;
      const ring = i.late ? "var(--red)" : i.prio === "high" ? "var(--red)" : i.prio === "medium" ? "var(--amber)" : col(i.color);
      return {
        isRow: true, isHead: false, title: i.title, star: !compact && !!i.star,
        hasMeta: !noMeta, meta: compact ? i.dueText || lbl : lbl,
        hasSide: !compact && !!i.dueText, side: i.dueText || "",
        onToggle: (e) => { if (e) e.stopPropagation(); on.toggle && on.toggle(i.id); },
        wrapStyle: "display:flex; align-items:flex-start; gap:8px; min-width:0; transition:opacity 320ms ease;" + (closing ? " opacity:0.55;" : "") + (i.fresh ? " animation:wIn 280ms ease;" : ""),
        boxStyle: "width:15px; height:15px; flex:none; margin-top:1px; border-radius:50%; box-sizing:border-box; display:flex; align-items:center; justify-content:center; cursor:pointer; transition:background 200ms ease, border-color 200ms ease, transform 260ms cubic-bezier(0.34,1.56,0.64,1); " + (filled ? "background:" + (closing ? "var(--acc)" : "var(--green)") + "; border:1.5px solid transparent; transform:scale(" + (closing ? 1.12 : 1) + ");" : "border:1.5px solid " + ring + ";"),
        checkStyle: "font-size:10px; color:var(--onacc); font-variation-settings:'wght' 700; transition:opacity 150ms ease; opacity:" + (filled ? 1 : 0) + ";",
        titleStyle: (compact ? "font:500 11.5px/1.3 -apple-system,sans-serif; display:-webkit-box; -webkit-line-clamp:2; -webkit-box-orient:vertical; overflow:hidden;" : "font:500 12px/1.3 -apple-system,sans-serif; white-space:nowrap; overflow:hidden; text-overflow:ellipsis;") + " color:" + (filled ? "var(--sub)" : "var(--ink)") + ";" + (filled ? " text-decoration:line-through;" : ""),
        metaStyle: "font:500 10px/1.2 -apple-system,sans-serif; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; color:" + (compact && i.late ? "var(--red)" : "var(--faint)") + ";",
        sideStyle: "font:500 10px/1.3 -apple-system,sans-serif; white-space:nowrap; flex:none; padding-top:1px; font-variant-numeric:tabular-nums; color:" + (i.late ? "var(--red)" : "var(--sub)") + ";",
      };
    };
    const head = (t, c, first) => ({ isHead: true, isRow: false, title: t, headStyle: "font:700 9.5px/1 -apple-system,sans-serif; letter-spacing:0.08em; text-transform:uppercase; color:" + c + "; padding-top:" + (first ? 2 : 7) + "px;" });

    if (kind === "today" || kind === "list") {
      const src = kind === "today" ? m.today : m.list;
      const items = src.items;
      let rows = [], shown = 0;
      if (kind === "today" && L) {
        const late = items.filter((i) => i.late), now = items.filter((i) => !i.late);
        let budget = 5;
        if (late.length) { rows.push(head("Overdue", "var(--red)", true)); late.slice(0, 3).forEach((i) => { rows.push(mkRow(i, false)); shown++; budget--; }); }
        if (now.length) { rows.push(head("Due today", "var(--faint)", !late.length)); now.slice(0, Math.max(0, budget)).forEach((i) => { rows.push(mkRow(i, false)); shown++; }); }
      } else {
        const n = kind === "today" ? (S ? 2 : M ? 3 : 6) : M ? 3 : 6;
        rows = items.slice(0, n).map((i) => mkRow(i, S, kind === "list" && M)); shown = rows.length;
      }
      v.rows = rows; v.hasRows = items.length > 0; v.rowsEmpty = items.length === 0;
      v.hasMore = items.length > shown; v.moreText = "+" + (items.length - shown) + " more";
      v.rowsWrapStyle = "display:flex; flex-direction:column; gap:" + (S ? 8 : 7) + "px; padding-top:" + (kind === "today" && M ? 0 : kind === "list" ? 13 : 11) + "px; min-height:0; overflow:hidden;";
      v.emptyTitle = "All clear"; v.emptySub = kind === "today" ? (S ? "Nothing due" : "Nothing due or overdue today") : "Every task in this list is done";
      v.onCapture = () => on.capture && on.capture(kind === "list" ? src.name : null);
      if (kind === "today") {
        const t = m.today; const pct = t.total ? t.done / t.total : 0;
        v.ringOff = (62.83 * (1 - pct)).toFixed(2); v.doneText = t.done + " of " + t.total + " done";
        v.lateText = t.late ? t.late + " late" : M ? "On track" : ""; v.lateStyle = "font:600 10.5px/1 -apple-system,sans-serif; white-space:nowrap; color:" + (t.late ? "var(--red)" : "var(--green)") + ";";
        v.dow = m.dow; v.dayNum = m.dayNum; v.todaySide = M; v.todayHead = !M;
        v.todayTitle = "Today"; v.todayTitleStyle = L ? "font:400 23px/1 'Instrument Serif',Georgia,serif; color:var(--ink);" : "font:700 13px/1 -apple-system,sans-serif; color:var(--ink);";
        v.hasFooter = L; v.footerAdd = "New task"; v.footerNote = t.done + " done today";
      } else {
        const l = m.list; const tot = l.open + l.done;
        v.isList = true; v.listEmoji = l.emoji; v.listName = l.name; v.listMeta = l.open + " open";
        v.listTileStyle = "width:28px; height:28px; flex:none; border-radius:9px; background:" + tint(l.color) + "; display:flex; align-items:center; justify-content:center; font-size:15px;" + (dim ? " filter:grayscale(1) brightness(1.4);" : "");
        v.listBarStyle = "height:3px; border-radius:2px; background:" + col(l.color) + "; width:" + (tot ? Math.round((l.done / tot) * 100) : 0) + "%; transition:width 600ms cubic-bezier(0.2,0.8,0.2,1);";
        v.hasFooter = L; v.footerAdd = "Add to " + l.short; v.footerNote = l.done + " done";
      }
    }

    if (kind === "upnext") {
      const u = m.upnext; const w = u.working;
      v.isUpnext = true;
      v.unLabel = w ? (w.paused ? "Paused" : "Working") : u.state === "now" ? "Now" : u.state === "next" ? "Next" : "Clear";
      v.unTime = u.time || ""; v.unTitle = u.title; v.unList = dim ? (u.list || "").replace(/^\S+\s/, "") : u.list || "";
      v.unElapsed = w ? w.elapsed : u.note;
      v.unElapsedStyle = w ? "font:600 19px/1 ui-monospace,Menlo,monospace; font-variant-numeric:tabular-nums; color:var(--acc);" : "font:500 11px/1 -apple-system,sans-serif; color:var(--sub); white-space:nowrap;";
      v.unBarStyle = "height:3px; border-radius:2px; background:var(--acc); width:" + Math.round((u.progress || 0) * 100) + "%; transition:width 900ms linear;";
      v.unDotStyle = "width:7px; height:7px; border-radius:50%; flex:none; background:" + (w && w.paused ? "var(--amber)" : "var(--acc)") + ";" + ((w && !w.paused) || (!w && u.state === "now") ? " animation:wBreathe 1.6s ease-in-out infinite;" : "");
      v.unMainStyle = "display:flex; flex-direction:column; min-width:0; " + (M ? "width:168px; flex:none;" : "flex:1;");
      v.unIdle = !w && u.state !== "none"; v.unWorking = !!w; v.unPauseIcon = w && w.paused ? "play_arrow" : "pause";
      v.onStart = () => on.start && on.start(); v.onPause = () => on.pause && on.pause(); v.onDone = () => on.done && on.done();
      v.unHasLater = M;
      v.unLater = (u.later || []).slice(0, 4).map((l) => ({ time: l.time, title: l.title,
        barStyle: "width:3px; height:15px; border-radius:2px; flex:none; background:" + (l.meet ? "var(--track)" : col(l.color)) + ";",
        titleStyle: "font:500 11.5px/1.2 -apple-system,sans-serif; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; min-width:0; color:" + (l.meet ? "var(--sub)" : "var(--ink)") + ";" }));
    }

    if (kind === "capture") {
      const c = m.inbox;
      v.isCapture = true; v.onCapture = () => on.capture && on.capture(null); v.onTriage = () => on.triage && on.triage();
      v.capMainStyle = "display:flex; flex-direction:column; cursor:pointer; min-width:0; " + (M ? "width:118px; flex:none;" : "flex:1;");
      v.capSub = S ? c.count + " waiting in Inbox" : "Type it, Openlist sorts dates and labels";
      v.capHasInbox = M; v.capCount = String(c.count); v.capItems = c.items.slice(0, 4).map((x) => ({ title: x.title, age: x.age }));
    }

    if (kind === "summary") {
      const s = m.summary;
      v.isSummary = true; v.sumMainStyle = "display:flex; flex-direction:column; gap:10px; min-width:0; " + (M ? "width:140px; flex:none;" : "flex:1;");
      v.stats = [["Due today", s.due, "var(--acc)"], ["Overdue", s.overdue, "var(--red)"], ["In Inbox", s.inbox, "var(--blue)"], ["Done", s.done, "var(--green)"]].map(([label, value, c]) => ({ label, value: String(value),
        numStyle: "font:400 " + (S ? 30 : 32) + "px/0.9 'Instrument Serif',Georgia,serif; font-variant-numeric:lining-nums tabular-nums; transition:color 300ms ease; color:" + (value ? c : "var(--faint)") + ";" }));
      v.sumHasWeek = M; v.weekTotal = s.weekTotal + " done";
      const max = Math.max(1, ...s.week.map((b) => b.n || 0));
      v.weekBars = s.week.map((b) => ({ day: b.day, num: b.n == null ? "" : String(b.n),
        numStyle: "font:600 9.5px/1 -apple-system,sans-serif; font-variant-numeric:tabular-nums; color:" + (b.today ? "var(--acc)" : "var(--faint)") + ";",
        barStyle: "width:100%; max-width:20px; border-radius:4px; transition:height 500ms cubic-bezier(0.2,0.8,0.2,1); height:" + (b.n == null ? 3 : Math.max(4, Math.round((b.n / max) * 70))) + "px; background:" + (b.today ? "var(--acc)" : b.n == null ? "var(--track)" : "var(--ink)") + "; opacity:" + (b.today || b.n == null ? 1 : 0.2) + ";",
        dayStyle: "font:600 9.5px/1 -apple-system,sans-serif; color:" + (b.today ? "var(--acc)" : "var(--faint)") + ";" }));
    }

    if (kind === "activity") {
      const a = m.activity; const n = S ? 10 : 21; const weeks = a.weeks.slice(-n);
      v.isActivity = true; v.streakText = a.streak + "-day streak";
      v.heat = weeks.map((wk, wi) => ({ cells: wk.map((c, di) => {
        const isToday = wi === weeks.length - 1 && di === a.todayDow;
        const op = c == null ? 0 : c === 0 ? 0 : c <= 1 ? 0.28 : c <= 3 ? 0.5 : c <= 6 ? 0.75 : 1;
        return { style: "width:10.5px; height:10.5px; border-radius:3px; box-sizing:border-box; transition:opacity 400ms ease;" + (c == null ? " background:transparent; box-shadow:inset 0 0 0 0.5px var(--line);" : c === 0 ? " background:var(--track);" : " background:var(--acc); opacity:" + op + ";") + (isToday ? " box-shadow:0 0 0 1.5px var(--ink);" : "") };
      }) }));
      v.actStats = S ? [{ value: String(a.month), label: "in September" }] : [{ value: String(a.today), label: "today" }, { value: String(a.week), label: "this week" }, { value: String(a.month), label: "in September" }];
    }

    if (kind === "agenda") {
      const g = m.agenda; const H0 = 9, H1 = 19; const pxh = XL ? 27 : 29; const week = XL || size === "medium";
      v.isAgenda = true; v.agWeek = XL;
      v.agTitle = XL ? "This week" : "Today"; v.agSub = XL ? g.range : g.daySub;
      v.agDays = XL ? g.week.map((d) => ({ label: d.label, headStyle: "font:600 9.5px/1 -apple-system,sans-serif; letter-spacing:0.05em; text-transform:uppercase; padding-left:4px; white-space:nowrap; color:" + (d.isToday ? "var(--acc)" : "var(--faint)") + ";" })) : [];
      const days = XL ? g.week : [{ isToday: true, items: g.day }];
      v.agGridStyle = "display:grid; grid-template-columns:30px repeat(" + days.length + ", minmax(0,1fr)); position:relative; height:" + (H1 - H0) * pxh + "px; flex:none;";
      v.agHours = [10, 12, 14, 16, 18].map((hh) => ({ label: String(hh).padStart(2, "0"), style: "position:absolute; right:7px; top:" + ((hh - H0) * pxh - 5) + "px; font:500 9px/1 ui-monospace,Menlo,monospace; color:var(--faint);" }));
      v.agCols = days.map((d) => ({ isToday: d.isToday,
        style: "position:relative; border-left:0.5px solid var(--line); background-image:repeating-linear-gradient(to bottom, var(--line) 0px, var(--line) 0.5px, transparent 0.5px, transparent " + pxh + "px);" + (XL && d.isToday ? " background-color:var(--chip);" : ""),
        items: d.items.filter((it) => it.end > H0 && it.start < H1).map((it) => {
          const top = (Math.max(it.start, H0) - H0) * pxh + 1; const h = Math.max(13, (Math.min(it.end, H1) - Math.max(it.start, H0)) * pxh - 2);
          return { title: it.title, time: it.timeText,
            style: "position:absolute; left:" + (XL ? 2 : 5) + "px; right:" + (XL ? 2 : 5) + "px; top:" + top + "px; height:" + h + "px; border-radius:5px; padding:" + (h < 18 ? "1px 5px" : "3px 6px") + "; box-sizing:border-box; overflow:hidden; display:flex; flex-direction:column; gap:1px; transition:background 300ms ease;" + (it.meet ? " background:var(--meet);" : " background:" + (it.done ? "var(--chip)" : tint(it.color)) + "; box-shadow:inset 2.5px 0 0 " + (it.done ? "var(--track)" : col(it.color)) + ";"),
            titleStyle: "font:600 " + (XL ? 9 : 10.5) + "px/1.2 -apple-system,sans-serif; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; color:" + (it.meet || it.done ? "var(--sub)" : "var(--ink)") + ";" + (it.done ? " text-decoration:line-through;" : ""),
            timeStyle: !XL && h >= 28 ? "font:500 9.5px/1.2 ui-monospace,Menlo,monospace; color:var(--faint);" : "display:none;" };
        }) }));
      v.agNowStyle = "position:absolute; left:0; right:0; top:" + ((g.nowH - H0) * pxh) + "px; height:1.5px; background:var(--red); z-index:3; pointer-events:none;";
    }
    return v;
  }
}
