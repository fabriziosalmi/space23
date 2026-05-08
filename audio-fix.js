// SPACE23 — AudioContext autoplay unlock for web build.
//
// Chrome and Firefox suspend every AudioContext at creation until the user
// performs a gesture on the document. Godot 4.4 attaches a resume() handler
// to the canvas, but it can race with engine init or miss clicks that land
// on Control nodes; on GitHub Pages this manifests as a silent game.
//
// Strategy:
//   1. Hook the AudioContext constructor so every instance the engine creates
//      gets registered.
//   2. On any user gesture at window level (click, touch, key, pointer),
//      iterate the registered instances and resume() the suspended ones.
//
// This runs before Godot loads (it's in <head>), so the constructor hook is
// in place by the time Godot creates its audio context.

(function () {
  var Native = window.AudioContext || window.webkitAudioContext;
  if (!Native) return;

  var instances = [];

  function Wrap() {
    var ctx = new Native(...arguments);
    instances.push(ctx);
    return ctx;
  }
  Wrap.prototype = Native.prototype;
  // Preserve `instanceof` checks (Godot may use them).
  Object.setPrototypeOf(Wrap, Native);

  window.AudioContext = Wrap;
  if (window.webkitAudioContext) window.webkitAudioContext = Wrap;

  function resumeAll() {
    for (var i = 0; i < instances.length; i++) {
      var c = instances[i];
      if (c && c.state === 'suspended') {
        c.resume().catch(function () { /* ignore */ });
      }
    }
  }

  var events = ['click', 'touchstart', 'keydown', 'pointerdown'];
  events.forEach(function (ev) {
    window.addEventListener(ev, resumeAll, { passive: true });
  });
})();
