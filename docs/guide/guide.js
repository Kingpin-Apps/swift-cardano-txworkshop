// The guide's contents: open beside the text on wide screens, a bar that
// opens on narrow ones; the section being read is marked and its group opened.
(function () {
  const panel = document.getElementById("toc-panel");
  if (!panel) return;
  const wide = window.matchMedia("(min-width: 901px)");
  const summary = panel.querySelector(":scope > summary");
  const current = document.createElement("span");
  current.className = "toc-current";
  summary.append(current);

  const syncPanel = () => { panel.open = wide.matches; };
  syncPanel();
  wide.addEventListener("change", syncPanel);

  const links = new Map();
  for (const link of panel.querySelectorAll('a[href^="#"]')) {
    links.set(link.getAttribute("href").slice(1), link);
  }
  const headings = [...document.querySelectorAll(".doc h2[id], .doc h3[id]")].filter((h) => links.has(h.id));

  let marked = null;
  function mark(id) {
    const link = links.get(id);
    if (!link || link === marked) return;
    marked?.removeAttribute("aria-current");
    link.setAttribute("aria-current", "location");
    marked = link;
    current.textContent = link.textContent;
    const group = link.closest(".toc-group");
    for (const other of panel.querySelectorAll(".toc-group")) {
      if (other !== group && !other.dataset.pinned) other.open = false;
    }
    if (group) group.open = true;
    if (wide.matches) link.scrollIntoView({ block: "nearest" });
  }

  // The section being read is the last heading above a line a fifth of the
  // way down the window.
  let ticking = false;
  function update() {
    ticking = false;
    const line = window.innerHeight * 0.2;
    let active = headings[0];
    for (const heading of headings) {
      if (heading.getBoundingClientRect().top <= line) active = heading; else break;
    }
    if (active) mark(active.id);
  }
  window.addEventListener("scroll", () => {
    if (!ticking) { ticking = true; requestAnimationFrame(update); }
  }, { passive: true });
  update();

  // A group opened by hand stays open while reading elsewhere.
  for (const group of panel.querySelectorAll(".toc-group")) {
    group.querySelector("summary").addEventListener("click", (event) => {
      if (event.target.closest("a")) return;
      if (group.open) delete group.dataset.pinned; else group.dataset.pinned = "true";
    });
  }

  // On a narrow screen, following a link closes the contents.
  panel.addEventListener("click", (event) => {
    const link = event.target.closest('a[href^="#"]');
    if (link && !wide.matches) panel.open = false;
  });
})();
