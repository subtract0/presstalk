/* A finite, illustrative animation. It never requests audio or sends data. */
(() => {
  const canvas = document.querySelector(".demo-canvas");
  if (!canvas) return;
  const controls = document.querySelector(".demo-controls");
  const pause = document.querySelector("[data-demo-pause]");
  const replay = document.querySelector("[data-demo-replay]");
  const label = document.querySelector(".status-label");
  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
  const german = document.documentElement.lang === "de";
  const labels = german
    ? { ready: "Fn gedrückt halten", listening: "Dein Satz …", processing: "Loslassen", complete: "Deine Worte. Geschrieben.", pause: "Pause", resume: "Fortsetzen" }
    : { ready: "Hold Fn", listening: "Say your sentence…", processing: "Let go", complete: "Your words. Right there.", pause: "Pause", resume: "Resume" };
  let elapsed = 0;
  let lastFrame = 0;
  let frameId = null;
  let running = false;
  let finished = true;
  let started = false;

  function phase(name) {
    if (canvas.dataset.phase === name) return;
    canvas.dataset.phase = name;
    label.textContent = labels[name];
  }

  function stop() {
    if (frameId !== null) cancelAnimationFrame(frameId);
    frameId = null;
    running = false;
  }

  function finish() {
    stop();
    finished = true;
    phase("complete");
    canvas.classList.remove("is-paused");
    pause.disabled = true;
    pause.textContent = labels.pause;
  }

  function tick(now) {
    if (!running) return;
    if (lastFrame) elapsed += now - lastFrame;
    lastFrame = now;
    // The result appears as one complete insertion; duration is illustrative.
    phase(elapsed < 850 ? "ready" : elapsed < 4450 ? "listening" : elapsed < 5150 ? "processing" : "complete");
    if (elapsed >= 8200) { finish(); return; }
    frameId = requestAnimationFrame(tick);
  }

  function resume() {
    running = true;
    lastFrame = 0;
    canvas.classList.remove("is-paused");
    pause.textContent = labels.pause;
    frameId = requestAnimationFrame(tick);
  }

  function play() {
    if (reducedMotion.matches) return;
    stop();
    started = true;
    finished = false;
    elapsed = 0;
    phase("ready");
    controls.hidden = false;
    pause.disabled = false;
    resume();
  }

  function suspend() {
    stop();
    canvas.classList.add("is-paused");
    pause.textContent = labels.resume;
  }

  pause.addEventListener("click", () => {
    if (finished) return;
    if (running) suspend(); else resume();
  });
  replay.addEventListener("click", play);
  document.addEventListener("visibilitychange", () => {
    if (document.hidden && running) suspend();
  });
  reducedMotion.addEventListener("change", () => {
    if (reducedMotion.matches) {
      finish();
      controls.hidden = true;
    } else {
      controls.hidden = false;
      pause.disabled = true;
    }
  });

  if (reducedMotion.matches) return;
  controls.hidden = false;
  if ("IntersectionObserver" in window) {
    const observer = new IntersectionObserver((entries) => {
      if (entries.some((entry) => entry.isIntersecting) && !started) {
        play();
        observer.disconnect();
      }
    }, { threshold: 0.35 });
    observer.observe(canvas);
  } else {
    play();
  }
})();
