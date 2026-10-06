/// CaptureJS is web-only; native builds use Socket Mobile scanners in Basic (HID) mode.
const socketCaptureAvailable = false;

void socketCaptureStart({
  required String appId,
  required String developerId,
  required String appKey,
  required void Function(String code, String symbology) onScan,
  required void Function(String state, String detail) onStatus,
}) =>
    onStatus('error', 'Application mode is only available in the web app. Use Basic (HID) mode.');

void socketCaptureStop() {}
