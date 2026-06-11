import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/database_helper.dart';
import '../theme.dart';
import '../utils/format.dart';

enum Period { week, month, year, custom }

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  Period _period = Period.month;
  DateTime? _customStart;
  DateTime? _customEnd;
  String _breakdownType = 'expense';
  List<Map<String, Object?>> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// The [start, end) date range for the selected period.
  (DateTime, DateTime) _range() {
    final now = DateTime.now();
    switch (_period) {
      case Period.week:
        final start = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: now.weekday - 1));
        return (start, start.add(const Duration(days: 7)));
      case Period.month:
        return (DateTime(now.year, now.month, 1),
            DateTime(now.year, now.month + 1, 1));
      case Period.year:
        return (DateTime(now.year, 1, 1), DateTime(now.year + 1, 1, 1));
      case Period.custom:
        final s = _customStart ?? DateTime(now.year, now.month, 1);
        final e = _customEnd ?? now;
        return (
          DateTime(s.year, s.month, s.day),
          DateTime(e.year, e.month, e.day).add(const Duration(days: 1)),
        );
    }
  }

  Future<void> _load() async {
    final (start, end) = _range();
    final rows = await DatabaseHelper.instance
        .getTransactionsWithCategoryBetween(start, end);
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  double _sumWhere(String type) => _rows
      .where((r) => r['type'] == type)
      .fold(0.0, (sum, r) => sum + (r['amount'] as num).toDouble());

  // ---- Period selection ----

  Future<void> _onPeriodChanged(Period p) async {
    if (p == Period.custom) {
      final now = DateTime.now();
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
        initialDateRange: _customStart != null && _customEnd != null
            ? DateTimeRange(start: _customStart!, end: _customEnd!)
            : DateTimeRange(start: DateTime(now.year, now.month, 1), end: now),
      );
      if (picked == null) return; // keep previous period if cancelled
      setState(() {
        _customStart = picked.start;
        _customEnd = picked.end;
        _period = Period.custom;
      });
    } else {
      setState(() => _period = p);
    }
    _load();
  }

  String _rangeLabel() {
    final (start, end) = _range();
    final last = end.subtract(const Duration(days: 1));
    final f = DateFormat('d MMM yyyy');
    return '${f.format(start)} – ${f.format(last)}';
  }

  // ---- Category breakdown (pie) ----

  List<_Slice> _breakdown() {
    final map = <String, _Slice>{};
    for (final r in _rows.where((r) => r['type'] == _breakdownType)) {
      final name = r['category_name'] as String;
      final icon = (r['category_icon'] as String?) ?? '';
      final amt = (r['amount'] as num).toDouble();
      map.update(name, (s) => s..amount += amt,
          ifAbsent: () => _Slice(name, icon, amt));
    }
    final list = map.values.toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));
    return list;
  }

  // ---- Trend (bar chart) ----
  //
  // Bucketing rules:
  //   Week   -> 7 daily bars (Mon..Sun)
  //   Month  -> weekly bars, labeled by the week's first day (1, 8, 15, ...)
  //   Year   -> 12 monthly bars (Jan..Dec)
  //   Custom -> adaptive: <=14d daily, <=92d weekly, else monthly
  List<_Bucket> _trend() {
    final (start, end) = _range();
    final expenses = _rows.where((r) => r['type'] == 'expense').toList();

    double sumBetween(DateTime a, DateTime b) => expenses.where((r) {
          final d = DateTime.fromMillisecondsSinceEpoch(r['date'] as int);
          return !d.isBefore(a) && d.isBefore(b);
        }).fold(0.0, (s, r) => s + (r['amount'] as num).toDouble());

    List<_Bucket> daily(DateFormat fmt) {
      final out = <_Bucket>[];
      var d = DateTime(start.year, start.month, start.day);
      while (d.isBefore(end)) {
        final next = d.add(const Duration(days: 1));
        out.add(_Bucket(fmt.format(d), sumBetween(d, next)));
        d = next;
      }
      return out;
    }

    List<_Bucket> weekly(DateFormat fmt) {
      final out = <_Bucket>[];
      var s = DateTime(start.year, start.month, start.day);
      while (s.isBefore(end)) {
        var e = s.add(const Duration(days: 7));
        if (e.isAfter(end)) e = end;
        out.add(_Bucket(fmt.format(s), sumBetween(s, e)));
        s = s.add(const Duration(days: 7));
      }
      return out;
    }

    List<_Bucket> monthly(DateFormat fmt) {
      final out = <_Bucket>[];
      var m = DateTime(start.year, start.month, 1);
      while (m.isBefore(end)) {
        final next = DateTime(m.year, m.month + 1, 1);
        out.add(_Bucket(fmt.format(m), sumBetween(m, next)));
        m = next;
      }
      return out;
    }

    switch (_period) {
      case Period.week:
        return daily(DateFormat('EEE')); // Mon, Tue, ...
      case Period.month:
        return weekly(DateFormat('d/M')); // 1/6, 8/6, 15/6, 22/6, 29/6
      case Period.year:
        return monthly(DateFormat('MMM')); // Jan..Dec
      case Period.custom:
        final spanDays = end.difference(start).inDays;
        if (spanDays <= 14) return daily(DateFormat('d/M'));
        if (spanDays <= 92) return weekly(DateFormat('d/M'));
        return monthly(DateFormat('MMM yy'));
    }
  }

  String _axisLabel(double v) {
    if (v >= 1000) {
      final k = v / 1000;
      return 'RM${k == k.roundToDouble() ? k.toInt() : k.toStringAsFixed(1)}k';
    }
    return 'RM${v.toInt()}';
  }

  // ---- UI ----

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _periodSelector(),
                  const SizedBox(height: 4),
                  Center(
                    child: Text(_rangeLabel(),
                        style: TextStyle(color: Colors.grey.shade600)),
                  ),
                  const SizedBox(height: 12),
                  _summaryCard(),
                  const SizedBox(height: 16),
                  _sectionTitle('Spending by Category'),
                  _breakdownTypeToggle(),
                  const SizedBox(height: 8),
                  _pieSection(),
                  const SizedBox(height: 24),
                  _sectionTitle('Spending Trend'),
                  const SizedBox(height: 8),
                  _trendSection(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(text,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      );

  Widget _periodSelector() {
    return SegmentedButton<Period>(
      style: SegmentedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 6),
      ),
      segments: const [
        ButtonSegment(value: Period.week, label: Text('Week')),
        ButtonSegment(value: Period.month, label: Text('Month')),
        ButtonSegment(value: Period.year, label: Text('Year')),
        ButtonSegment(value: Period.custom, label: Text('Custom')),
      ],
      selected: {_period},
      showSelectedIcon: false,
      onSelectionChanged: (s) => _onPeriodChanged(s.first),
    );
  }

  Widget _summaryCard() {
    final income = _sumWhere('income');
    final expense = _sumWhere('expense');
    final balance = income - expense;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _stat('Income', income, incomeColor),
            _stat('Expense', expense, expenseColor),
            _stat('Balance', balance,
                balance >= 0 ? incomeColor : expenseColor),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, double value, Color color) => Column(
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 2),
          Text(formatRM(value),
              style: TextStyle(fontWeight: FontWeight.bold, color: color)),
        ],
      );

  Widget _breakdownTypeToggle() {
    return Align(
      alignment: Alignment.centerLeft,
      child: SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'expense', label: Text('Expense')),
          ButtonSegment(value: 'income', label: Text('Income')),
        ],
        selected: {_breakdownType},
        showSelectedIcon: false,
        onSelectionChanged: (s) => setState(() => _breakdownType = s.first),
      ),
    );
  }

  Widget _pieSection() {
    final slices = _breakdown();
    if (slices.isEmpty) {
      return _emptyBox('No $_breakdownType data for this period');
    }
    final total = slices.fold(0.0, (s, x) => s + x.amount);
    return Column(
      children: [
        SizedBox(
          height: 200,
          child: PieChart(
            PieChartData(
              centerSpaceRadius: 48,
              sectionsSpace: 2,
              sections: [
                for (var i = 0; i < slices.length; i++)
                  PieChartSectionData(
                    value: slices[i].amount,
                    color: chartColor(i),
                    radius: 56,
                    title: '${(slices[i].amount / total * 100).round()}%',
                    titleStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < slices.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Container(width: 12, height: 12, color: chartColor(i)),
                const SizedBox(width: 8),
                Expanded(child: Text('${slices[i].icon} ${slices[i].name}')),
                Text(
                  '${formatRM(slices[i].amount)}  (${(slices[i].amount / total * 100).round()}%)',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _trendSection() {
    final buckets = _trend();
    final maxV = buckets.fold(0.0, (m, b) => b.total > m ? b.total : m);
    if (maxV == 0) {
      return _emptyBox('No expense data for this period');
    }
    final maxY = maxV * 1.2;
    final interval = maxY / 4;

    return LayoutBuilder(
      builder: (context, constraints) {
        const slot = 46.0;
        final needed = buckets.length * slot;
        final scrolls = needed > constraints.maxWidth;
        final width = scrolls ? needed : constraints.maxWidth;

        final chart = SizedBox(
          width: width,
          height: 240,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: maxY,
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => Colors.blueGrey.shade800,
                  getTooltipItem: (group, _, rod, _) => BarTooltipItem(
                    '${buckets[group.x].label}\n${formatRM(rod.toY)}',
                    const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 12),
                  ),
                ),
              ),
              gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: interval),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 52,
                    interval: interval,
                    getTitlesWidget: (value, meta) {
                      if (value > meta.max - interval * 0.1) {
                        return const SizedBox.shrink();
                      }
                      return Text(_axisLabel(value),
                          style: const TextStyle(fontSize: 9));
                    },
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 26,
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (i < 0 || i >= buckets.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(buckets[i].label,
                            style: const TextStyle(fontSize: 9)),
                      );
                    },
                  ),
                ),
              ),
              barGroups: [
                for (var i = 0; i < buckets.length; i++)
                  BarChartGroupData(x: i, barRods: [
                    BarChartRodData(
                      toY: buckets[i].total,
                      color: expenseColor,
                      width: 12,
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(3)),
                    ),
                  ]),
              ],
            ),
          ),
        );

        return scrolls
            ? SingleChildScrollView(
                scrollDirection: Axis.horizontal, child: chart)
            : chart;
      },
    );
  }

  Widget _emptyBox(String text) => Container(
        height: 120,
        alignment: Alignment.center,
        child: Text(text, style: TextStyle(color: Colors.grey.shade600)),
      );
}

class _Slice {
  final String name;
  final String icon;
  double amount;
  _Slice(this.name, this.icon, this.amount);
}

class _Bucket {
  final String label;
  final double total;
  _Bucket(this.label, this.total);
}
