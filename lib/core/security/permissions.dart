import '../../data/models/org.dart';

enum Perm {
  refund,
  voidSale,
  discountOverLimit,
  priceOverride,
  cashMovement,
  noSale,
  closeRegister,
  manageAvailability,
  settings,
  createVatRate,
  staffPins,
  changeRegister,
  resetApp,
}

extension PermX on Perm {
  String get label => switch (this) {
        Perm.refund => 'Refund a sale',
        Perm.voidSale => 'Void a sale',
        Perm.discountOverLimit => 'Discount above cashier limit',
        Perm.priceOverride => 'Change an item price',
        Perm.cashMovement => 'Pay cash in or out',
        Perm.noSale => 'Open the cash drawer (no sale)',
        Perm.closeRegister => 'Close the register',
        Perm.manageAvailability => 'Change product availability',
        Perm.settings => 'Change till settings',
        Perm.createVatRate => 'Create a VAT rate for the organisation',
        Perm.staffPins => 'Manage staff PINs',
        Perm.changeRegister => 'Change register',
        Perm.resetApp => 'Reset the app',
      };

  PosRole get minimumRole => switch (this) {
        Perm.manageAvailability || Perm.noSale => PosRole.supervisor,
        Perm.refund || Perm.voidSale || Perm.discountOverLimit || Perm.priceOverride || Perm.cashMovement => PosRole.supervisor,
        Perm.closeRegister => PosRole.supervisor,
        Perm.settings || Perm.createVatRate || Perm.staffPins || Perm.changeRegister || Perm.resetApp => PosRole.manager,
      };
}

bool can(StaffMember? staff, Perm perm) => staff != null && staff.posRole.index >= perm.minimumRole.index;
