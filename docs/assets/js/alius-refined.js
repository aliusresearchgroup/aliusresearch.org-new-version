(function () {
  "use strict";

  function onReady(fn) {
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", fn, { once: true });
    } else {
      fn();
    }
  }

  var _decodeEl = null;
  function decodeEntities(value) {
    if (value == null) return "";
    if (!_decodeEl) {
      _decodeEl = document.createElement("textarea");
    }
    _decodeEl.innerHTML = String(value);
    return _decodeEl.value;
  }

  function toSlug(text) {
    return String(text || "")
      .toLowerCase()
      .replace(/[\u200b\u200c\u200d\ufeff]/g, "")
      .replace(/&[a-z0-9#]+;/gi, "-")
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "");
  }

  function safeText(value) {
    return decodeEntities(String(value || "")).replace(/\s+/g, " ").trim();
  }

  function normalizePath(pathname) {
    if (!pathname) return "/";
    return pathname.replace(/\/+$/, "") || "/";
  }

  function normalizeBasePath(base) {
    if (!base) return "";
    if (base === "/") return "";
    return ("/" + String(base).replace(/^\/+|\/+$/g, "")).replace(/\/+$/, "");
  }

  function getBasePathFromBody() {
    var body = document.body;
    if (!body) return "";

    var explicit = normalizeBasePath(body.getAttribute("data-alius-base") || "");
    if (explicit) return explicit;

    var canonical = body.getAttribute("data-alius-canonical") || "";
    var path = window.location.pathname || "/";
    if (canonical && canonical !== "/") {
      var idx = path.indexOf(canonical);
      if (idx > 0) {
        return normalizeBasePath(path.slice(0, idx));
      }
    }

    if (canonical === "/") {
      var p = path.replace(/\/index\.html$/i, "");
      p = p.replace(/\/+$/, "");
      return p && p !== "/" ? normalizeBasePath(p) : "";
    }

    return "";
  }

  function withBasePath(pathname) {
    var p = String(pathname || "");
    if (!p) return p;
    if (/^(?:[a-z]+:)?\/\//i.test(p) || /^(?:mailto|tel|javascript):/i.test(p) || p.charAt(0) === "#") {
      return p;
    }
    if (p.charAt(0) !== "/") {
      return p;
    }
    return (getBasePathFromBody() || "") + p;
  }

  function humanizeSlug(value) {
    var txt = safeText(value).replace(/[_-]+/g, " ").trim();
    if (!txt) return "";
    return txt.replace(/\b([a-z])/gi, function (_, c) {
      return c.toUpperCase();
    });
  }

  function getHubPathByMenuLabel(label) {
    var key = safeText(label).toLowerCase();
    switch (key) {
      case "home":
        return "/";
      case "about":
        return "/about/";
      case "team":
        return "/about/team/team/";
      case "bulletin":
        return "/bulletin/";
      case "journal clubs":
        return "/events/journal-club/";
      case "events":
        return "/events/events/";
      case "membership":
        return "/community/membership-renewal-894351/";
      default:
        return "";
    }
  }

  function rewriteTopMenuLinksToHubs() {
    var navSelectors = [
      "#navigation > ul.wsite-menu-default > li > a.wsite-menu-item",
      "#navmobile > ul.wsite-menu-default > li > a.wsite-menu-item"
    ];
    navSelectors.forEach(function (sel) {
      document.querySelectorAll(sel).forEach(function (a) {
        var hubPath = getHubPathByMenuLabel(a.textContent || "");
        if (hubPath) {
          a.setAttribute("href", withBasePath(hubPath));
        }
      });
    });
  }

  function disableDropdownMenus() {
    document.querySelectorAll("#navigation .wsite-menu-wrap, #navmobile .wsite-menu-wrap").forEach(function (wrap) {
      wrap.setAttribute("aria-hidden", "true");
      wrap.style.display = "none";
      wrap.querySelectorAll("a").forEach(function (a) {
        a.setAttribute("tabindex", "-1");
      });
    });
    document.querySelectorAll(".wsite-menu-arrow").forEach(function (el) {
      el.setAttribute("aria-hidden", "true");
    });
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

  function removeKofiEmbeds() {
    var removeSelectors = [
      "script[src*='storage.ko-fi.com']",
      "script[src*='ko-fi.com']",
      "iframe[src*='ko-fi.com']",
      "iframe#kofiframe",
      "[id*='kofi-widget']",
      "[class*='kofi-widget']"
    ];

    removeSelectors.forEach(function (sel) {
      document.querySelectorAll(sel).forEach(function (el) {
        var container = el.closest && el.closest(".wcustomhtml");
        if (container) container.classList.add("alius-kofi-removed");
        el.remove();
      });
    });

    document.querySelectorAll("script:not([src])").forEach(function (el) {
      var txt = (el.textContent || "").toLowerCase();
      if (txt.indexOf("kofiwidgetoverlay") >= 0 || txt.indexOf("ko-fi") >= 0) {
        var container = el.closest && el.closest(".wcustomhtml");
        if (container) container.classList.add("alius-kofi-removed");
        el.remove();
      }
    });

    document.querySelectorAll(".wcustomhtml").forEach(function (block) {
      var html = (block.innerHTML || "").toLowerCase();
      var text = (block.textContent || "").toLowerCase();
      if (html.indexOf("ko-fi") >= 0 || html.indexOf("kofi") >= 0 || text.indexOf("support us") >= 0) {
        block.classList.add("alius-kofi-removed");
      }
      var hasMeaningfulContent = block.querySelector("img, video, audio, iframe, object, embed, a, p, h1, h2, h3, h4, h5, h6");
      if (!hasMeaningfulContent && safeText(block.textContent || "").length === 0) {
        block.classList.add("alius-kofi-removed");
      }
    });
  }

  function observeKofiArtifacts() {
    if (!window.MutationObserver || !document.documentElement) return;
    var timer = null;
    var observer = new MutationObserver(function () {
      if (timer) return;
      timer = window.setTimeout(function () {
        timer = null;
        removeKofiEmbeds();
      }, 50);
    });
    observer.observe(document.documentElement, { childList: true, subtree: true });
    window.setTimeout(function () {
      observer.disconnect();
    }, 15000);
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
    if (body.classList.contains("alius-scroll-hub-page")) return;
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
    var url = withBasePath("/assets/data/alius-page-index.json");
    return fetch(url, { credentials: "same-origin" }).then(function (r) {
      if (!r.ok) throw new Error("Failed to load page index: " + r.status);
      return r.json();
    });
  }

  function sortPagesByTitle(a, b) {
    return safeText(a && a.title).localeCompare(safeText(b && b.title));
  }

  function buildSectionLinks() {
    var body = document.body;
    if (!body || document.querySelector(".alius-section-links")) return;
    if (body.classList.contains("alius-scroll-hub-page")) return;

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
          .sort(sortPagesByTitle)
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
          a.href = withBasePath(p.canonical_path);
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

  function getHubConfig(canonicalPath) {
    switch (normalizePath(canonicalPath)) {
      case "/":
        return {
          key: "home",
          title: "ALIUS Site Menu",
          subtitle: "A one-page overview of the main sections of the website. Use the side menu to jump smoothly through the sections.",
          hideOriginalContent: true
        };
      case "/about/":
        return {
          key: "about",
          title: "About Menu",
          subtitle: "Overview pages and related information for the ALIUS group.",
          hideOriginalContent: true
        };
      case "/about/team/team/":
        return {
          key: "team",
          title: "Team Menu",
          subtitle: "Browse coordinators, members, and team-related pages in a single scrollable menu.",
          hideOriginalContent: true
        };
      case "/bulletin/":
        return {
          key: "bulletin",
          title: "Bulletin Menu",
          subtitle: "Browse bulletin issues, interviews, and bulletin-related pages in one place.",
          hideOriginalContent: true
        };
      case "/events/journal-club/":
        return {
          key: "journal-clubs",
          title: "Journal Clubs Menu",
          subtitle: "Journal Club pages collected into a single smooth-scrolling menu.",
          hideOriginalContent: true
        };
      case "/events/events/":
        return {
          key: "events",
          title: "Events Menu",
          subtitle: "Event pages organized by topic, year, and type for easier browsing.",
          hideOriginalContent: true
        };
      case "/community/membership-renewal-894351/":
        return {
          key: "membership",
          title: "Membership Menu",
          subtitle: "Membership and community pages organized into a single menu view.",
          hideOriginalContent: true
        };
      default:
        return null;
    }
  }

  function buildHomeHubGroups(pages) {
    var defs = [
      {
        label: "About",
        intro: "Mission, background, and general information.",
        hubPath: "/about/",
        filter: function (p) {
          return p.section === "about" && p.canonical_path.indexOf("/about/team/") !== 0;
        }
      },
      {
        label: "Team",
        intro: "Coordinators, members, and team-related pages.",
        hubPath: "/about/team/team/",
        filter: function (p) {
          return p.section === "about" && p.canonical_path.indexOf("/about/team/") === 0;
        }
      },
      {
        label: "Bulletin",
        intro: "Issues, interviews, and bulletin archives.",
        hubPath: "/bulletin/",
        filter: function (p) {
          return p.section === "bulletin";
        }
      },
      {
        label: "Journal Clubs",
        intro: "Journal club listings and related pages.",
        hubPath: "/events/journal-club/",
        filter: function (p) {
          return p.section === "events" && p.canonical_path.indexOf("/events/journal-club") === 0;
        }
      },
      {
        label: "Events",
        intro: "Conferences, workshops, and event pages.",
        hubPath: "/events/events/",
        filter: function (p) {
          return p.section === "events" && p.canonical_path.indexOf("/events/journal-club") !== 0;
        }
      },
      {
        label: "Membership",
        intro: "Membership and community pages.",
        hubPath: "/community/membership-renewal-894351/",
        filter: function (p) {
          return p.section === "community";
        }
      }
    ];

    return defs
      .map(function (def) {
        var items = pages.filter(def.filter).sort(sortPagesByTitle);
        var hubPage = pages.find(function (p) {
          return p.canonical_path === def.hubPath;
        });
        var dedup = [];
        if (hubPage) dedup.push(hubPage);
        items.forEach(function (p) {
          if (!dedup.some(function (x) { return x.canonical_path === p.canonical_path; })) {
            dedup.push(p);
          }
        });
        return {
          id: toSlug(def.label) || "section",
          label: def.label,
          intro: def.intro,
          items: dedup
        };
      })
      .filter(function (g) {
        return g.items && g.items.length > 0;
      });
  }

  function buildGroupedHubPages(config, pages, currentCanonical) {
    var filtered = pages.filter(function (p) {
      if (!p || !p.canonical_path || !p.title) return false;
      if (p.canonical_path === currentCanonical) return false;
      switch (config.key) {
        case "about":
          return p.section === "about";
        case "team":
          return p.section === "about" && p.canonical_path.indexOf("/about/team/") === 0;
        case "bulletin":
          return p.section === "bulletin";
        case "journal-clubs":
          return p.section === "events" && p.canonical_path.indexOf("/events/journal-club") === 0;
        case "events":
          return p.section === "events" && p.canonical_path.indexOf("/events/journal-club") !== 0;
        case "membership":
          return p.section === "community";
        default:
          return false;
      }
    });

    var groupsByName = {};
    filtered.forEach(function (p) {
      var name = "Pages";
      if (config.key === "about") {
        name = p.canonical_path.indexOf("/about/team/") === 0 ? "Team Pages" : (humanizeSlug(p.subcategory) || "About");
      } else if (config.key === "team") {
        if (safeText(p.title).toLowerCase() === "team") {
          name = "Team Pages";
        } else {
          name = humanizeSlug(p.subcategory) || "Team Pages";
        }
      } else if (config.key === "bulletin") {
        name = humanizeSlug(p.subcategory) || "Bulletin";
      } else if (config.key === "journal-clubs") {
        name = "Journal Clubs";
      } else if (config.key === "events") {
        name = humanizeSlug(p.subcategory) || "Events";
      } else if (config.key === "membership") {
        name = humanizeSlug(p.subcategory) || "Membership";
      }
      if (!groupsByName[name]) groupsByName[name] = [];
      groupsByName[name].push(p);
    });

    return Object.keys(groupsByName)
      .sort(function (a, b) { return a.localeCompare(b); })
      .map(function (name) {
        var items = groupsByName[name].sort(sortPagesByTitle);
        return {
          id: toSlug(name) || "group",
          label: name,
          intro: "",
          items: items
        };
      })
      .filter(function (g) { return g.items.length > 0; });
  }

  function makeEl(tag, className, text) {
    var el = document.createElement(tag);
    if (className) el.className = className;
    if (text != null) el.textContent = text;
    return el;
  }

  function renderHubItem(page) {
    var card = makeEl("article", "alius-scroll-hub-item");
    var titleWrap = makeEl("h4", "alius-scroll-hub-item-title");
    var link = makeEl("a", "alius-scroll-hub-item-link", safeText(page.title) || "Open page");
    link.href = withBasePath(page.canonical_path);
    titleWrap.appendChild(link);

    var meta = makeEl("div", "alius-scroll-hub-item-meta");
    var section = safeText(page.section);
    var subcat = safeText(page.subcategory);
    meta.textContent = [humanizeSlug(section), humanizeSlug(subcat)].filter(Boolean).join(" / ");

    var desc = makeEl("p", "alius-scroll-hub-item-desc");
    desc.textContent = safeText(page.description) || "Open page";

    var cta = makeEl("a", "alius-scroll-hub-item-cta", "Open page");
    cta.href = withBasePath(page.canonical_path);

    card.appendChild(titleWrap);
    if (safeText(meta.textContent)) {
      card.appendChild(meta);
    }
    card.appendChild(desc);
    card.appendChild(cta);
    return card;
  }

  function renderHubPage(config, pages) {
    var body = document.body;
    var currentCanonical = body.getAttribute("data-alius-canonical") || "/";
    var currentMeta = pages.find(function (p) {
      return p && p.canonical_path === currentCanonical;
    }) || null;

    var groups = config.key === "home"
      ? buildHomeHubGroups(pages)
      : buildGroupedHubPages(config, pages, currentCanonical);

    if (!groups.length) return;

    var wrapper = makeEl("section", "alius-scroll-hub");
    wrapper.setAttribute("aria-labelledby", "alius-scroll-hub-title");

    var container = makeEl("div", "container alius-scroll-hub-container");
    var grid = makeEl("div", "alius-scroll-hub-grid");

    var sidebar = makeEl("aside", "alius-scroll-hub-sidebar");
    var sidebarInner = makeEl("div", "alius-scroll-hub-sidebar-inner");
    var sidebarTitle = makeEl("h2", "alius-scroll-hub-sidebar-title", "Jump");
    var sidebarNav = makeEl("nav", "alius-scroll-hub-sidebar-nav");
    sidebarNav.setAttribute("aria-label", "Section navigation");
    var sidebarList = makeEl("ul", "alius-scroll-hub-sidebar-list");

    var main = makeEl("div", "alius-scroll-hub-main");
    var header = makeEl("header", "alius-scroll-hub-header");
    var title = makeEl("h2", "alius-scroll-hub-title", config.title);
    title.id = "alius-scroll-hub-title";

    var subtitleText = config.subtitle;
    if (currentMeta && safeText(currentMeta.description)) {
      subtitleText = safeText(currentMeta.description);
    }
    var subtitle = makeEl("p", "alius-scroll-hub-subtitle", subtitleText || "Browse this section as a one-page menu.");
    header.appendChild(title);
    header.appendChild(subtitle);
    main.appendChild(header);

    groups.forEach(function (group, index) {
      var groupId = "alius-hub-group-" + (toSlug(group.id || group.label) || String(index + 1));
      var li = makeEl("li", "alius-scroll-hub-sidebar-item");
      var navLink = makeEl("a", "alius-scroll-hub-sidebar-link", group.label);
      navLink.href = "#" + groupId;
      li.appendChild(navLink);
      sidebarList.appendChild(li);

      var section = makeEl("section", "alius-scroll-hub-group");
      section.id = groupId;
      section.setAttribute("data-hub-section-id", groupId);

      var groupHeader = makeEl("div", "alius-scroll-hub-group-header");
      var groupTitle = makeEl("h3", "alius-scroll-hub-group-title", group.label);
      groupHeader.appendChild(groupTitle);
      if (group.intro) {
        groupHeader.appendChild(makeEl("p", "alius-scroll-hub-group-intro", group.intro));
      }
      section.appendChild(groupHeader);

      var itemsWrap = makeEl("div", "alius-scroll-hub-items");
      group.items.forEach(function (page) {
        itemsWrap.appendChild(renderHubItem(page));
      });
      section.appendChild(itemsWrap);
      main.appendChild(section);
    });

    sidebarNav.appendChild(sidebarList);
    sidebarInner.appendChild(sidebarTitle);
    sidebarInner.appendChild(sidebarNav);
    sidebar.appendChild(sidebarInner);

    grid.appendChild(sidebar);
    grid.appendChild(main);
    container.appendChild(grid);
    wrapper.appendChild(container);

    var contentWrapper = document.querySelector("#content-wrapper");
    var wsiteContent = document.querySelector("#wsite-content");
    if (!contentWrapper) return;

    if (config.hideOriginalContent && wsiteContent) {
      body.classList.add("alius-scroll-hub-page");
      wsiteContent.classList.add("alius-scroll-hub-source");
    }

    contentWrapper.insertBefore(wrapper, wsiteContent || null);
    initHubScrollSpy(wrapper);
  }

  function initHubScrollSpy(wrapper) {
    var links = Array.prototype.slice.call(wrapper.querySelectorAll(".alius-scroll-hub-sidebar-link"));
    if (!links.length) return;

    function setActiveById(id) {
      links.forEach(function (a) {
        var active = a.getAttribute("href") === "#" + id;
        a.classList.toggle("is-active", active);
        if (active) a.setAttribute("aria-current", "true");
        else a.removeAttribute("aria-current");
      });
    }

    var first = links[0].getAttribute("href");
    if (first && first.charAt(0) === "#") {
      setActiveById(first.slice(1));
    }

    if (!window.IntersectionObserver) return;
    var sections = Array.prototype.slice.call(wrapper.querySelectorAll(".alius-scroll-hub-group"));
    var observer = new IntersectionObserver(
      function (entries) {
        entries.forEach(function (entry) {
          if (entry.isIntersecting) {
            setActiveById(entry.target.id);
          }
        });
      },
      {
        root: null,
        rootMargin: "-25% 0px -60% 0px",
        threshold: 0.05
      }
    );
    sections.forEach(function (s) { observer.observe(s); });
  }

  function buildHubPageIfNeeded() {
    var body = document.body;
    if (!body) return Promise.resolve(false);
    var currentCanonical = body.getAttribute("data-alius-canonical") || "/";
    var config = getHubConfig(currentCanonical);
    if (!config) return Promise.resolve(false);

    return loadPageIndex()
      .then(function (pages) {
        renderHubPage(config, pages || []);
        return true;
      })
      .catch(function () {
        return false;
      });
  }

  onReady(function () {
    if (!document.body || !document.body.classList.contains("alius-refined")) {
      return;
    }

    document.documentElement.classList.add("alius-refined-js");
    removeKofiEmbeds();
    observeKofiArtifacts();
    rewriteTopMenuLinksToHubs();
    disableDropdownMenus();
    setNavState();
    hardenExternalLinks();

    buildHubPageIfNeeded().then(function (isHub) {
      if (!isHub) {
        buildToc();
        buildSectionLinks();
      }
    });
  });
})();
