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
    ('How does the cash drawer open?',
        'Connect the drawer to the printer DK (RJ11) port. In Settings → Cash drawer turn on “Open drawer on cash sales”, then use Test open drawer. Cash sales, Direct Sale, Pay in/out, Cash drop and No sale send the kick when that setting is on.'),
    ('How do I take card payments?',
        'With any standalone terminal: charge the amount on the terminal and tap Approved. With SumUp Solo: add your SumUp API key, merchant code and reader ID in Settings → Payment and the amount is sent to the reader automatically.'),
    ('Where do products and prices come from?',
        'From Zaam ERP (catalogue, variants, barcodes, price lists and promotions). Quantity volume breaks on the price list (e.g. cheaper from 5 units) apply automatically on the till and in B2B. The till downloads changes every few minutes and stock levels every minute.'),
    ('What does the customer display show?',
        'A YouTube marketing video — not sale prices. Set the link in Settings → Customer display, then Options → Connect Display and drag the window onto the customer monitor.'),
    ('How do I reprint the last receipt?',
        'On the Sell screen tap Receipt, or open Direct Sale (D-Sale) and tap Print. Both print a copy of the most recent sale on this till.'),
    ('What is Direct Sale (D-Sale)?',
        'Direct Sale is a full-screen till for products without barcodes: enter the amount in pence (e.g. 2 then 00 for £2.00), then Sale, Print, Payout, or Hourly (early sales report). Use the header back control to return to Sell. It sits alongside Sell and does not replace product scanning.'),
    ('How do I add a new product on the till?',
        "Options → Manager tools / Add Prod. for the catalogue product, then Add Vt's. for the sellable variant (SKU, options, barcode, cost, sell price, stock). Manager PIN required. Day-to-day cashiers use Sell shortcuts (Receipt, Saved, Refund, Lock) instead."),
    ('Why are categories empty on Add Prod.?',
        'Ask an admin in ERP → Catalog → Classifications (Manage Classifications) to add values or tap Import from products, then reopen Add Prod. and tap Refresh. Until then the till may show categories already used on products downloaded to this device.'),
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
