(function () {
  function parseInterval(trigger) {
    var match = trigger.match(/every\s+(\d+)(ms|s)/i);
    if (!match) return null;
    var value = parseInt(match[1], 10);
    var unit = match[2].toLowerCase();
    if (Number.isNaN(value)) return null;
    return unit === "ms" ? value : value * 1000;
  }

  function swapContent(target, html, swap) {
    if (swap === "outerHTML") {
      target.outerHTML = html;
      return;
    }
    target.innerHTML = html;
  }

  function requestAndSwap(el) {
    var url = el.getAttribute("hx-get");
    if (!url) return;

    var targetSelector = el.getAttribute("hx-target");
    var swap = el.getAttribute("hx-swap") || "innerHTML";
    var target = targetSelector ? document.querySelector(targetSelector) : el;

    if (!target) return;

    fetch(url, {
      headers: {
        "HX-Request": "true"
      }
    })
      .then(function (res) {
        return res.text();
      })
      .then(function (html) {
        swapContent(target, html, swap);
        scan(target);
      })
      .catch(function () {
        // Fail silently; next poll will retry.
      });
  }

  function setupElement(el) {
    if (el.dataset.hxBound === "true") return;
    el.dataset.hxBound = "true";

    var trigger = el.getAttribute("hx-trigger") || "click";
    var hasLoad = trigger.indexOf("load") !== -1;
    var interval = parseInterval(trigger);

    if (trigger.indexOf("click") !== -1) {
      el.addEventListener("click", function (event) {
        event.preventDefault();
        requestAndSwap(el);
      });
    }

    if (hasLoad) {
      requestAndSwap(el);
    }

    if (interval !== null) {
      window.setInterval(function () {
        requestAndSwap(el);
      }, interval);
    }
  }

  function scan(root) {
    var scope = root || document;
    var elements = scope.querySelectorAll("[hx-get]");
    for (var i = 0; i < elements.length; i += 1) {
      setupElement(elements[i]);
    }
  }

  document.addEventListener("DOMContentLoaded", function () {
    scan(document);
  });
})();
