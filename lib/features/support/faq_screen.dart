import 'package:flutter/material.dart';

class FaqScreen extends StatelessWidget {
  const FaqScreen({super.key});

  static const _faqs = [
    ('Can I keep selling if the internet goes down?',
        'Yes. Sales, refunds, cash movements and register close are saved on this device and sent to Zaam ERP automatically when the connection returns. The status pill at the top shows how many changes are waiting.'),
    ('What does "Check Unsynced Sales" do?',
        'It lists everything waiting to sync. "Sync now" retries immediately; "Fix Sales" resets items that failed (for example because a product was deleted in the ERP) so they are tried again. Use Send Debug Data if something keeps failing.'),
    ('How do I use a barcode scanner?',
        'Plug in any USB or Bluetooth scanner set to keyboard mode with an Enter suffix, then scan on the Sell screen. On phones and tablets you can also tap the camera icon.'),
    ('How do refunds work?',
        'Options → Refund Transaction, then scan the barcode on the receipt or type the receipt number. Pick the items, choose Cash, Card or Voucher and whether to put the stock back. Card refunds must also be done on the card terminal.'),
    ('What is the difference between an X-read and a Z-read?',
        'An X-read shows takings so far without closing anything. A Z-read happens when you close the register: you count the cash, the variance is recorded and the session ends.'),
    ('Why does it ask for a manager PIN?',
        'Refunds, voids, large discounts, cash in/out, closing the register and settings need a supervisor or manager. Roles and PINs are set in Settings → Staff PINs.'),
    ('How do I connect a receipt printer?',
        'Settings → Printer. Network ESC/POS printers (Epson TM, Star, Xprinter…) need the printer IP address; the cash drawer plugs into the printer. "System print dialog" works with AirPrint and desktop printers, and on the web.'),
    ('How do I take card payments?',
        'With any standalone terminal: charge the amount on the terminal and tap Approved. With SumUp Solo: add your SumUp API key, merchant code and reader ID in Settings → Payment and the amount is sent to the reader automatically.'),
    ('Where do products and prices come from?',
        'From Zaam ERP (catalogue, variants, barcodes, price lists and promotions). The till downloads changes every few minutes and stock levels every minute.'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('FAQ')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              for (final (q, a) in _faqs)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ExpansionTile(
                    title: Text(q, style: const TextStyle(fontWeight: FontWeight.w600)),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    expandedAlignment: Alignment.centerLeft,
                    children: [Text(a)],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
