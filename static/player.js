(function () {
  const data = window.CAPTION_EDITOR;
  if (!data || !Array.isArray(data.cues) || !data.srtPath) {
    return;
  }

  const video = document.getElementById("reviewVideo");
  const cueList = document.getElementById("cueList");
  const saveBtn = document.getElementById("saveBtn");
  const saveStatus = document.getElementById("saveStatus");
  const track = document.getElementById("reviewTrack");
  const trackBaseUrl = track ? track.getAttribute("src") : "";

  if (!video || !cueList || !saveBtn || !saveStatus) {
    return;
  }

  const cues = data.cues.map((cue) => ({ ...cue }));
  let activeIndex = -1;

  const tcToSeconds = (timecode) => {
    const m = timecode.match(/^(\d{2}):(\d{2}):(\d{2}),(\d{3})$/);
    if (!m) {
      return NaN;
    }
    return Number(m[1]) * 3600 + Number(m[2]) * 60 + Number(m[3]) + Number(m[4]) / 1000;
  };

  const renderCue = (cue, idx) => {
    const row = document.createElement("div");
    row.className = "cue-row";
    row.dataset.index = String(idx);

    const rowHead = document.createElement("div");
    rowHead.className = "cue-row-head";

    const idxBadge = document.createElement("span");
    idxBadge.className = "idx";
    idxBadge.textContent = String(idx + 1);

    const jump = document.createElement("button");
    jump.type = "button";
    jump.className = "mini-btn";
    jump.textContent = "Jump";
    jump.addEventListener("click", () => {
      const sec = tcToSeconds(cues[idx].start);
      if (!Number.isNaN(sec)) {
        video.currentTime = sec;
        video.pause();
      }
    });

    rowHead.append(idxBadge, jump);

    const timeGrid = document.createElement("div");
    timeGrid.className = "time-grid";

    const startInput = document.createElement("input");
    startInput.value = cue.start;
    startInput.placeholder = "HH:MM:SS,mmm";
    startInput.addEventListener("input", (e) => {
      cues[idx].start = e.target.value.trim();
      setDirty();
    });

    const endInput = document.createElement("input");
    endInput.value = cue.end;
    endInput.placeholder = "HH:MM:SS,mmm";
    endInput.addEventListener("input", (e) => {
      cues[idx].end = e.target.value.trim();
      setDirty();
    });

    timeGrid.append(startInput, endInput);

    const textArea = document.createElement("textarea");
    textArea.value = cue.text;
    textArea.rows = 3;
    textArea.addEventListener("input", (e) => {
      cues[idx].text = e.target.value;
      setDirty();
    });

    row.append(rowHead, timeGrid, textArea);
    return row;
  };

  const renderList = () => {
    cueList.innerHTML = "";
    cues.forEach((cue, idx) => cueList.append(renderCue(cue, idx)));
  };

  const setDirty = () => {
    saveStatus.textContent = "Unsaved changes";
    saveStatus.classList.add("warn");
  };

  const setSaved = (msg) => {
    saveStatus.textContent = msg;
    saveStatus.classList.remove("warn");
  };

  const highlightActiveCue = () => {
    const now = video.currentTime;
    let nextActive = -1;

    for (let i = 0; i < cues.length; i += 1) {
      const start = tcToSeconds(cues[i].start);
      const end = tcToSeconds(cues[i].end);
      if (!Number.isNaN(start) && !Number.isNaN(end) && now >= start && now <= end) {
        nextActive = i;
        break;
      }
    }

    if (nextActive === activeIndex) {
      return;
    }

    if (activeIndex >= 0) {
      const oldEl = cueList.querySelector(`.cue-row[data-index="${activeIndex}"]`);
      if (oldEl) {
        oldEl.classList.remove("active");
      }
    }

    activeIndex = nextActive;
    if (activeIndex >= 0) {
      const activeEl = cueList.querySelector(`.cue-row[data-index="${activeIndex}"]`);
      if (activeEl) {
        activeEl.classList.add("active");
        activeEl.scrollIntoView({ block: "center", inline: "nearest", behavior: "auto" });
      }
    }
  };

  const save = async () => {
    saveBtn.disabled = true;
    saveBtn.textContent = "Saving...";

    try {
      const res = await fetch("/api/srt/save", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          srt_path: data.srtPath,
          media_dir: data.mediaDir,
          cues
        })
      });
      const payload = await res.json();
      if (!res.ok || !payload.ok) {
        throw new Error(payload.message || "Save failed");
      }

      setSaved("Saved");
      if (track && trackBaseUrl) {
        const joiner = trackBaseUrl.includes("?") ? "&" : "?";
        const fresh = `${trackBaseUrl}${joiner}v=${Date.now()}`;
        track.src = fresh;
        video.load();
      }
    } catch (err) {
      setSaved(`Save failed: ${err.message}`);
      saveStatus.classList.add("warn");
    } finally {
      saveBtn.disabled = false;
      saveBtn.textContent = "Save SRT";
    }
  };

  renderList();
  video.addEventListener("timeupdate", highlightActiveCue);
  saveBtn.addEventListener("click", save);
})();
