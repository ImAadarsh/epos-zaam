// Socket Mobile scanners in Application mode via CaptureJS.
// Needs Socket Mobile Companion running on this computer/tablet (Windows, Android),
// or the Rumba browser on iOS. Basic (HID keyboard) mode needs none of this.
(function () {
  var CAPTURE_JS = 'https://socketimagescdn.azureedge.net/cdn/scripts/captureJs-2.0.2.228.min.js';
  var capture = null;
  var devices = {};
  var loading = null;
  var generation = 0;

  function loadScript() {
    if (window.SocketMobile) return Promise.resolve();
    if (loading) return loading;
    loading = new Promise(function (resolve, reject) {
      var s = document.createElement('script');
      s.src = CAPTURE_JS;
      s.async = true;
      s.onload = function () { resolve(); };
      s.onerror = function () { loading = null; reject(new Error('Could not download CaptureJS (offline?)')); };
      document.head.appendChild(s);
    });
    return loading;
  }

  function decode(data) {
    if (!data) return '';
    if (typeof data === 'string') return data;
    var out = '';
    for (var i = 0; i < data.length; i++) out += String.fromCharCode(data[i]);
    return out;
  }

  function stop() {
    generation++;
    var old = capture;
    capture = null;
    Object.keys(devices).forEach(function (k) {
      try { devices[k].close(); } catch (e) {}
    });
    devices = {};
    if (old) {
      try { old.close(); } catch (e) {}
    }
  }

  // onScan(code, symbology); onStatus(state, detail) with state in
  // loading | waiting | connected | disconnected | no-service | error.
  function start(appId, developerId, appKey, onScan, rawStatus) {
    var onStatus = function (state, detail) {
      console.info('[Zaam scanner] Socket Mobile', state, detail || '');
      rawStatus(state, detail);
    };
    stop();
    var gen = generation;
    var live = function () { return gen === generation; };
    onStatus('loading', '');
    loadScript().then(function () {
      if (!live()) return;
      var SM = window.SocketMobile;
      var ids = SM.CaptureEventIds;
      var root = new SM.Capture();
      capture = root;
      var notify = function (event) {
        if (!live() || !event) return;
        if (event.id === ids.DeviceArrival) {
          var dev = new SM.Capture();
          var guid = event.value.guid;
          var name = event.value.name || 'Socket Mobile scanner';
          dev.openDevice(guid, root).then(function () {
            if (!live()) { try { dev.close(); } catch (e) {} return; }
            devices[guid] = dev;
            onStatus('connected', name);
          }).catch(function (err) { onStatus('error', 'Could not open ' + name + ' (' + err + ')'); });
        } else if (event.id === ids.DeviceRemoval) {
          var g = event.value && event.value.guid;
          if (g && devices[g]) {
            try { devices[g].close(); } catch (e) {}
            delete devices[g];
          }
          onStatus(Object.keys(devices).length ? 'connected' : 'disconnected', (event.value && event.value.name) || '');
        } else if (event.id === ids.DecodedData) {
          if (event.result !== undefined && event.result < 0) return;
          var code = decode(event.value && event.value.data).trim();
          if (code) onScan(code, (event.value && event.value.name) || '');
        }
      };
      return root.open({ appId: appId, developerId: developerId, appKey: appKey }, notify).then(function () {
        if (live() && !Object.keys(devices).length) onStatus('waiting', '');
      }).catch(function (err) {
        if (!live()) return;
        capture = null;
        if (err === SM.SktErrors.ESKT_UNABLEOPENDEVICE) {
          onStatus('no-service', 'Socket Mobile Companion is not running on this device');
        } else {
          onStatus('error', 'CaptureJS error ' + err + ' (check App ID, Developer ID and AppKey)');
        }
      });
    }).catch(function (err) {
      if (live()) onStatus('error', String((err && err.message) || err));
    });
  }

  window.zaamSocketCapture = { start: start, stop: stop };
})();
