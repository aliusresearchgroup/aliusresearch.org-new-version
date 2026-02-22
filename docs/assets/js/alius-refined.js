(function () {
  "use strict";

  function onReady(fn) {
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", fn, { once: true });
    } else {
      fn();
    }
  }

  function toSlug(text) {
    return String(text || "")
      .toLowerCase()
      .replace(/[\u200b\u200c\u200d\ufeff]/g, "")
      .replace(/&[a-z0-9#]+;/gi, "-")
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "");
  }

  function getBasePathFromBody() {
    var canonical = document.body && document.body.getAttribute("data-alius-canonical");
    if (!canonical) {
      return "";
    }
    var path = window.location.pathname || "/";
    var idx = path.indexOf(canonical);
    if (idx > 0) {
      return path.slice(0, idx);
    }
    return "";
  }

  function normalizePath(pathname) {
    if (!pathname) return "/";
    return pathname.replace(/\/+$/, "") || "/";
  }

  function setNavState() {
    var navs = document.querySelectorAll("#navigation, #navmobile");
    navs.forEach(function (nav) {
      var activeWrap = nav.querySelector("li#active");
      if (activeWrap) {
        activeWrap.classList.add("alius-nav-active");
        var activeLink = activeWrap.querySelector("a.wsite-menu-item, a.wsite-menu-subitem");
        if (activeLink) {
          activeLink.setAttribute("aria-current", "page");
        }
      }
      nav.querySelectorAll("li").forEach(function (li) {
        if (li.querySelector(".wsite-menu-wrap")) {
          li.classList.add("alius-nav-has-children");
        }
      });
    });
  }

  function ensureHeadingIds() {
    var seen = new Set();
    var headings = Array.prototype.slice.call(
      document.querySelectorAll("#wsite-content h2.wsite-content-title, #wsite-content h2")
    );
    headings.forEach(function (h, index) {
      var text = (h.textContent || "").replace(/\s+/g, " ").trim();
      if (!text) return;
      if (!h.id) {
        var base = "section-" + (toSlug(text) || String(index + 1));
        var id = base;
        var n = 2;
        while (seen.has(id) || document.getElementById(id)) {
          id = base + "-" + n++;
        }
        h.id = id;
      }
      seen.add(h.id);
    });
    return headings;
  }

  function buildToc() {
    var body = document.body;
    if (!body || body.getAttribute("data-alius-canonical") === "/") return;
    if (document.querySelector(".alius-page-toc")) return;

    var headings = ensureHeadingIds().filter(function (h) {
      var text = (h.textContent || "").replace(/\s+/g, " ").trim();
      return text && text.length > 1;
    });

    if (headings.length < 3) return;

    var toc = document.createElement("aside");
    toc.className = "alius-page-toc";
    toc.setAttribute("aria-labelledby", "alius-page-toc-title");
    var inner = document.createElement("div");
    inner.className = "alius-page-toc-inner";
    var title = document.createElement("h2");
    title.id = "alius-page-toc-title";
    title.className = "alius-page-toc-title";
    title.textContent = "On this page";
    var list = document.createElement("ol");
    list.className = "alius-page-toc-list";

    headings.slice(0, 12).forEach(function (h) {
      var li = document.createElement("li");
      var a = document.createElement("a");
      a.href = "#" + h.id;
      a.textContent = (h.textContent || "").replace(/\s+/g, " ").trim();
      li.appendChild(a);
      list.appendChild(li);
    });

    inner.appendChild(title);
    inner.appendChild(list);
    toc.appendChild(inner);

    var context = document.querySelector(".alius-page-context");
    if (context && context.nextSibling) {
      context.parentNode.insertBefore(toc, context.nextSibling);
      return;
    }

    var contentWrapper = document.querySelector("#content-wrapper");
    if (contentWrapper && contentWrapper.firstChild) {
      contentWrapper.insertBefore(toc, contentWrapper.firstChild);
    }
  }

  function safeText(value) {
    return String(value || "").replace(/\s+/g, " ").trim();
  }

  function isSectionLanding(meta) {
    if (!meta || !meta.canonical_path) return false;
    var landingPaths = new Set([
      "/about/",
      "/bulletin/",
      "/research/",
      "/events/events/",
      "/media/media/",
      "/community/become-a-member/"
    ]);
    return landingPaths.has(meta.canonical_path);
  }

  function loadPageIndex() {
    var base = getBasePathFromBody();
    var url = (base || "") + "/assets/data/alius-page-index.json";
    return fetch(url, { credentials: "same-origin" })
      .then(function (r) {
        if (!r.ok) throw new Error("Failed to load page index: " + r.status);
        return r.json();
      });
  }

  function buildSectionLinks() {
    var body = document.body;
    if (!body || document.querySelector(".alius-section-links")) return;

    var currentCanonical = body.getAttribute("data-alius-canonical") || "";
    var currentSection = body.getAttribute("data-alius-section") || "";
    if (!currentCanonical || !currentSection) return;

    loadPageIndex()
      .then(function (pages) {
        var currentMeta = pages.find(function (p) {
          return p && p.canonical_path === currentCanonical;
        });
        if (!isSectionLanding(currentMeta)) return;

        var items = pages
          .filter(function (p) {
            if (!p || p.section !== currentSection) return false;
            if (p.canonical_path === currentCanonical) return false;
            if (!p.title) return false;
            if (p.section === "archive") return false;
            return true;
          })
          .sort(function (a, b) {
            return safeText(a.title).localeCompare(safeText(b.title));
          })
          .slice(0, 8);

        if (!items.length) return;

        var panel = document.createElement("section");
        panel.className = "alius-section-links";
        panel.setAttribute("aria-labelledby", "alius-section-links-title");
        var inner = document.createElement("div");
        inner.className = "alius-section-links-inner";
        var title = document.createElement("h2");
        title.id = "alius-section-links-title";
        title.className = "alius-section-links-title";
        title.textContent = "Explore this section";
        var grid = document.createElement("div");
        grid.className = "alius-section-links-grid";

        items.forEach(function (p) {
          var a = document.createElement("a");
          a.className = "alius-section-link";
          a.href = (getBasePathFromBody() || "") + p.canonical_path;
          var t = document.createElement("span");
          t.className = "alius-section-link-title";
          t.textContent = safeText(p.title);
          var d = document.createElement("span");
          d.className = "alius-section-link-desc";
          d.textContent = safeText(p.description) || "Open page";
          a.appendChild(t);
          a.appendChild(d);
          grid.appendChild(a);
        });

        inner.appendChild(title);
        inner.appendChild(grid);
        panel.appendChild(inner);

        var context = document.querySelector(".alius-page-context");
        var toc = document.querySelector(".alius-page-toc");
        if (toc && toc.parentNode) {
          toc.parentNode.insertBefore(panel, toc.nextSibling);
          return;
        }
        if (context && context.parentNode) {
          context.parentNode.insertBefore(panel, context.nextSibling);
          return;
        }
        var contentWrapper = document.querySelector("#content-wrapper");
        if (contentWrapper) {
          contentWrapper.insertBefore(panel, contentWrapper.firstChild);
        }
      })
      .catch(function () {
        return;
      });
  }

  function hardenExternalLinks() {
    document.querySelectorAll('a[target="_blank"]').forEach(function (a) {
      var rel = a.getAttribute("rel") || "";
      var tokens = rel.split(/\s+/).filter(Boolean);
      if (tokens.indexOf("noopener") < 0) tokens.push("noopener");
      if (tokens.indexOf("noreferrer") < 0) tokens.push("noreferrer");
      a.setAttribute("rel", tokens.join(" "));
    });
  }

  onReady(function () {
    if (!document.body || !document.body.classList.contains("alius-refined")) {
      return;
    }
    document.documentElement.classList.add("alius-refined-js");
    setNavState();
    hardenExternalLinks();
    buildToc();
    buildSectionLinks();
  });
})();
