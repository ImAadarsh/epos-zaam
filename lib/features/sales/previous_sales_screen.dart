import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/network/api_exception.dart';
import '../../core/scanner/camera_scanner.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../core/utils/responsive.dart';
import '../../data/models/sale.dart';
import '../../data/repositories/sales_repository.dart';
import '../../data/repositories/session.dart';
import '../shell/status_bar.dart';
import 'refund_screen.dart';
import 'sale_detail_screen.dart';

enum _Scope { thisRegister, all }

/// Previous Sales: server history merged with this device's not-yet-synced sales.
class PreviousSalesScreen extends ConsumerStatefulWidget {
  const PreviousSalesScreen({super.key, this.embedded = false});

  /// True when shown as a tab (no back button).
  final bool embedded;

  @override
  ConsumerState<PreviousSalesScreen> createState() => _PreviousSalesScreenState();
}

class _PreviousSalesScreenState extends ConsumerState<PreviousSalesScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  _Scope _scope = _Scope.thisRegister;
  DateTime? _day;
  List<SaleSummary> _remote = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final session = ref.read(sessionProvider);
      final day = _day;
      final res = Map<String, dynamic>.from(await ref.read(apiClientProvider).get('/api/pos/sales', query: {
        'search': _search.text.trim().isEmpty ? null : _search.text.trim(),
        'registerId': _scope == _Scope.thisRegister ? session.registerId : null,
        'from': day == null ? null : DateTime(day.year, day.month, day.day).toUtc().toIso8601String(),
        'to': day == null ? null : DateTime(day.year, day.month, day.day, 23, 59, 59).toUtc().toIso8601String(),
        'limit': 100,
      }) as Map);
      if (!mounted) return;
      setState(() => _remote = ((res['items'] as List?) ?? []).map((e) => SaleSummary.fromServer(Map<String, dynamic>.from(e as Map))).toList());
    } catch (e) {
      if (mounted) setState(() => _error = (e is ApiException && e.isNetwork) ? 'Offline: showing sales made on this device.' : errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<SaleSummary> _merged(List<SaleRecord> local) {
    final q = _search.text.trim().toLowerCase();
    final session = ref.read(sessionProvider);
    final remoteNumbers = _remote.map((r) => r.receiptNumber).toSet();
    final extra = local
        .where((s) => !remoteNumbers.contains(s.receiptNumber))
        .where((s) => _error != null || s.sync != SyncState.synced)
        .where((s) => _scope == _Scope.all || s.registerId == session.registerId)
        .where((s) => _day == null || DateUtils.isSameDay(s.soldAt, _day))
        .where((s) => q.isEmpty || s.receiptNumber.toLowerCase().contains(q) || formatPence(s.totalPence).contains(q))
        .map(SaleSummary.fromLocal);
    return [...extra, ..._remote]..sort((a, b) => b.soldAt.compareTo(a.soldAt));
  }

  void _open(SaleSummary s) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SaleDetailScreen(code: s.code)));

  @override
  Widget build(BuildContext context) {
    final local = ref.watch(localSalesProvider);
    final rows = _merged(local);
    final theme = Theme.of(context);
    final time = DateFormat('dd MMM HH:mm');
    final wide = !context.isCompact;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        title: const Text('Previous Sales'),
        actions: [
          IconButton(
            tooltip: 'Refund transaction',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RefundScreen())),
            icon: const Icon(Icons.undo),
          ),
          IconButton(tooltip: 'Refresh', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
          if (widget.embedded) const ShellStatusActions(),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  decoration: InputDecoration(
                    hintText: 'Search receipt #, amount or email',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: cameraScanSupported
                        ? IconButton(
                            icon: const Icon(Icons.qr_code_scanner),
                            onPressed: () async {
                              final c = await scanWithCamera(context, title: 'Scan receipt');
                              if (c != null) {
                                _search.text = c;
                                _load();
                              }
                            },
                          )
                        : null,
                  ),
                  onChanged: (_) {
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 400), _load);
                  },
                  onSubmitted: (_) => _load(),
                ),
              ),
            ]),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(children: [
              SegmentedButton<_Scope>(
                segments: const [ButtonSegment(value: _Scope.thisRegister, label: Text('This register')), ButtonSegment(value: _Scope.all, label: Text('All registers'))],
                selected: {_scope},
                onSelectionChanged: (s) {
                  setState(() => _scope = s.first);
                  _load();
                },
              ),
              const SizedBox(width: 8),
              InputChip(
                avatar: const Icon(Icons.calendar_today, size: 18),
                label: Text(_day == null ? 'Any date' : DateFormat('EEE d MMM').format(_day!)),
                onPressed: () async {
                  final d = await showDatePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime.now(), initialDate: _day ?? DateTime.now());
                  if (d != null) {
                    setState(() => _day = d);
                    _load();
                  }
                },
                onDeleted: _day == null
                    ? null
                    : () {
                        setState(() => _day = null);
                        _load();
                      },
              ),
            ]),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null) Padding(padding: const EdgeInsets.all(8), child: Text(_error!, style: TextStyle(color: theme.colorScheme.error))),
          if (wide)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
              child: DefaultTextStyle(
                style: theme.textTheme.labelLarge!.copyWith(color: theme.colorScheme.onSurfaceVariant),
                child: const Row(children: [
                  Expanded(flex: 3, child: Text('#')),
                  Expanded(flex: 2, child: Text('Time')),
                  Expanded(flex: 2, child: Text('Amount', textAlign: TextAlign.end)),
                  SizedBox(width: 24),
                  Expanded(flex: 2, child: Text('Register')),
                  Expanded(flex: 2, child: Text('Staff')),
                  SizedBox(width: 110, child: Text('Status')),
                ]),
              ),
            ),
          const Divider(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: rows.isEmpty
                  ? ListView(children: const [Padding(padding: EdgeInsets.all(48), child: Center(child: Text('No sales found')))])
                  : ListView.separated(
                      itemCount: rows.length,
                      separatorBuilder: (_, _) => const Divider(),
                      itemBuilder: (_, i) {
                        final s = rows[i];
                        final status = _StatusChip(summary: s);
                        if (!wide) {
                          return ListTile(
                            onTap: () => _open(s),
                            title: Text(s.receiptNumber, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text([time.format(s.soldAt), if (s.staffName != null) s.staffName!, if (s.registerName != null) s.registerName!].join(' · ')),
                            trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                              Text(formatPence(s.totalPence), style: theme.textTheme.titleMedium),
                              status,
                            ]),
                          );
                        }
                        return InkWell(
                          onTap: () => _open(s),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                            child: Row(children: [
                              Expanded(flex: 3, child: Text(s.receiptNumber, style: const TextStyle(fontWeight: FontWeight.w600))),
                              Expanded(flex: 2, child: Text(time.format(s.soldAt))),
                              Expanded(flex: 2, child: Text(formatPence(s.totalPence), textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w600))),
                              const SizedBox(width: 24),
                              Expanded(flex: 2, child: Text(s.registerName ?? '-')),
                              Expanded(flex: 2, child: Text(s.staffName ?? '-')),
                              SizedBox(width: 110, child: Align(alignment: Alignment.centerLeft, child: status)),
                            ]),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.summary});
  final SaleSummary summary;

  @override
  Widget build(BuildContext context) {
    final (label, color) = summary.sync != SyncState.synced
        ? ('Not synced', ZaamColors.amber)
        : switch (summary.status) {
            'voided' => ('Voided', ZaamColors.red),
            'refunded' => ('Refunded', ZaamColors.red),
            'partially_refunded' => ('Part refund', ZaamColors.amber),
            _ => ('Completed', ZaamColors.green),
          };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}
