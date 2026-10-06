import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Stops every camera stream opened on this page (see `web/index.html`).
void releaseAllCameras() {
  if (globalContext.has('zaamStopCameras')) globalContext.callMethod('zaamStopCameras'.toJS);
}
