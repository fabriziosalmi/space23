// SPACE23 — AudioContext autoplay unlock for web build.
//
// Browsers suspend every AudioContext at creation until a user gesture lands
// on the document. Godot 4.4's web export attaches a resume() handler to the
// canvas, but it can race with engine init or miss clicks that fall on
// Control nodes; on GitHub Pages this manifests as a silent game.
//
// Strategy:
//   1. Hook the AudioContext constructor so every instance the engine creates
//      gets registered.
//   2. On any user gesture, iterate the registered instances and resume() the
//      suspended ones. We listen in CAPTURE phase on both window AND document,
//      so we get the event before any canvas listener can stopPropagation.
//
// Loaded from <head>, so the constructor hook is in place before Godot's
// index.js runs.

(function () {
  'use strict';
  var W = window;
  var Native = W.AudioContext || W.webkitAudioContext;
  if (!Native) {
    console.warn('[audio-fix] AudioContext not available in this browser');
    return;
  }

  var instances = [];

  function Hook() {
    // Reflect.construct preserves `new.target` and the proper [[Construct]]
    // invocation; safer than `new Native(...arguments)` across edge cases.
    var ctx = Reflect.construct(Native, arguments, Hook);
    instances.push(ctx);
    console.log('[audio-fix] AudioContext registered (state=' + ctx.state + ', total=' + instances.length + ')');
    return ctx;
  }
  Hook.prototype = Native.prototype;

  W.AudioContext = Hook;
  if (W.webkitAudioContext) W.webkitAudioContext = Hook;

  function resumeAll(triggerEvent) {
    for (var i = 0; i < instances.length; i++) {
      var c = instances[i];
      if (c && c.state === 'suspended') {
        var idx = i;
        c.resume().then(function () {
          console.log('[audio-fix] resumed (event=' + (triggerEvent && triggerEvent.type) + ', idx=' + idx + ')');
        }).catch(function (err) {
          console.warn('[audio-fix] resume() failed:', err);
        });
      }
    }
  }

  // Capture phase + both window and document so we still catch the event even
  // if a canvas-level listener calls stopPropagation. `passive: true` keeps
  // the page responsive on touch.
  var EVENTS = ['click', 'mousedown', 'touchstart', 'touchend', 'keydown', 'pointerdown'];
  for (var i = 0; i < EVENTS.length; i++) {
    W.addEventListener(EVENTS[i], resumeAll, { capture: true, passive: true });
    document.addEventListener(EVENTS[i], resumeAll, { capture: true, passive: true });
  }

  console.log('[audio-fix] installed (Native=' + Native.name + ')');
})();
