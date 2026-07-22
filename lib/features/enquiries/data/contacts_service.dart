import 'package:flutter/foundation.dart';
import 'package:fluttercontactpicker/fluttercontactpicker.dart';

import 'capture_draft.dart';

/// Name + phone lifted from a device contact, ready to prefill the manual add
/// form. Either field may be null when the contact lacks it.
class ContactPick {
  const ContactPick({this.name, this.phone});
  final String? name;
  final String? phone;
}

/// Opens the OS contact picker and returns the chosen contact's name + phone.
/// Abstracted so widgets depend on the interface (not the native plugin) and it
/// can be faked in tests.
abstract class ContactsService {
  /// Returns the picked contact, or null when the user simply cancelled the
  /// picker. Throws [ContactPickException] when the picker itself failed
  /// (permission denied, plugin/OS error) so the UI can surface a real message
  /// instead of silently doing nothing.
  Future<ContactPick?> pickContact();
}

/// A real failure opening the OS contact picker — distinct from the user
/// cancelling. Carries the underlying error for logging, not for display.
class ContactPickException implements Exception {
  const ContactPickException(this.cause);
  final Object cause;
  @override
  String toString() => 'ContactPickException: $cause';
}

/// Pure mapping from the native picker's output to a [ContactPick]: trims the
/// name and normalizes the phone to digits. No plugin calls, so it is unit
/// tested directly.
ContactPick contactToPrefill(String? fullName, String? rawNumber) {
  final name = fullName?.trim();
  return ContactPick(
    name: (name == null || name.isEmpty) ? null : name,
    phone: CaptureDraft.normalizePhone(rawNumber),
  );
}

/// Real implementation backed by the native OS contact picker. Uses only the
/// single-contact picker (no address-book enumeration); on Android 11+ the
/// plugin requests READ_CONTACTS at runtime.
class DeviceContactsService implements ContactsService {
  @override
  Future<ContactPick?> pickContact() async {
    try {
      final contact = await FlutterContactPicker.pickPhoneContact();
      return contactToPrefill(contact.fullName, contact.phoneNumber?.number);
    } on UserCancelledPickingException {
      // The user backed out without choosing — a genuine no-op, not an error.
      return null;
    } catch (e) {
      // Permission denied or a plugin/OS failure. Previously this was swallowed
      // identically to a cancel, so the button appeared dead. Surface it.
      debugPrint('contact pick failed: $e');
      throw ContactPickException(e);
    }
  }
}
