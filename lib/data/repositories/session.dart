import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/network/api_client.dart';
import '../../core/storage/local_db.dart';
import '../../core/utils/app_log.dart';
import 'initial_data.dart';

class SessionUser {
  const SessionUser({required this.id, required this.email, required this.name, required this.orgId, this.roles = const []});

  final String id;
  final String email;
  final String name;
  final String orgId;
  final List<String> roles;

  factory SessionUser.fromLogin(Map<String, dynamic> j) => SessionUser(
        id: '${j['id']}',
        email: '${j['email']}',
        name: [j['firstName'], j['lastName']].where((e) => e != null && '$e'.isNotEmpty).join(' ').trim().isEmpty
            ? '${j['email']}'
            : [j['firstName'], j['lastName']].where((e) => e != null && '$e'.isNotEmpty).join(' '),
        orgId: '${j['organizationId']}',
        roles: ((j['roles'] as List?) ?? []).map((e) => '$e').toList(),
      );

  factory SessionUser.fromJson(Map<String, dynamic> j) => SessionUser(
        id: '${j['id']}',
        email: '${j['email']}',
        name: '${j['name']}',
        orgId: '${j['orgId']}',
        roles: ((j['roles'] as List?) ?? []).map((e) => '$e').toList(),
      );

  Map<String, dynamic> toJson() => {'id': id, 'email': email, 'name': name, 'orgId': orgId, 'roles': roles};
}

class SessionState {
  const SessionState({
    required this.baseUrl,
    required this.deviceId,
    this.accessToken,
    this.refreshToken,
    this.user,
    this.registerId,
    this.staffId,
    this.locked = true,
    this.lastActiveAt,
  });

  final String baseUrl;
  final String deviceId;
  final String? accessToken;
  final String? refreshToken;

  /// The ERP account the device is signed in with.
  final SessionUser? user;
  final String? registerId;

  /// Staff member currently operating the till (unlocked with their PIN).
  final String? staffId;
  final bool locked;

  /// Last time the unlocked till was used; drives the idle lock across reloads.
  final DateTime? lastActiveAt;

  bool get isLoggedIn => accessToken != null && user != null;

  SessionState copyWith({
    String? baseUrl,
    String? accessToken,
    String? refreshToken,
    SessionUser? user,
    String? registerId,
    String? staffId,
    bool clearStaff = false,
    bool? locked,
    DateTime? lastActiveAt,
  }) =>
      SessionState(
        baseUrl: baseUrl ?? this.baseUrl,
        deviceId: deviceId,
        accessToken: accessToken ?? this.accessToken,
        refreshToken: refreshToken ?? this.refreshToken,
        user: user ?? this.user,
        registerId: registerId ?? this.registerId,
        staffId: clearStaff ? null : (staffId ?? this.staffId),
        locked: locked ?? this.locked,
        lastActiveAt: lastActiveAt ?? this.lastActiveAt,
      );

  Map<String, dynamic> toJson() => {
        'baseUrl': baseUrl,
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'user': user?.toJson(),
        'registerId': registerId,
        'staffId': staffId,
        'locked': locked,
        'lastActiveAt': lastActiveAt?.toIso8601String(),
      };
}

class SessionController extends Notifier<SessionState> {
  @override
  SessionState build() {
    final init = ref.read(initialDataProvider);
    final j = init.session;
    if (j == null) return SessionState(baseUrl: AppConfig.defaultApiBaseUrl, deviceId: init.deviceId);
    final lastActive = DateTime.tryParse('${j['lastActiveAt'] ?? ''}');
    final autoLock = (init.settings?['autoLockSeconds'] as num?)?.toInt() ?? 0;
    final idleExpired = autoLock > 0 && (lastActive == null || DateTime.now().difference(lastActive).inSeconds >= autoLock);
    return SessionState(
      baseUrl: (j['baseUrl'] as String?) ?? AppConfig.defaultApiBaseUrl,
      deviceId: init.deviceId,
      accessToken: j['accessToken'] as String?,
      refreshToken: j['refreshToken'] as String?,
      user: j['user'] is Map ? SessionUser.fromJson(Map<String, dynamic>.from(j['user'] as Map)) : null,
      registerId: j['registerId'] as String?,
      staffId: j['staffId'] as String?,
      // A reload keeps the till as it was (unlocked after sign-in) unless it was locked or idle too long.
      locked: j['locked'] != false || j['staffId'] == null || idleExpired,
      lastActiveAt: lastActive,
    );
  }

  Future<void> _persist() => ref.read(localDbProvider).putKv('session', state.toJson());

  /// Signs the device in with an ERP account (`POST /api/iam/auth/login`).
  Future<void> login({required String baseUrl, required String email, required String password}) async {
    final url = AppConfig.normaliseBaseUrl(baseUrl);
    final client = ApiClient(
      baseUrl: url,
      tokens: () => (access: null, refresh: null),
      onRefreshed: (_) {},
      onUnauthorized: () {},
    );
    final res = Map<String, dynamic>.from(await client.post('/api/iam/auth/login', data: {'email': email.trim(), 'password': password}) as Map);
    final user = SessionUser.fromLogin(Map<String, dynamic>.from(res['user'] as Map));
    state = SessionState(
      baseUrl: url,
      deviceId: state.deviceId,
      accessToken: res['accessToken'] as String?,
      refreshToken: res['refreshToken'] as String?,
      user: user,
      registerId: state.user?.orgId == user.orgId ? state.registerId : null,
      staffId: user.id,
      locked: false,
      lastActiveAt: DateTime.now(),
    );
    AppLog.info('Signed in as ${user.email}');
    await _persist();
  }

  Future<void> setBaseUrl(String url) async {
    state = state.copyWith(baseUrl: AppConfig.normaliseBaseUrl(url));
    await _persist();
  }

  Future<void> updateAccessToken(String token) async {
    state = state.copyWith(accessToken: token);
    await _persist();
  }

  Future<void> selectRegister(String registerId) async {
    state = state.copyWith(registerId: registerId);
    await _persist();
  }

  Future<void> unlock(String staffId) async {
    state = state.copyWith(staffId: staffId, locked: false, lastActiveAt: DateTime.now());
    AppLog.info('Till unlocked by staff $staffId');
    await _persist();
  }

  /// Records till activity; written at most every 30 s.
  Future<void> touch() async {
    final last = state.lastActiveAt;
    if (state.locked || (last != null && DateTime.now().difference(last).inSeconds < 30)) return;
    state = state.copyWith(lastActiveAt: DateTime.now());
    await _persist();
  }

  Future<void> lock() async {
    state = state.copyWith(locked: true);
    await _persist();
  }

  Future<void> logout() async {
    state = SessionState(baseUrl: state.baseUrl, deviceId: state.deviceId);
    await _persist();
  }
}

final sessionProvider = NotifierProvider<SessionController, SessionState>(SessionController.new);

/// API client bound to the current server; tokens are read lazily per request.
final apiClientProvider = Provider<ApiClient>((ref) {
  final baseUrl = ref.watch(sessionProvider.select((s) => s.baseUrl));
  return ApiClient(
    baseUrl: baseUrl,
    tokens: () {
      final s = ref.read(sessionProvider);
      return (access: s.accessToken, refresh: s.refreshToken);
    },
    onRefreshed: (token) => ref.read(sessionProvider.notifier).updateAccessToken(token),
    onUnauthorized: () => AppLog.warn('API returned 401 after refresh; sign in again from Settings'),
  );
});
