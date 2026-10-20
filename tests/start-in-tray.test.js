'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { EventEmitter } = require('node:events');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync(require.resolve('../compat/start-in-tray.js'), 'utf8');

function boot(startup = true) {
  const app = new EventEmitter();
  class BrowserWindow {
    constructor() {
      this.visible = true;
      this.minimized = false;
      this.webContents = { setBackgroundThrottling: value => { this.throttling = value; } };
      app.emit('browser-window-created', {}, this);
    }
    hide() { this.visible = false; }
    show() { this.visible = true; }
    showInactive() { this.visible = true; }
    minimize() { this.visible = true; this.minimized = true; }
  }
  class Tray extends EventEmitter {}
  const loaded = [];
  vm.runInNewContext(source, {
    process: { argv: startup ? ['CpuTemp.exe', '--startupWithMinimize'] : ['CpuTemp.exe'] },
    require: name => {
      if (name === 'electron') return { app, BrowserWindow, Tray };
      loaded.push(name);
    }
  });
  return { app, BrowserWindow, Tray, loaded };
}

test('logon stays hidden despite delayed vendor show/minimize calls; monitoring entry still loads', () => {
  const { BrowserWindow, loaded } = boot();
  const window = new BrowserWindow();
  assert.equal(window.visible, false);
  window.show(); window.showInactive(); window.minimize();
  assert.equal(window.visible, false);
  assert.equal(window.minimized, false);
  assert.equal(window.throttling, false);
  assert.deepEqual(loaded, ['./bytecode-loader.js', './index.jsc']);
});
for (const event of ['click', 'double-click', 'right-click']) {
  test(`tray ${event} allows vendor callback to reopen the UI`, () => {
    const { BrowserWindow, Tray } = boot();
    const window = new BrowserWindow();
    const tray = new Tray();
    tray.on(event, () => window.show());
    tray.emit(event);
    assert.equal(window.visible, true);
    window.hide(); window.show();
    assert.equal(window.visible, true);
  });
}
test('another logon invocation stays hidden; explicit manual relaunch opens', () => {
  const { app, BrowserWindow } = boot();
  const window = new BrowserWindow();
  app.on('second-instance', () => window.show());
  app.emit('second-instance', {}, ['CpuTemp.exe', '--startupWithMinimize']);
  assert.equal(window.visible, false);
  app.emit('second-instance', {}, ['CpuTemp.exe']);
  assert.equal(window.visible, true);
});
test('manual launch retains vendor visibility behavior', () => {
  const { BrowserWindow, loaded } = boot(false);
  const window = new BrowserWindow();
  window.hide(); window.show();
  assert.equal(window.visible, true);
  window.minimize();
  assert.equal(window.minimized, true);
  assert.deepEqual(loaded, ['./bytecode-loader.js', './index.jsc']);
});
