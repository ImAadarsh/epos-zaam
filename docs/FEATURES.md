# Zaam EPOS – feature research & status

## Research summary

| App | Takeaways adopted |
| --- | --- |
| Goodtill / SumUp POS | Options menu layout (close register, X/Z reads, clock in/out, saved & previous sales, refund by receipt barcode, manage availability, unsynced sales, change register, customer display, debug data, reset). Payment types with per-type "show prompt". SumUp Solo / Bluetooth readers. |
| Square POS | Fast grid + cart, split tender, quick-cash buttons, tips, digital receipts, offline card-less mode with later sync. |
| Lightspeed Retail | Variant/matrix products, barcode-first selling, stock visibility at the till, customer lookup on sale. |
| Shopify POS | Responsive phone/tablet layouts, cart on a sheet on phones, parked carts, staff PINs with role permissions and manager override. |
| Epos Now | UK focus: VAT-inclusive pricing, cash-up by UK denominations, float/pay in/pay out/drop, Z-read end of day, ESC/POS printers with cash drawer kick. |

Common patterns applied: offline-first with an idempotent outbox, PIN lock between staff, keyboard-wedge scanner support, receipt reprint/email, refunds against the original sale with restock, and a second-screen customer display.

## Feature status

Legend: ✅ done · 🟡 partial · ⛔ stub (clear error / manual fallback)

### Sale flow
- ✅ Product grid with categories, search, barcode/SKU lookup (HID scanner + camera on web/iOS/Android/macOS)
- ✅ Variants, modifiers, allergen confirmation, unavailable / out-of-stock prompts
- ✅ Cart: quantity, line discount, price override, notes, cart discount (proportional), customer, sale type, table
- ✅ Payments: cash (quick-cash, change), card, voucher/other, split tender, tips, "show prompt" per type
- ✅ Receipts: USB ESC/POS via WebUSB (Chrome PWA), network ESC/POS (TCP 9100, native), drawer kick, CODE128/QR, PDF via system print dialog, email
- ✅ Park / resume sales (Saved Sales) with table timers
- ✅ Offline: sales, refunds, shifts, clock entries queued and replayed in order; local receipt numbers

### Options menu (Goodtill parity)
- ✅ Close Register: start close, UK denomination count, X-read, Z-read, float after close, printable report
- ✅ Pay in / pay out / cash drop / no sale
- ✅ Staff Clock In/Out with search
- ✅ Settings: payment types, SumUp Solo, other providers, general toggles, printers, staff PINs & roles
- ✅ Saved Sales, Previous Sales (server + unsynced), sale detail, reprint, void
- ✅ Refund Transaction (scan receipt barcode or type number, partial quantities, restock)
- ✅ Manage Availability (Products / Modifiers tabs, Show All)
- ✅ Check Unsynced Sales (Sync now, Fix Sales, discard)
- ✅ Change Register ("Register Active")
- 🟡 Connect Display: web opens a second window (BroadcastChannel); native has no network pairing yet
- ✅ Send Debug Data, FAQ, Reset App

### Hardware / integrations
- ✅ SumUp Solo via SumUp Cloud API (needs API key, merchant code, reader id; browsers may hit CORS)
- ⛔ SumUp Bluetooth readers (native SDK not integrated – use standalone mode)
- ⛔ Integrated drivers for other card providers (standalone terminal with manual confirmation)
- ⛔ Bluetooth / USB receipt printers (network ESC/POS or PDF only); raw network printing not possible on web
- 🟡 Auth tokens stored in the local sembast DB, not platform secure storage
