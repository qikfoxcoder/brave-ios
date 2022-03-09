"use strict";

Object.defineProperty(window.__firefox__, "AdblockRustInjector", {
  enumerable: false,
  configurable: false,
  writable: false,
  value: {}
});

Object.defineProperty(window.__firefox__.AdblockRustInjector, "applyFilter", {
  enumerable: false,
  configurable: false,
  writable: false,
  value: function(json) {
      var head = document.head || document.getElementsByTagName('head')[0];
      if (head == null) {
          return;
      }
      
      const obj = JSON.parse(atob(json));
      const hide_selectors = obj.hide_selectors;
      const style_selectors = obj.style_selectors;
      const injected_script = obj.injected_script;
      
      // CSS Rules
      var rules = "";
      var style = document.createElement('style');
      style.type = 'text/css';

      for (const selector of hide_selectors) {
          rules += selector + "{display: none !important}"
      }
      
      for (const [key, value] of Object.entries(style_selectors)) {
          var subRules = "";
          for (const subRule of value) {
              subRules += subRule + ";"
          }
          
          rules += key + "{" + subRules + " !important}"
      };

      if (style.styleSheet) {
        style.styleSheet.cssText = rules;
      } else {
        style.appendChild(document.createTextNode(rules));
      }

      head.appendChild(style);
      
      // Scripts
      var script = document.createElement("script");
      script.innerHTML = injected_script;
      head.appendChild(script);
  }
});
