'use strict';

// This file replaces out/main/index.js, ahead of the vendor's compiled entry.
// Keep manual launches unchanged; only Windows logon launches stay hidden.
if (process.argv.includes('--startupWithMinimize')) {
  const { app, BrowserWindow, Tray } = require('electron');
  let waitingForUser = true;
  const release = () => { waitingForUser = false; };

  for (const method of ['show', 'showInactive', 'minimize']) {
    const original = BrowserWindow.prototype[method];
    BrowserWindow.prototype[method] = function (...args) {
      if (waitingForUser) {
        this.hide();
        return;
      }
      return original.apply(this, args);
    };
  }

  app.on('browser-window-created', (_event, window) => {
    if (waitingForUser) window.hide();
    // Sensor/device updates in the renderer must keep running while hidden.
    window.webContents.setBackgroundThrottling(false);
  });

  // Release before the vendor's tray callbacks call window.show().
  const emit = Tray.prototype.emit;
  Tray.prototype.emit = function (event, ...args) {
    if (['click', 'double-click', 'right-click'].includes(event)) release();
    return emit.call(this, event, ...args);
  };
  app.prependListener('second-instance', (_event, argv) => {
    if (!argv.includes('--startupWithMinimize')) release();
  });
}

require('./bytecode-loader.js');
require('./index.jsc');
