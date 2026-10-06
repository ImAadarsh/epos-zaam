import 'dart:js_interop';
import 'dart:js_interop_unsafe';

const socketCaptureAvailable = true;

JSObject? get _bridge => globalContext.has('zaamSocketCapture') ? globalContext['zaamSocketCapture'] as JSObject : null;

/// Starts CaptureJS (see `web/socket_capture_bridge.js`).
void socketCaptureStart({
  required String appId,
  required String developerId,
  required String appKey,
  required void Function(String code, String symbology) onScan,
  required void Function(String state, String detail) onStatus,
}) {
  final bridge = _bridge;
  if (bridge == null) return onStatus('error', 'Scanner bridge not loaded; reload the page');
  bridge.callMethodVarArgs('start'.toJS, [
    appId.toJS,
    developerId.toJS,
    appKey.toJS,
    ((JSString code, JSString symbology) => onScan(code.toDart, symbology.toDart)).toJS,
    ((JSString state, JSString detail) => onStatus(state.toDart, detail.toDart)).toJS,
  ]);
}

void socketCaptureStop() => _bridge?.callMethod('stop'.toJS);
