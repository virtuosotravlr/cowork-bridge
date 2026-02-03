(function () {
  function setupConfirmDialog() {
    var dialog = document.getElementById("confirm-dialog");
    if (!dialog) return;

    var messageEl = dialog.querySelector("[data-confirm-message]");
    var confirmButton = dialog.querySelector("[data-confirm-ok]");
    var cancelButton = dialog.querySelector("[data-confirm-cancel]");
    var pendingForm = null;

    function setConfirmedAndSubmit(form) {
      var input = form.querySelector("input[name='confirmed']");
      if (!input) {
        input = document.createElement("input");
        input.type = "hidden";
        input.name = "confirmed";
        form.appendChild(input);
      }
      input.value = "true";
      form.dataset.confirmed = "true";
      form.submit();
    }

    function showDialog(form) {
      var msg = form.getAttribute("data-confirm") || "Are you sure?";
      if (messageEl) messageEl.textContent = msg;
      pendingForm = form;
      if (typeof dialog.showModal === "function") {
        dialog.showModal();
      } else if (window.confirm(msg)) {
        setConfirmedAndSubmit(form);
      }
    }

    document.addEventListener("submit", function (event) {
      var form = event.target;
      if (!form || !form.matches("form[data-confirm]")) return;
      if (form.dataset.confirmed === "true") return;
      event.preventDefault();
      showDialog(form);
    });

    if (confirmButton) {
      confirmButton.addEventListener("click", function () {
        if (!pendingForm) return;
        var form = pendingForm;
        pendingForm = null;
        dialog.close();
        setConfirmedAndSubmit(form);
      });
    }

    if (cancelButton) {
      cancelButton.addEventListener("click", function () {
        pendingForm = null;
        dialog.close();
      });
    }
  }

  document.addEventListener("DOMContentLoaded", function () {
    setupConfirmDialog();
    setupThemeToggle();
    setupTabs();
  });

  function setupThemeToggle() {
    var toggle = document.getElementById("theme-toggle");
    if (!toggle) return;

    var stored = localStorage.getItem("ui-theme");
    if (stored === "light") {
      document.documentElement.dataset.theme = "light";
      toggle.checked = true;
    }

    toggle.addEventListener("change", function () {
      if (toggle.checked) {
        document.documentElement.dataset.theme = "light";
        localStorage.setItem("ui-theme", "light");
      } else {
        document.documentElement.dataset.theme = "dark";
        localStorage.setItem("ui-theme", "dark");
      }
    });
  }

  function setupTabs() {
    var groups = document.querySelectorAll("[data-tab-group]");
    groups.forEach(function (group) {
      var groupId = group.getAttribute("data-tab-group") || "default";
      var buttons = group.querySelectorAll("[data-tab]");
      var panels = group.querySelectorAll("[data-tab-panel]");

      function activate(tab) {
        buttons.forEach(function (btn) {
          btn.classList.toggle("active", btn.getAttribute("data-tab") === tab);
        });
        panels.forEach(function (panel) {
          panel.classList.toggle("active", panel.getAttribute("data-tab-panel") === tab);
        });
        localStorage.setItem("tab:" + groupId, tab);
      }

      var saved = localStorage.getItem("tab:" + groupId);
      if (saved) {
        activate(saved);
      } else if (buttons.length > 0) {
        activate(buttons[0].getAttribute("data-tab"));
      }

      buttons.forEach(function (btn) {
        btn.addEventListener("click", function () {
          activate(btn.getAttribute("data-tab"));
        });
      });
    });
  }
})();
